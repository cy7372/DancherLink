/*
 * DancherLink Patcher - Incremental Update Tool
 * Applies binary patches to update the installation
 */

#include <QCoreApplication>
#include <QCommandLineParser>
#include <QCommandLineOption>
#include <QFile>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDebug>
#include <QCryptographicHash>
#include <QIODevice>

#ifdef Q_OS_WIN32
#include <windows.h>
#endif

// Simple diff/patch implementation based on BSDiff algorithm
// This is a simplified version for demonstration
// For production use, consider using the full bsdiff library

struct PatchHeader {
    QByteArray magic;      // "DANCHERPATCH"
    quint32 version;       // Patch format version
    quint64 sourceSize;    // Expected source file size
    quint64 targetSize;    // Target file size after patch
    quint32 fileCount;     // Number of files to patch
};

struct FileEntry {
    QString relativePath;  // Relative path from install directory
    quint64 sourceSize;    // Original file size
    quint64 targetSize;    // New file size
    QByteArray sourceHash; // SHA256 of original file
    QByteArray targetHash; // SHA256 of new file
    QByteArray diffData;   // Binary diff (compressed)
    bool isAdded;          // New file (no source)
    bool isDeleted;        // File to be removed
    bool isReplaced;       // Replace entire file (diffData is full content)
};

class Patcher {
public:
    Patcher(const QString& patchPath, const QString& installDir)
        : m_patchPath(patchPath), m_installDir(installDir) {}

    bool apply() {
        qDebug() << "Opening patch file:" << m_patchPath;

        QFile patchFile(m_patchPath);
        if (!patchFile.open(QIODevice::ReadOnly)) {
            qCritical() << "Failed to open patch file:" << patchFile.errorString();
            return false;
        }

        // Read and verify header
        PatchHeader header;
        header.magic = patchFile.read(12);
        if (header.magic != "DANCHERPATCH") {
            qCritical() << "Invalid patch format";
            return false;
        }

        header.version = readQuint32(patchFile);
        if (header.version != 1) {
            qCritical() << "Unsupported patch version:" << header.version;
            return false;
        }

        header.sourceSize = readQuint64(patchFile);
        header.targetSize = readQuint64(patchFile);
        header.fileCount = readQuint32(patchFile);

        qDebug() << "Patch version:" << header.version;
        qDebug() << "Files to patch:" << header.fileCount;

        // Read file entries
        for (quint32 i = 0; i < header.fileCount; i++) {
            FileEntry entry = readFileEntry(patchFile);
            if (!applyFileEntry(entry)) {
                return false;
            }

            // Report progress
            int percent = (i + 1) * 100 / header.fileCount;
            qDebug().noquote() << QString("Progress: %1% (%2/%3 files)").arg(percent).arg(i + 1).arg(header.fileCount);
        }

        patchFile.close();
        qDebug() << "Patch applied successfully!";
        return true;
    }

private:
    QString m_patchPath;
    QString m_installDir;

    quint32 readQuint32(QFile& file) {
        QByteArray data = file.read(4);
        if (data.size() != 4) return 0;
        return (quint32(data[0]) << 24) | (quint32(data[1]) << 16) |
               (quint32(data[2]) << 8) | quint32(data[3]);
    }

    quint64 readQuint64(QFile& file) {
        QByteArray data = file.read(8);
        if (data.size() != 8) return 0;
        return (quint64(data[0]) << 56) | (quint64(data[1]) << 48) |
               (quint64(data[2]) << 40) | (quint64(data[3]) << 32) |
               (quint64(data[4]) << 24) | (quint64(data[5]) << 16) |
               (quint64(data[6]) << 8) | quint64(data[7]);
    }

    QString readString(QFile& file) {
        quint32 len = readQuint32(file);
        return QString::fromUtf8(file.read(len));
    }

    QByteArray readByteArray(QFile& file) {
        quint32 len = readQuint32(file);
        return file.read(len);
    }

    FileEntry readFileEntry(QFile& file) {
        FileEntry entry;
        entry.relativePath = readString(file);
        entry.sourceSize = readQuint64(file);
        entry.targetSize = readQuint64(file);
        entry.sourceHash = readByteArray(file);
        entry.targetHash = readByteArray(file);
        entry.isAdded = file.read(1)[0] != 0;
        entry.isDeleted = file.read(1)[0] != 0;
        entry.isReplaced = file.read(1)[0] != 0;
        entry.diffData = readByteArray(file);
        return entry;
    }

