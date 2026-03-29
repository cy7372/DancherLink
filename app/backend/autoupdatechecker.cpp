#include <QStandardPaths>
#include <QDateTime>
#include "autoupdatechecker.h"
#include "settings/streamingpreferences.h"

#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QFile>
#include <QtConcurrent>
#include <QDesktopServices>
#include <QDir>

#ifdef Q_OS_WIN32
#include <windows.h>
#include <shellapi.h>
#endif

AutoUpdateChecker::AutoUpdateChecker(QObject *parent) :
    QObject(parent)
{
    m_Nam = new QNetworkAccessManager(this);

    // Never communicate over HTTP
    m_Nam->setStrictTransportSecurityEnabled(true);

    // Allow HTTP redirects
    m_Nam->setRedirectPolicy(QNetworkRequest::NoLessSafeRedirectPolicy);

    connect(m_Nam, &QNetworkAccessManager::finished,
            this, &AutoUpdateChecker::handleUpdateCheckRequestFinished);

    QString currentVersion(VERSION_STR);
    qDebug() << "Current Moonlight version:" << currentVersion;
    parseStringToVersionQuad(currentVersion, m_CurrentVersionQuad);

    // Should at least have a 1.0-style version number
    Q_ASSERT(m_CurrentVersionQuad.count() > 1);
}

void AutoUpdateChecker::start(bool isManual)
{
    qDebug() << "AutoUpdateChecker::start(isManual=" << isManual << ")";

    // Recreate the network manager if it was deleted
    // [FIX] We must recreate m_Nam if it's null, otherwise subsequent manual checks will fail
    // because m_Nam is deleted after each request in handleUpdateCheckRequestFinished.
    if (!m_Nam) {
        m_Nam = new QNetworkAccessManager(this);
        // Never communicate over HTTP
        m_Nam->setStrictTransportSecurityEnabled(true);
        // Allow HTTP redirects
        m_Nam->setRedirectPolicy(QNetworkRequest::NoLessSafeRedirectPolicy);
        connect(m_Nam, &QNetworkAccessManager::finished,
                this, &AutoUpdateChecker::handleUpdateCheckRequestFinished);
    }

    QString updateUrl = StreamingPreferences::get()->getUpdateSubscriptionUrl();
    if (updateUrl.isEmpty()) {
        qDebug() << "Auto-update check skipped: No subscription URL configured";
        emit updateCheckFailed("No subscription URL configured", isManual);
        return;
    }

    QUrl url(updateUrl);
    if (url.scheme().isEmpty()) {
        // If no scheme is provided, assume it's a local file path
        url = QUrl::fromLocalFile(updateUrl);
    }
    
    // Store the manifest URL for relative path resolution later
    m_ManifestUrl = url;

#if defined(Q_OS_WIN32) || defined(Q_OS_DARWIN) || defined(STEAM_LINK) || defined(APP_IMAGE) // Only run update checker on platforms without auto-update
    if (url.isLocalFile()) {
        // Run local file check asynchronously to avoid blocking the main thread
        // when accessing network shares (UNC paths) that might be unavailable.
        QString localFile = url.toLocalFile();
        QString host = url.host();

        // If toLocalFile returns empty (e.g. invalid file:// URL), try to use the string as is if it looks like a path
        if (localFile.isEmpty()) {
            QString urlStr = url.toString();
            if (urlStr.startsWith("file:///")) {
                localFile = urlStr.mid(8);
            } else if (urlStr.startsWith("file://")) {
                localFile = urlStr.mid(7);
            }
        }
        
        QtConcurrent::run([this, localFile, host, isManual]() {
            // If we have a hostname (UNC path), try to ping port 445 (SMB) first
            // to fail fast if the host is offline.
            if (!host.isEmpty()) {
                QTcpSocket socket;
                socket.connectToHost(host, 445); // SMB port
                if (!socket.waitForConnected(200)) { // 200ms timeout
                    qWarning() << "Update host" << host << "is unreachable (port 445)";
                    QMetaObject::invokeMethod(this, "onUpdateCheckFailed",
                                              Qt::QueuedConnection,
                                              Q_ARG(QString, "Update server unreachable"),
                                              Q_ARG(bool, isManual));
                    return;
                }
                socket.disconnectFromHost();
            }

            QFile file(localFile);
            if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
                QByteArray data = file.readAll();
                QMetaObject::invokeMethod(this, "onUpdateManifestReceived",
                                          Qt::QueuedConnection,
                                          Q_ARG(QByteArray, data),
                                          Q_ARG(bool, isManual));
            } else {
                QString error = file.errorString();
                qWarning() << "Failed to open local update file:" << localFile << ":" << error;
                QMetaObject::invokeMethod(this, "onUpdateCheckFailed",
                                          Qt::QueuedConnection,
                                          Q_ARG(QString, "File error: " + error),
                                          Q_ARG(bool, isManual));
            }
        });
        return;
    }

    qDebug() << "Checking for updates at:" << url;
    QNetworkRequest req(url);
    req.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::AlwaysNetwork);
    
    QNetworkReply *reply = m_Nam->get(req);
    reply->setProperty("isManual", isManual);
