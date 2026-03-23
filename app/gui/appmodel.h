#pragma once

#include "backend/boxartmanager.h"
#include "backend/computermanager.h"
#include "streaming/session.h"
#include "streaming/networkqualitymonitor.h"

#include <QAbstractListModel>
#include <QFutureWatcher>
#include <QElapsedTimer>

class AppModel : public QAbstractListModel
{
    Q_OBJECT

    Q_PROPERTY(int networkLatencyMs READ networkLatencyMs NOTIFY networkLatencyChanged)
    Q_PROPERTY(QString networkQualityString READ networkQualityString NOTIFY networkLatencyChanged)
    Q_PROPERTY(float packetLossRate READ packetLossRate NOTIFY packetLossRateChanged)
    Q_PROPERTY(QString networkQualityDetailed READ networkQualityDetailed NOTIFY networkStatusChanged)
    Q_PROPERTY(int recommendedBitrate READ recommendedBitrate NOTIFY networkStatusChanged)

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

    QVariant data(const QModelIndex &index, int role) const override;

    int rowCount(const QModelIndex &parent) const override;

    virtual QHash<int, QByteArray> roleNames() const override;

private slots:
    void handleComputerStateChanged(NvComputer* computer);

    void handleBoxArtLoaded(NvComputer* computer, NvApp app, QUrl image);

    void handleNetworkQualityChanged();

signals:
    void computerLost();
    void networkLatencyChanged(int rttMs);
    void packetLossRateChanged(float lossRate);
    void networkStatusChanged();

private:
    void updateAppList(QVector<NvApp> newList);

    QVector<NvApp> getVisibleApps(const QVector<NvApp>& appList);

    bool isAppCurrentlyVisible(const NvApp& app);

    void measureLatencyAsync();
    void startLatencyMeasurement();
    void stopLatencyMeasurement();
    void applyAdaptiveSettings(Session* session) const;

    NvComputer* m_Computer;
    BoxArtManager m_BoxArtManager;
    ComputerManager* m_ComputerManager;
    QVector<NvApp> m_VisibleApps, m_AllApps;
    int m_CurrentGameId;
    bool m_ShowHiddenGames;

    // Network quality measurement
    // -1 = measuring in progress, -2 = measurement failed, >= 0 = RTT in ms
    int m_MeasuredRttMs = -1;
    QFutureWatcher<int>* m_LatencyWatcher = nullptr;

    // Continuous latency measurement with periodic updates
    QTimer* m_LatencyTimer = nullptr;         // Timer for periodic measurement
    QVector<int> m_LatencySamples;             // Current batch of samples
    int m_MeasuredRttMedian = -1;              // Median of last completed batch
    int m_MeasurementBatch = 0;                // Batch counter (0 = first batch)
    static constexpr int LATENCY_SAMPLE_COUNT = 5;      // Samples per batch
    static constexpr int LATENCY_SAMPLE_INTERVAL_MS = 100; // Time between samples
    static constexpr int LATENCY_BATCH_INTERVAL_MS = 3000; // Time between batches

    // Packet loss rate from NetworkQualityMonitor (0.0 - 1.0)
    float m_PacketLossRate;
};
