#pragma once

#include "backend/boxartmanager.h"
#include "backend/computermanager.h"
#include "streaming/session.h"
#include "streaming/networkqualitymonitor.h"
#include "utils/latencymeasurer.h"

#include <QAbstractListModel>
#include <QTimer>

class AppModel : public QAbstractListModel
{
    Q_OBJECT

    Q_PROPERTY(int networkLatencyMs READ networkLatencyMs NOTIFY networkLatencyChanged)
    Q_PROPERTY(QString networkQualityString READ networkQualityString NOTIFY networkLatencyChanged)
    Q_PROPERTY(float packetLossRate READ packetLossRate NOTIFY packetLossRateChanged)
    Q_PROPERTY(QString networkQualityDetailed READ networkQualityDetailed NOTIFY networkStatusChanged)
    Q_PROPERTY(int recommendedBitrate READ recommendedBitrate NOTIFY networkStatusChanged)

    // Audio quality properties
    Q_PROPERTY(QString audioQualityString READ audioQualityString NOTIFY audioQualityChanged)
    Q_PROPERTY(float audioPacketLossRate READ audioPacketLossRate NOTIFY audioQualityChanged)
    Q_PROPERTY(QString audioQualityDetailed READ audioQualityDetailed NOTIFY audioQualityChanged)

    enum Roles
    {
        NameRole = Qt::UserRole,
        RunningRole,
        BoxArtRole,
        HiddenRole,
        AppIdRole,
        DirectLaunchRole,
        AppCollectorGameRole,
    };

public:
    explicit AppModel(QObject *parent = nullptr);
    ~AppModel();

    // Must be called before any QAbstractListModel functions
    Q_INVOKABLE void initialize(ComputerManager* computerManager, int computerIndex, bool showHiddenGames);

    Q_INVOKABLE Session* createSessionForApp(int appIndex);

    Q_INVOKABLE int getDirectLaunchAppIndex();

    Q_INVOKABLE int getRunningAppId();

    Q_INVOKABLE QString getRunningAppName();

    Q_INVOKABLE void quitRunningApp();

    Q_INVOKABLE void setAppHidden(int appIndex, bool hidden);

    Q_INVOKABLE void setAppDirectLaunch(int appIndex, bool directLaunch);

    Q_INVOKABLE void createDesktopShortcut(int appIndex);

    int networkLatencyMs() const;
    QString networkQualityString() const;
    float packetLossRate() const;
    QString networkQualityDetailed() const;
    int recommendedBitrate() const;

    // Audio quality methods
    QString audioQualityString() const;
    float audioPacketLossRate() const;
    QString audioQualityDetailed() const;

    QVariant data(const QModelIndex &index, int role) const override;

    int rowCount(const QModelIndex &parent) const override;

    virtual QHash<int, QByteArray> roleNames() const override;

    // Called from QML to start/stop latency measurement for this computer
    Q_INVOKABLE void startLatencyMeasurement();
    Q_INVOKABLE void stopLatencyMeasurement();

private slots:
    void handleComputerStateChanged(NvComputer* computer);

    void handleBoxArtLoaded(NvComputer* computer, NvApp app, QUrl image);

    void handleNetworkQualityChanged();

    void checkLatencyUpdate();

signals:
    void computerLost();
    void networkLatencyChanged(int rttMs);
    void packetLossRateChanged(float lossRate);
    void networkStatusChanged();
    void audioQualityChanged();

private:
    void updateAppList(QVector<NvApp> newList);

    QVector<NvApp> getVisibleApps(const QVector<NvApp>& appList);

    bool isAppCurrentlyVisible(const NvApp& app);

    void applyAdaptiveSettings(Session* session) const;

    NvComputer* m_Computer;
    BoxArtManager m_BoxArtManager;
    ComputerManager* m_ComputerManager;
    QVector<NvApp> m_VisibleApps, m_AllApps;
    int m_CurrentGameId;
    bool m_ShowHiddenGames;

    // Latency measurement - uses shared LatencyMeasurer
    LatencyMeasurer* m_LatencyMeasurer;
    QTimer* m_LatencyCheckTimer;  // Polls for latency updates from m_Computer
    int m_LastReportedLatency;

    // Packet loss rate from NetworkQualityMonitor (0.0 - 1.0)
    float m_PacketLossRate;
};