#else
    Q_UNUSED(isManual);
#endif
}

bool AutoUpdateChecker::openUpdateUrl(QString urlStr)
{
    QUrl url(urlStr);

#if defined(Q_OS_WIN32)
    // On Windows, Qt's openUrlExternally (ShellExecute) often fails with Access Denied (error 5)
    // when using file:/// URLs pointing to executables/MSIs.
    // We try to invoke ShellExecute directly with a native file path to workaround this.
    if (url.scheme() == "file" || url.scheme().isEmpty()) {
        QString localPath = url.toLocalFile();
        if (localPath.isEmpty()) {
            // If toLocalFile returns empty (e.g. invalid file:// URL), try to use the string as is if it looks like a path
            if (urlStr.startsWith("file:///")) {
                localPath = urlStr.mid(8);
            } else if (urlStr.startsWith("file://")) {
                localPath = urlStr.mid(7);
            } else {
                localPath = urlStr;
            }
        }

        // Normalize path (convert / to \)
        localPath = QDir::toNativeSeparators(localPath);

        qDebug() << "Attempting to open local update file via ShellExecute:" << localPath;

        // ShellExecuteW
        HINSTANCE result = ShellExecuteW(nullptr, L"open",
                                       reinterpret_cast<const wchar_t*>(localPath.utf16()),
                                       nullptr, nullptr, SW_SHOWNORMAL);

        // If File Not Found (SE_ERR_FNF = 2), it might be due to spaces in the path or other parsing issues.
        // Try quoting the path.
        if (reinterpret_cast<intptr_t>(result) == 2) { // SE_ERR_FNF
            qWarning() << "ShellExecute failed with File Not Found (Error 2). Trying with quoted path...";
            QString quotedPath = QString("\"%1\"").arg(localPath);
            result = ShellExecuteW(nullptr, L"open",
                                   reinterpret_cast<const wchar_t*>(quotedPath.utf16()),
                                   nullptr, nullptr, SW_SHOWNORMAL);
        }

        // If Access Denied (SE_ERR_ACCESSDENIED = 5), try 'runas' to request elevation
        if (reinterpret_cast<intptr_t>(result) == 5) { // SE_ERR_ACCESSDENIED
             qWarning() << "ShellExecute failed with Access Denied (Error 5). Trying 'runas' verb...";
             
             QString targetPath = localPath;
             bool isMsi = localPath.endsWith(".msi", Qt::CaseInsensitive);

             // MSI Special Handling:
             // If we're elevating, msiexec running as admin might not see network drives
             // or might have trouble with permissions in user-private folders.
             // We use QDir::temp() which typically resolves to %TEMP%.
             // On Windows, if we are elevating to the SAME user (just Admin token), this works fine.
             // If elevating to a different Admin user, they might not read this user's temp, but standard UAC flow usually keeps the user context.
             if (isMsi) {
                 QString fileName = QFileInfo(localPath).fileName();
                 // Insert a random component to ensure uniqueness
                 QString uniqueName = QString("%1_%2").arg(QDateTime::currentMSecsSinceEpoch()).arg(fileName);

                 // Use AppLocalDataLocation (e.g. AppData/Local/DancherLink) which is writable and safe
                 QString appDataPath = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
                 QDir appDataDir(appDataPath);
                 if (!appDataDir.exists()) {
                     appDataDir.mkpath(".");
                 }
                 
                 // Create an 'updates' subdirectory
                 QString updateDirPath = appDataDir.filePath("updates");
                 QDir updateDir(updateDirPath);
                 if (!updateDir.exists()) {
                     updateDir.mkpath(".");
                 }

                 QString targetMsiPath = updateDir.filePath(uniqueName);
                 targetPath = QDir::toNativeSeparators(targetMsiPath);

                 // Clean up old updates in this directory to save space
                 QFileInfoList oldFiles = updateDir.entryInfoList(QStringList() << "*.msi", QDir::Files, QDir::Time | QDir::Reversed);
                 for (int i = 5; i < oldFiles.size(); ++i) {
                     // Keep the 5 most recent files, delete others
                     QFile::remove(oldFiles.at(i).absoluteFilePath());
                 }

                 qDebug() << "Copying MSI to AppData for elevation:" << localPath << "->" << targetPath;
                 
                 // Try to open source file with shared read access to avoid sharing violation if it's still open
                 QFile srcFile(localPath);
                 
                 // If normal copy fails, try manual read/write
                 if (!srcFile.copy(targetPath)) {
                     qWarning() << "QFile::copy failed, trying manual read/write:" << srcFile.errorString();
                     
                     if (srcFile.open(QIODevice::ReadOnly)) {
                         QFile destFile(targetPath);
                         if (destFile.open(QIODevice::WriteOnly)) {
                             // Copy in chunks
                             const qint64 bufferSize = 1024 * 1024; // 1MB buffer
                             char *buffer = new char[bufferSize];
                             qint64 bytesRead = 0;
                             bool writeSuccess = true;
                             
                             while ((bytesRead = srcFile.read(buffer, bufferSize)) > 0) {
                                 if (destFile.write(buffer, bytesRead) != bytesRead) {
                                     writeSuccess = false;
                                     break;
                                 }
                             }
                             
                             delete[] buffer;
                             srcFile.close();
                             destFile.close();
                             
                             if (!writeSuccess) {
                                 qWarning() << "Manual copy failed during write to:" << targetPath;
                                 QFile::remove(targetPath); // Cleanup incomplete file
                             }
                         } else {
                             qWarning() << "Failed to open dest file for write:" << targetPath << destFile.errorString();
                             srcFile.close();
                         }
                     } else {
                         qWarning() << "Failed to open source file for read:" << localPath << srcFile.errorString();
                     }
                 }
                 
                 // Check if destination exists after either copy method
                 if (QFile::exists(targetPath)) {
                     // Success
                 } else {
                     qWarning() << "Failed to copy MSI to AppData:" << targetPath;
                     
                     // Fallback to Temp if AppData fails (unlikely, but possible)
                     QString tempPath = QDir::temp().filePath(uniqueName);
                     if (srcFile.copy(tempPath)) {
                         targetPath = QDir::toNativeSeparators(tempPath);
                         qDebug() << "Copied to Temp as fallback:" << targetPath;
                     } else {
                         qWarning() << "Failed to copy MSI to Temp:" << tempPath << "Error:" << srcFile.errorString();
                     }
                 }
             }

             if (isMsi) {
                 // Use /i for install
                 QString params = QString("/i \"%1\"").arg(targetPath);
                 result = ShellExecuteW(nullptr, L"runas",
                                        L"msiexec.exe",
                                        reinterpret_cast<const wchar_t*>(params.utf16()),
                                        nullptr, SW_SHOWNORMAL);
             } else {
                 result = ShellExecuteW(nullptr, L"runas",
                                        reinterpret_cast<const wchar_t*>(targetPath.utf16()),
                                        nullptr, nullptr, SW_SHOWNORMAL);
             }
        }

        if (reinterpret_cast<intptr_t>(result) > 32) {
            return true;
        } else {
            qWarning() << "ShellExecute failed for local path:" << localPath << "Error:" << result;
            // Fallback to standard Qt open
        }
    }
#endif

    return QDesktopServices::openUrl(url);
}

