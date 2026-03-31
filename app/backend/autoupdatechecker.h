#pragma once

#include <QObject>
#include <QNetworkAccessManager>
#include <QFile>

class AutoUpdateChecker : public QObject
{
    Q_OBJECT
public:
    explicit AutoUpdateChecker(QObject *parent = nullptr);

    Q_INVOKABLE void start(bool isManual = false);
    Q_INVOKABLE bool openUpdateUrl(QString url);

signals:
    void updateAvailable(QString newVersion, QString url, bool isManual);
    void patchAvailable(QString newVersion, QString patchUrl, QString fullUrl, bool isManual);
    void noUpdateAvailable(bool isManual);
    void updateCheckFailed(QString errorMessage, bool isManual);
    void patchDownloadProgress(qint64 received, qint64 total);
    void patchDownloadFinished(QString patchPath, bool isManual);
    void patchApplyProgress(int percent);
    void patchApplyFinished(bool success, QString errorMessage);

private slots:
    void handleUpdateCheckRequestFinished(QNetworkReply* reply);
    void onUpdateManifestReceived(const QByteArray& data, bool isManual);
    void onUpdateCheckFailed(const QString& errorMessage, bool isManual);
    void onPatchDownloadProgress(qint64 received, qint64 total);
    void onPatchDownloadFinished(QNetworkReply* reply);
    void onPatchApplyStarted();
    void onPatchApplyProgress(int percent);
    void onPatchApplyFinished(bool success, QString errorMessage);

private:
    void parseStringToVersionQuad(const QString& string, QVector<int>& version);
    int compareVersion(const QVector<int>& version1, const QVector<int>& version2);
    QString getPlatform();
    void downloadPatch(QString patchUrl, QString savePath, bool isManual);
    void applyPatch(QString patchPath, bool isManual);
    QString getInstallPath();
    QString getTempPatchPath();

    QVector<int> m_CurrentVersionQuad;
    QNetworkAccessManager* m_Nam;
    QNetworkAccessManager* m_PatchDownloader;
    bool m_CheckInProgress;
    bool m_PatchDownloadInProgress;
    QUrl m_ManifestUrl;
    QString m_PendingPatchPath;
    bool m_IsManualUpdate;
    QString m_FullUpdateUrl;
    QString m_NewVersion;
};
