#pragma once

#include "identitymanager.h"
#include "nvapp.h"
#include "nvaddress.h"

#include <Limelight.h>

#include <QUrl>
#include <QNetworkAccessManager>
#include <QNetworkReply>

class NvComputer;

class NvDisplayMode
{
public:
    bool operator==(const NvDisplayMode& other) const
    {
        return width == other.width &&
                height == other.height &&
                refreshRate == other.refreshRate;
    }

    int width;
    int height;
    int refreshRate;
};
Q_DECLARE_TYPEINFO(NvDisplayMode, Q_PRIMITIVE_TYPE);

class GfeHttpResponseException : public std::exception
{
public:
    GfeHttpResponseException(int statusCode, QString message) :
        m_StatusCode(statusCode),
        m_StatusMessage(message)
    {

    }

    const char* what() const throw()
    {
        return m_StatusMessage.toLatin1();
    }

    const char* getStatusMessage() const
    {
        return m_StatusMessage.toLatin1();
    }

    int getStatusCode() const
    {
        return m_StatusCode;
    }

    QString toQString() const
    {
        return m_StatusMessage + " (Error " + QString::number(m_StatusCode) + ")";
    }

private:
    int m_StatusCode;
    QString m_StatusMessage;
};

class QtNetworkReplyException : public std::exception
{
public:
    QtNetworkReplyException(QNetworkReply::NetworkError error, QString errorText) :
        m_Error(error),
        m_ErrorText(errorText)
    {

    }

    const char* what() const throw()
    {
        return m_ErrorText.toLatin1();
    }

    const char* getErrorText() const
    {
        return m_ErrorText.toLatin1();
    }

    QNetworkReply::NetworkError getError() const
    {
        return m_Error;
    }

    QString toQString() const
    {
        return m_ErrorText + " (Error " + QString::number(m_Error) + ")";
    }

private:
    QNetworkReply::NetworkError m_Error;
    QString m_ErrorText;
};

class INvHTTP
{
public:
    enum NvLogLevel {
        NVLL_NONE,
        NVLL_ERROR,
        NVLL_VERBOSE
    };

    virtual ~INvHTTP() = default;

    virtual QString
    getServerInfo(NvLogLevel logLevel, bool fastFail = false) = 0;

    virtual QString
    openConnectionToString(QUrl baseUrl,
                           QString command,
                           QString arguments,
                           int timeoutMs,
                           NvLogLevel logLevel = NvLogLevel::NVLL_VERBOSE) = 0;

    virtual void setServerCert(QSslCertificate serverCert) = 0;

    virtual void setAddress(NvAddress address) = 0;
    virtual void setHttpsPort(uint16_t port) = 0;

    virtual NvAddress address() = 0;

    virtual QSslCertificate serverCert() = 0;

    virtual uint16_t httpPort() = 0;

    virtual uint16_t httpsPort() = 0;

    virtual void
    quitApp() = 0;

    virtual void
    startApp(QString verb,
             bool isGfe,
             int appId,
             PSTREAM_CONFIGURATION streamConfig,
             bool sops,
             bool localAudio,
             int gamepadMask,
             bool persistGameControllersOnDisconnect,
             QString& rtspSessionUrl) = 0;

    virtual QVector<NvApp>
    getAppList() = 0;

    virtual QImage
    getBoxArt(int appId) = 0;
};

class NvHTTP : public QObject, public INvHTTP
{
    Q_OBJECT

public:
    // Using declaration to make NvLogLevel available in NvHTTP scope if needed,
    // or just rely on inheritance.
    using NvLogLevel = INvHTTP::NvLogLevel;

    explicit NvHTTP(NvAddress address, uint16_t httpsPort, QSslCertificate serverCert, QNetworkAccessManager* nam = nullptr);

    explicit NvHTTP(NvComputer* computer, QNetworkAccessManager* nam = nullptr);

    static
    int
    getCurrentGame(QString serverInfo);

    QString
    getServerInfo(NvLogLevel logLevel, bool fastFail = false) override;

    static
    void
    verifyResponseStatus(QString xml);

    static
    QString
    getXmlString(QString xml,
                 QString tagName);

    static
    QByteArray
    getXmlStringFromHex(QString xml,
                        QString tagName);

    QString
    openConnectionToString(QUrl baseUrl,
                           QString command,
                           QString arguments,
                           int timeoutMs,
                           NvLogLevel logLevel = NvLogLevel::NVLL_VERBOSE) override;

    void setServerCert(QSslCertificate serverCert) override;

    void setAddress(NvAddress address) override;
    void setHttpsPort(uint16_t port) override;

    NvAddress address() override;

    QSslCertificate serverCert() override;

    uint16_t httpPort() override;

    uint16_t httpsPort() override;

    static
    QVector<int>
    parseQuad(QString quad);

    void
    quitApp() override;

    void
    startApp(QString verb,
             bool isGfe,
             int appId,
             PSTREAM_CONFIGURATION streamConfig,
             bool sops,
             bool localAudio,
             int gamepadMask,
             bool persistGameControllersOnDisconnect,
             QString& rtspSessionUrl) override;

    QVector<NvApp>
    getAppList() override;

    QImage
    getBoxArt(int appId) override;

    static
    QVector<NvDisplayMode>
    getDisplayModeList(QString serverInfo);

    QUrl m_BaseUrlHttp;
    QUrl m_BaseUrlHttps;
private:
    void
    handleSslErrors(QNetworkReply* reply, const QList<QSslError>& errors);

    QNetworkReply*
    openConnection(QUrl baseUrl,
                   QString command,
                   QString arguments,
                   int timeoutMs,
                   NvLogLevel logLevel);

    NvAddress m_Address;
    QNetworkAccessManager* m_Nam;
    QSslCertificate m_ServerCert;
};
