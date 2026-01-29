#include "autoupdatechecker.h"
#include "settings/streamingpreferences.h"

#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QFile>
#include <QtConcurrent>

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

#if defined(Q_OS_WIN32) || defined(Q_OS_DARWIN) || defined(STEAM_LINK) || defined(APP_IMAGE) // Only run update checker on platforms without auto-update
    if (url.isLocalFile()) {
        // Run local file check asynchronously to avoid blocking the main thread
        // when accessing network shares (UNC paths) that might be unavailable.
        QString localFile = url.toLocalFile();
        QString host = url.host();
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

#if QT_VERSION >= QT_VERSION_CHECK(5, 14, 0) && QT_VERSION < QT_VERSION_CHECK(5, 15, 1) && !defined(QT_NO_BEARERMANAGEMENT)
    // HACK: Set network accessibility to work around QTBUG-80947 (introduced in Qt 5.14.0 and fixed in Qt 5.15.1)
    QT_WARNING_PUSH
    QT_WARNING_DISABLE_DEPRECATED
    m_Nam->setNetworkAccessible(QNetworkAccessManager::Accessible);
    QT_WARNING_POP
#endif

    qDebug() << "Checking for updates at:" << url;
    QNetworkRequest req(url);
    req.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::AlwaysNetwork);
    
    // [FIX] We MUST capture the reply object to set the property on it.
    // Previously, we just called m_Nam->get(req) without assigning the return value,
    // so the subsequent setProperty() call was missing or invalid, leading to isManual being lost.
    QNetworkReply *reply = m_Nam->get(req);
    
    // Store the manual check state in the reply object to avoid race conditions
    // This property is retrieved in handleUpdateCheckRequestFinished to determine if we should show UI.
    reply->setProperty("isManual", isManual);
#endif
}

void AutoUpdateChecker::parseStringToVersionQuad(QString& string, QVector<int>& version)
{
    QStringList list = string.split('.');
    for (const QString& component : list) {
        version.append(component.toInt());
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

int AutoUpdateChecker::compareVersion(QVector<int>& version1, QVector<int>& version2) {
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
                    emit updateAvailable(updateObj["version"].toString(),
                                            updateObj["browser_url"].toString(), isManual);
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