void AutoUpdateChecker::parseStringToVersionQuad(const QString& string, QVector<int>& version)
{
    // Remove any suffix after the last numeric component (e.g., "-beta" from "1.0.11.181-beta")
    // Find the position where we have only digits and dots
    QString cleanString = string;
    int i = 0;
    for (; i < cleanString.length(); i++) {
        QChar c = cleanString[i];
        if (!c.isDigit() && c != QLatin1Char('.')) {
            // Found non-numeric, non-dot character, truncate here
            cleanString = cleanString.left(i);
            break;
        }
    }

    QStringList list = cleanString.split('.');
    for (const QString& component : list) {
        if (!component.isEmpty()) {
            version.append(component.toInt());
        }
    }
}

QString AutoUpdateChecker::getPlatform()
{
#if defined(STEAM_LINK)
    return QStringLiteral("steamlink");
#elif defined(APP_IMAGE)
    return QStringLiteral("appimage");
#elif defined(Q_OS_DARWIN) && QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
    // Qt 6 changed this from 'osx' to 'macos'. Use the old one
    // to be consistent (and not require another entry in the manifest).
    return QStringLiteral("osx");
#else
    return QSysInfo::productType();
#endif
}

int AutoUpdateChecker::compareVersion(const QVector<int>& version1, const QVector<int>& version2) {
    for (int i = 0;; i++) {
        int v1Val = 0;
        int v2Val = 0;

        // Treat missing decimal places as 0
        if (i < version1.count()) {
            v1Val = version1[i];
        }
        if (i < version2.count()) {
            v2Val = version2[i];
        }
        if (i >= version1.count() && i >= version2.count()) {
            // Equal versions
            return 0;
        }

        if (v1Val < v2Val) {
            return -1;
        }
        else if (v1Val > v2Val) {
            return 1;
        }
    }
}