    bool applyFileEntry(const FileEntry& entry) {
        QString fullPath = QDir(m_installDir).filePath(entry.relativePath);
        QFileInfo fi(fullPath);

        if (entry.isDeleted) {
            qDebug() << "Deleting:" << entry.relativePath;
            if (fi.isFile()) {
                QFile::remove(fullPath);
            }
            return true;
        }

        if (entry.isReplaced) {
            qDebug() << "Replacing:" << entry.relativePath;
            return writeFile(fullPath, entry.diffData);
        }

        if (entry.isAdded) {
            qDebug() << "Adding:" << entry.relativePath;
            return writeFile(fullPath, entry.diffData);
        }

        // Verify source file
        if (!fi.isFile()) {
            qCritical() << "Source file not found:" << entry.relativePath;
            return false;
        }

        QFile srcFile(fullPath);
        if (!srcFile.open(QIODevice::ReadOnly)) {
            qCritical() << "Failed to open source file:" << entry.relativePath;
            return false;
        }

        QByteArray sourceData = srcFile.readAll();
        srcFile.close();

        // Verify source hash
        QByteArray actualHash = QCryptographicHash::hash(sourceData, QCryptographicHash::Sha256);
        if (actualHash != entry.sourceHash) {
            qCritical() << "Source file hash mismatch:" << entry.relativePath;
            qCritical() << "Expected:" << entry.sourceHash.toHex();
            qCritical() << "Actual:" << actualHash.toHex();
            return false;
        }

        // Apply diff (simplified - in production, use actual bsdiff)
        QByteArray targetData = applyDiff(sourceData, entry.diffData, entry.targetSize);
        if (targetData.isEmpty()) {
            qCritical() << "Failed to apply diff:" << entry.relativePath;
            return false;
        }

        // Verify target hash
        QByteArray targetHash = QCryptographicHash::hash(targetData, QCryptographicHash::Sha256);
        if (targetHash != entry.targetHash) {
            qCritical() << "Target hash verification failed:" << entry.relativePath;
            return false;
        }

        return writeFile(fullPath, targetData);
    }

    QByteArray applyDiff(const QByteArray& source, const QByteArray& diffData, quint64 targetSize) {
        // Simplified implementation - just returns the diffData for "replace" operations
        // In production, implement actual BSDiff algorithm here

        // If diffData size matches targetSize, it's a full replacement
        if (quint64(diffData.size()) == targetSize) {
            return diffData;
        }

        // For actual diff, we would use bsdiff here
        // For now, return empty to indicate failure
        qWarning() << "Binary diff not implemented, using fallback";
        return QByteArray();
    }

    bool writeFile(const QString& path, const QByteArray& data) {
        // Create directory if needed
        QDir dir = QFileInfo(path).dir();
        if (!dir.exists()) {
            dir.mkpath(".");
        }

        QFile file(path);
        if (!file.open(QIODevice::WriteOnly)) {
            qCritical() << "Failed to open file for writing:" << path << file.errorString();
            return false;
        }

        if (file.write(data) != data.size()) {
            qCritical() << "Failed to write file:" << path;
            file.close();
            QFile::remove(path);
            return false;
        }

        file.close();
        return true;
    }
};

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    QCoreApplication::setApplicationName("DancherLink Patcher");
    QCoreApplication::setApplicationVersion("1.0.0");

    QCommandLineParser parser;
    parser.setApplicationDescription("Apply incremental updates to DancherLink installation");
    parser.addHelpOption();
    parser.addVersionOption();

    parser.addPositionalArgument("command", "Command to execute (apply, create, verify)");
    parser.addPositionalArgument("patch", "Patch file path (for apply command)");
    parser.addPositionalArgument("installDir", "Installation directory (for apply command)");

    parser.process(app);

    const QStringList args = parser.positionalArguments();
    if (args.size() < 1) {
        qCritical() << "Usage: DancherLink.Patcher.exe <command> [args...]";
        qCritical() << "Commands:";
        qCritical() << "  apply <patch.patch> <installDir>  - Apply a patch";
        qCritical() << "  create <oldDir> <newDir> <out.patch> - Create a patch";
        return 1;
    }

    QString command = args[0];

    if (command == "apply") {
        if (args.size() < 3) {
            qCritical() << "Usage: apply <patch.patch> <installDir>";
            return 1;
        }
        QString patchPath = args[1];
        QString installDir = args[2];

        if (!QFile::exists(patchPath)) {
            qCritical() << "Patch file not found:" << patchPath;
            return 1;
        }

        if (!QDir(installDir).exists()) {
            qCritical() << "Installation directory not found:" << installDir;
            return 1;
        }

        Patcher patcher(patchPath, installDir);
        bool success = patcher.apply();
        return success ? 0 : 1;

    } else if (command == "create") {
        if (args.size() < 4) {
            qCritical() << "Usage: create <oldDir> <newDir> <out.patch>";
            return 1;
        }
        qCritical() << "Patch creation not implemented in this version";
        qCritical() << "Use the Python script: python scripts/create_patch.py";
        return 1;

    } else if (command == "verify") {
        qCritical() << "Verify command not implemented yet";
        return 1;

    } else {
        qCritical() << "Unknown command:" << command;
        return 1;
    }
}
