#pragma once

#include <QObject>
#include <QNetworkAccessManager>

class AutoUpdateChecker : public QObject
{
    Q_OBJECT
public:
    explicit AutoUpdateChecker(QObject *parent = nullptr);

    Q_INVOKABLE void start(bool isManual = false);
    Q_INVOKABLE bool openUpdateUrl(QString url);

signals:
    void updateAvailable(QString newVersion, QString url, bool isManual);
    void noUpdateAvailable(bool isManual);
    void updateCheckFailed(QString errorMessage, bool isManual);

private slots:
    void handleUpdateCheckRequestFinished(QNetworkReply* reply);
    void onUpdateManifestReceived(const QByteArray& data, bool isManual);
    void onUpdateCheckFailed(const QString& errorMessage, bool isManual);

private:
    void parseStringToVersionQuad(const QString& string, QVector<int>& version);

    int compareVersion(const QVector<int>& version1, const QVector<int>& version2);

    QString getPlatform();

    QVector<int> m_CurrentVersionQuad;
    QNetworkAccessManager* m_Nam;
    bool m_CheckInProgress;
    QUrl m_ManifestUrl;
};