void AutoUpdateChecker::handleUpdateCheckRequestFinished(QNetworkReply* reply)
{
    Q_ASSERT(reply->isFinished());

    // Retrieve the manual check state from the reply object
    bool isManual = reply->property("isManual").toBool();

    // Delete the QNetworkAccessManager to free resources and
    // prevent the bearer plugin from polling in the background.
    m_Nam->deleteLater();
    m_Nam = nullptr;

    if (reply->error() == QNetworkReply::NoError) {
        // Read all data and queue the reply for deletion
        QByteArray data = reply->readAll();
        reply->deleteLater();

        onUpdateManifestReceived(data, isManual);
    }
    else {
        qWarning() << "Update checking failed with error:" << reply->error();
        onUpdateCheckFailed("Network error: " + reply->errorString(), isManual);
        reply->deleteLater();
    }
}

void AutoUpdateChecker::onUpdateCheckFailed(const QString& errorMessage, bool isManual)
{
    m_CheckInProgress = false;
    emit updateCheckFailed(errorMessage, isManual);
}

void AutoUpdateChecker::onUpdateManifestReceived(const QByteArray& data, bool isManual)
{
    QString jsonString = QString::fromUtf8(data);

    QJsonParseError error;
    QJsonDocument jsonDoc = QJsonDocument::fromJson(jsonString.toUtf8(), &error);
    if (jsonDoc.isNull()) {
        qWarning() << "Update manifest malformed:" << error.errorString();
        onUpdateCheckFailed("Update manifest malformed: " + error.errorString(), isManual);
        return;
    }

    QJsonArray array;
    if (jsonDoc.isArray()) {
            array = jsonDoc.array();
    } else if (jsonDoc.isObject()) {
            // Handle the case where the JSON is a single object instead of an array
            array.append(jsonDoc.object());
    } else {
        qWarning() << "Update manifest doesn't contain an array or object";
        onUpdateCheckFailed("Update manifest is invalid", isManual);
        return;
    }

    if (array.isEmpty()) {
        qWarning() << "Update manifest doesn't contain an array";
        onUpdateCheckFailed("Update manifest is empty", isManual);
        return;
    }

    for (QJsonValueRef updateEntry : array) {
        if (updateEntry.isObject()) {
            QJsonObject updateObj = updateEntry.toObject();
            if (!updateObj.contains("platform") ||
                    !updateObj.contains("arch") ||
                    !updateObj.contains("version") ||
                    !updateObj.contains("browser_url")) {
                qWarning() << "Update manifest entry missing vital field";
                continue;
            }

            if (!updateObj["platform"].isString() ||
                    !updateObj["arch"].isString() ||
                    !updateObj["version"].isString() ||
                    !updateObj["browser_url"].isString()) {
                qWarning() << "Update manifest entry has unexpected vital field type";
                continue;
            }

            // Check if this entry is for Beta channel
            bool isBetaEntry = updateObj.contains("isBeta") && updateObj["isBeta"].toBool();

            // Determine if current build is Beta (4+ version segments) or Release (3 segments)
            bool isCurrentBeta = m_CurrentVersionQuad.count() >= 4;

            // Only match Beta entries to Beta builds, and Release entries to Release builds
            if (isBetaEntry != isCurrentBeta) {
                qDebug() << "Skipping manifest entry (Beta mismatch): current=" << isCurrentBeta << " entry=" << isBetaEntry;
                continue;
            }

            if (updateObj["arch"] == QSysInfo::buildCpuArchitecture() &&
                    updateObj["platform"] == getPlatform()) {

                // Check the kernel version minimum if one exists
                if (updateObj.contains("kernel_version_at_least") && updateObj["kernel_version_at_least"].isString()) {
                    QVector<int> requiredVersionQuad;
                    QVector<int> actualVersionQuad;

                    QString requiredVersion = updateObj["kernel_version_at_least"].toString();
                    QString actualVersion = QSysInfo::kernelVersion();
                    parseStringToVersionQuad(requiredVersion, requiredVersionQuad);
                    parseStringToVersionQuad(actualVersion, actualVersionQuad);

                    if (compareVersion(actualVersionQuad, requiredVersionQuad) < 0) {
                        qDebug() << "Skipping manifest entry due to kernel version (" << actualVersion << "<" << requiredVersion << ")";
                        continue;
                    }
                }

                qDebug() << "Found update manifest match for current platform";

                QString latestVersion = updateObj["version"].toString();
                qDebug() << "Latest version of DancherLink for this platform is:" << latestVersion;

                QVector<int> latestVersionQuad;
                parseStringToVersionQuad(latestVersion, latestVersionQuad);

                int res = compareVersion(m_CurrentVersionQuad, latestVersionQuad);
                m_CheckInProgress = false;
                if (res < 0) {
                    // m_CurrentVersionQuad < latestVersionQuad
                    qDebug() << "Update available";
                    
                    // Resolve the browser URL against the manifest URL
                    QString rawUrl = updateObj["browser_url"].toString();
                    QUrl resolvedUrl = m_ManifestUrl.resolved(QUrl(rawUrl));
                    
                    emit updateAvailable(updateObj["version"].toString(),
                                            resolvedUrl.toString(), isManual);
                    return;
                }
                else if (res > 0) {
                    qDebug() << "Update manifest version lower than current version";
                    emit noUpdateAvailable(isManual);
                    return;
                }
                else {
                    qDebug() << "Update manifest version equal to current version";
                    emit noUpdateAvailable(isManual);
                    return;
                }
            }
        }
        else {
            qWarning() << "Update manifest contained unrecognized entry:" << updateEntry.toString();
        }
    }

    qWarning() << "No entry in update manifest found for current platform:"
                << QSysInfo::buildCpuArchitecture() << getPlatform() << QSysInfo::kernelVersion();
    onUpdateCheckFailed("No update entry found for this platform", isManual);
}
