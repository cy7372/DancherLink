#pragma once

#include "backend/boxartmanager.h"
#include "backend/computermanager.h"
#include "streaming/session.h"

#include <QAbstractListModel>
#include <QFutureWatcher>
#include <QElapsedTimer>

class AppModel : public QAbstractListModel
{
    Q_OBJECT

    Q_PROPERTY(int networkLatencyMs READ networkLatencyMs NOTIFY networkLatencyChanged)
    Q_PROPERTY(QString networkQualityString READ networkQualityString NOTIFY networkLatencyChanged)

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

    QVariant data(const QModelIndex &index, int role) const override;

    int rowCount(const QModelIndex &parent) const override;

    virtual QHash<int, QByteArray> roleNames() const override;

private slots:
    void handleComputerStateChanged(NvComputer* computer);

    void handleBoxArtLoaded(NvComputer* computer, NvApp app, QUrl image);

signals:
    void computerLost();
    void networkLatencyChanged(int rttMs);

private:
    void updateAppList(QVector<NvApp> newList);

    QVector<NvApp> getVisibleApps(const QVector<NvApp>& appList);

    bool isAppCurrentlyVisible(const NvApp& app);

    void measureLatencyAsync();
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

    // Debouncing for latency measurement to avoid redundant network requests
    QElapsedTimer m_LatencyDebounceTimer;
    static constexpr int LATENCY_DEBOUNCE_INTERVAL_MS = 5000; // Minimum 5 seconds between measurements
};
