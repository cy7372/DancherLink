#include "appmodel.h"

#include <QCoreApplication>
#include <QStandardPaths>
#include <QDir>
#include <QRegularExpression>
#include <QtConcurrent>
#include <QFuture>
#include <QThreadPool>
#include <QTcpSocket>
#include <QElapsedTimer>
#include <QTimer>
#include <QtMath>
#include <QReadLocker>

#include "streaming/audioqualitymonitor.h"

#ifdef Q_OS_WIN32
#include <shobjidl.h>
#include <shlguid.h>

// RAII wrapper for COM pointers to ensure proper cleanup
template<typename T>
class ComPtr {
public:
    ComPtr() : ptr_(nullptr) {}
    explicit ComPtr(T* p) : ptr_(p) {}
    ~ComPtr() { release(); }

    // Disable copy
    ComPtr(const ComPtr&) = delete;
    ComPtr& operator=(const ComPtr&) = delete;

    // Enable move
    ComPtr(ComPtr&& other) noexcept : ptr_(other.ptr_) { other.ptr_ = nullptr; }
    ComPtr& operator=(ComPtr&& other) noexcept {
        if (this != &other) {
            release();
            ptr_ = other.ptr_;
            other.ptr_ = nullptr;
        }
        return *this;
    }

    T** put() { return &ptr_; }
    T* get() const { return ptr_; }
    T* operator->() const { return ptr_; }
    explicit operator bool() const { return ptr_ != nullptr; }

    void release() {
        if (ptr_) {
            ptr_->Release();
            ptr_ = nullptr;
        }
    }

private:
    T* ptr_;
};
#endif

AppModel::AppModel(QObject *parent)
    : QAbstractListModel(parent)
    , m_Computer(nullptr)
    , m_ComputerManager(nullptr)
    , m_CurrentGameId(0)
    , m_ShowHiddenGames(false)
    , m_LatencyMeasurer(new LatencyMeasurer(this))
    , m_LatencyCheckTimer(nullptr)
    , m_LastReportedLatency(-1)
    , m_PacketLossRate(0.0f)
{
    connect(&m_BoxArtManager, &BoxArtManager::boxArtLoadComplete,
            this, &AppModel::handleBoxArtLoaded);
}

AppModel::~AppModel()
{
    stopLatencyMeasurement();
}

void AppModel::initialize(ComputerManager* computerManager, int computerIndex, bool showHiddenGames)
{
    m_ComputerManager = computerManager;
    connect(m_ComputerManager, &ComputerManager::computerStateChanged,
            this, &AppModel::handleComputerStateChanged);

    Q_ASSERT(computerIndex < m_ComputerManager->getComputers().count());
    m_Computer = m_ComputerManager->getComputers().at(computerIndex);
    m_CurrentGameId = m_Computer->currentGameId;
    m_ShowHiddenGames = showHiddenGames;

    updateAppList(m_Computer->appList);

    // Start continuous latency measurement
    startLatencyMeasurement();

    // Connect to NetworkQualityMonitor for real-time packet loss updates
    connect(NetworkQualityMonitor::instance(), &NetworkQualityMonitor::statsUpdated,
            this, [this]() {
        float newLossRate = NetworkQualityMonitor::instance()->packetLossRate();
        if (m_PacketLossRate != newLossRate) {
            m_PacketLossRate = newLossRate;
            emit packetLossRateChanged(m_PacketLossRate);
            emit networkStatusChanged();
        }
    });

    // Connect to AudioQualityMonitor for audio quality updates
    connect(AudioQualityMonitor::instance(), &AudioQualityMonitor::statsUpdated,
            this, [this]() {
        emit audioQualityChanged();
    });
    connect(AudioQualityMonitor::instance(), &AudioQualityMonitor::qualityChanged,
            this, [this]() {
        emit audioQualityChanged();
    });
}

void AppModel::startLatencyMeasurement()
{
    if (!m_Computer) {
        return;
    }

    // Use shared LatencyMeasurer to measure this computer
    // This ensures latency is shared between ComputerModel and AppModel
    if (m_LatencyMeasurer) {
        m_LatencyMeasurer->start(m_Computer);
    }

    // Start polling timer to check for updates from NvComputer
    if (!m_LatencyCheckTimer) {
        m_LatencyCheckTimer = new QTimer(this);
        m_LatencyCheckTimer->setInterval(100); // Check every 100ms
        connect(m_LatencyCheckTimer, &QTimer::timeout, this, &AppModel::checkLatencyUpdate);
    }
    m_LatencyCheckTimer->start();
    qDebug() << "[AppModel] Started latency measurement for" << m_Computer->name;
}

void AppModel::stopLatencyMeasurement()
{
    if (m_LatencyCheckTimer) {
        m_LatencyCheckTimer->stop();
    }

    if (m_LatencyMeasurer) {
        m_LatencyMeasurer->stop();
    }

    qDebug() << "[AppModel] Stopped latency measurement";
}

void AppModel::checkLatencyUpdate()
{
    if (!m_Computer) {
        return;
    }

    QReadLocker lock(&m_Computer->lock);
    int currentLatency = m_Computer->measuredLatencyMs;
    lock.unlock();

    // Only emit signal if latency changed
    if (currentLatency != m_LastReportedLatency) {
        m_LastReportedLatency = currentLatency;
        emit networkLatencyChanged(currentLatency);
    }
}

int AppModel::networkLatencyMs() const
{
    if (!m_Computer) {
        return -1;
    }
    QReadLocker lock(&m_Computer->lock);
    return m_Computer->measuredLatencyMs;
}

QString AppModel::networkQualityString() const
{
    return LatencyMeasurer::qualityString(networkLatencyMs());
}

float AppModel::packetLossRate() const
{
    return m_PacketLossRate;
}

QString AppModel::networkQualityDetailed() const
{
    // Combine RTT-based quality with packet loss info
    QString rttQuality = networkQualityString();
    float lossRate = m_PacketLossRate * 100.0f;  // Convert to percentage

    int latencyMs = networkLatencyMs();
    if (latencyMs < 0) {
        return tr("N/A");
    }

    // Format: "Excellent (丢包 1.5%)" or "Good (丢包 0.2%)"
    return QString("%1 (%2)").arg(rttQuality).arg(tr("丢包 %1%").arg(lossRate, 0, 'f', 1));
}

int AppModel::recommendedBitrate() const
{
    return NetworkQualityMonitor::instance()->recommendedBitrate();
}

// Audio quality methods
QString AppModel::audioQualityString() const
{
    return AudioQualityMonitor::instance()->qualityString();
}

float AppModel::audioPacketLossRate() const
{
    return AudioQualityMonitor::instance()->packetLossRate();
}

QString AppModel::audioQualityDetailed() const
{
    QString quality = audioQualityString();
    float lossRate = audioPacketLossRate() * 100.0f;  // Convert to percentage
    float fecRate = AudioQualityMonitor::instance()->fecRecoveryRate() * 100.0f;

    int latencyMs = networkLatencyMs();
    if (latencyMs < 0) {
        return tr("N/A");
    }

    // Format: "Excellent (丢包 1.5%, FEC 恢复 2.3%)"
    return QString("%1 (%2)").arg(quality).arg(tr("丢包 %1%, FEC 恢复 %2%").arg(lossRate, 0, 'f', 1).arg(fecRate, 0, 'f', 1));
}

// Helper function to reduce FPS by steps, respecting standard FPS tiers
static int reduceFpsBySteps(int originalFps, int steps)
{
    // Standard FPS tiers: 30 ← 60 ← 90 ← 120 ← 144
    static const int fpsTiers[] = {30, 60, 90, 120, 144};
    const int numTiers = sizeof(fpsTiers) / sizeof(fpsTiers[0]);

    // Find the current tier index
    int index = 0;
    for (int i = 0; i < numTiers; i++) {
        if (originalFps >= fpsTiers[i]) {
            index = i;
        }
    }

    // Reduce by steps, but never below 30fps
    index -= steps;
    if (index < 0) index = 0;

    return fpsTiers[index];
}

void AppModel::applyAdaptiveSettings(Session* session) const
{
    StreamingPreferences* prefs = StreamingPreferences::get();

    // Get current latency from computer
    int latencyMs = -1;
    if (m_Computer) {
        QReadLocker lock(&m_Computer->lock);
        latencyMs = m_Computer->measuredLatencyMs;
    }

    if (!prefs->networkAdaptiveBitrate || latencyMs < 0) {
        return;
    }

    int fps = prefs->fps;
    int bitrateKbps = prefs->bitrateKbps;

    // Reduce FPS starting from Poor quality (RTT >= 30ms)
    // Poor (30-50ms): reduce 1 tier, Bad (>=50ms): reduce 2 tiers
    int fpsReductionSteps = 0;
    if (latencyMs >= 50) {
        fpsReductionSteps = 2;  // Bad: reduce 2 tiers
    } else if (latencyMs >= 30) {
        fpsReductionSteps = 1;  // Poor: reduce 1 tier
    }

    if (fpsReductionSteps > 0 && fps > 30) {
        fps = reduceFpsBySteps(fps, fpsReductionSteps);
    }

    // Scale bitrate based on measured RTT
    // Thresholds: Excellent <10ms, Good 10-20ms, Fair 20-30ms, Poor 30-50ms, Bad >=50ms
    float bitrateMultiplier;
    if (latencyMs < 10)       bitrateMultiplier = 1.00f;  // Excellent
    else if (latencyMs < 20)  bitrateMultiplier = 0.90f;  // Good
    else if (latencyMs < 30)  bitrateMultiplier = 0.70f;  // Fair
    else if (latencyMs < 50)  bitrateMultiplier = 0.50f;  // Poor
    else                       bitrateMultiplier = 0.30f;  // Bad

    // Calculate the "full quality" bitrate for the selected resolution and fps,
    // then apply the network quality multiplier as a ceiling
    int fullBitrate = StreamingPreferences::getDefaultBitrate(
        prefs->width, prefs->height, fps, prefs->enableYUV444);
    int recommendedBitrate = qMax(2000, (int)(fullBitrate * bitrateMultiplier));

    // Only reduce — never increase beyond what user configured
    if (recommendedBitrate < bitrateKbps) {
        bitrateKbps = recommendedBitrate;
    }

    // Only apply overrides if they differ from user's settings
    if (fps != prefs->fps || bitrateKbps != prefs->bitrateKbps) {
        session->setNetworkOverrides(fps, bitrateKbps);
        qDebug() << "[NetAdapt] RTT" << latencyMs << "ms → applying"
                 << fps << "fps /" << bitrateKbps << "kbps";
    }
}

int AppModel::getRunningAppId()
{
    return m_CurrentGameId;
}

QString AppModel::getRunningAppName()
{
    if (m_CurrentGameId != 0) {
        for (int i = 0; i < m_AllApps.count(); i++) {
            if (m_AllApps[i].id == m_CurrentGameId) {
                return m_AllApps[i].name;
            }
        }
    }

    return nullptr;
}

Session* AppModel::createSessionForApp(int appIndex)
{
    Q_ASSERT(appIndex < m_VisibleApps.count());
    NvApp app = m_VisibleApps.at(appIndex);

    Session* session = new Session(m_Computer, app);

    // Apply network-adaptive fps/bitrate overrides based on pre-stream measurement.
    // This modifies only this session's settings without touching saved preferences.
    applyAdaptiveSettings(session);

    return session;
}

int AppModel::getDirectLaunchAppIndex()
{
    for (int i = 0; i < m_VisibleApps.count(); i++) {
        if (m_VisibleApps[i].directLaunch) {
            return i;
        }
    }

    return -1;
}

int AppModel::rowCount(const QModelIndex &parent) const
{
    // For list models only the root node (an invalid parent) should return the list's size. For all
    // other (valid) parents, rowCount() should return 0 so that it does not become a tree model.
    if (parent.isValid())
        return 0;

    return m_VisibleApps.count();
}

QVariant AppModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid())
        return QVariant();

    Q_ASSERT(index.row() < m_VisibleApps.count());
    NvApp app = m_VisibleApps.at(index.row());

    switch (role)
    {
    case NameRole:
        return app.name;
    case RunningRole:
        return m_Computer->currentGameId == app.id;
    case BoxArtRole:
        // loadBoxArt is not const, but we need to call it from a const method.
        // The method is logically const (it doesn't change the app data, just updates a cache),
        // so mutable would be appropriate for the cache if we could modify BoxArtManager.
        // For now, const_cast is the pragmatic solution.
        return const_cast<BoxArtManager&>(m_BoxArtManager).loadBoxArt(m_Computer, app);
    case HiddenRole:
        return app.hidden;
    case AppIdRole:
        return app.id;
    case DirectLaunchRole:
        return app.directLaunch;
    case AppCollectorGameRole:
        return app.isAppCollectorGame;
    default:
        return QVariant();
    }
}

QHash<int, QByteArray> AppModel::roleNames() const
{
    QHash<int, QByteArray> names;

    names[NameRole] = "name";
    names[RunningRole] = "running";
    names[BoxArtRole] = "boxart";
    names[HiddenRole] = "hidden";
    names[AppIdRole] = "appid";
    names[DirectLaunchRole] = "directLaunch";
    names[AppCollectorGameRole] = "appCollectorGame";

    return names;
}

void AppModel::quitRunningApp()
{
    m_ComputerManager->quitRunningApp(m_Computer);
}

bool AppModel::isAppCurrentlyVisible(const NvApp& app)
{
    for (const NvApp& visibleApp : m_VisibleApps) {
        if (app.id == visibleApp.id) {
            return true;
        }
    }

    return false;
}

QVector<NvApp> AppModel::getVisibleApps(const QVector<NvApp>& appList)
{
    QVector<NvApp> visibleApps;

    for (const NvApp& app : appList) {
        // Don't immediately hide games that were previously visible. This
        // allows users to easily uncheck the "Hide App" checkbox if they
        // check it by mistake.
        if (m_ShowHiddenGames || !app.hidden || isAppCurrentlyVisible(app)) {
            visibleApps.append(app);
        }
    }

    return visibleApps;
}

void AppModel::updateAppList(QVector<NvApp> newList)
{
    m_AllApps = newList;

    QVector<NvApp> newVisibleList = getVisibleApps(newList);

    // Process removals and updates first
    for (int i = 0; i < m_VisibleApps.count(); i++) {
        const NvApp& existingApp = m_VisibleApps.at(i);

        bool found = false;
        for (const NvApp& newApp : newVisibleList) {
            if (existingApp.id == newApp.id) {
                // If the data changed, update it in our list
                if (existingApp != newApp) {
                    m_VisibleApps.replace(i, newApp);
                    emit dataChanged(createIndex(i, 0), createIndex(i, 0));
                }

                found = true;
                break;
            }
        }

        if (!found) {
            beginRemoveRows(QModelIndex(), i, i);
            m_VisibleApps.removeAt(i);
            endRemoveRows();
            i--;
        }
    }

    // Process additions now
    for (const NvApp& newApp : newVisibleList) {
        int insertionIndex = static_cast<int>(m_VisibleApps.size());
        bool found = false;

        for (int i = 0; i < m_VisibleApps.count(); i++) {
            const NvApp& existingApp = m_VisibleApps.at(i);

            if (existingApp.id == newApp.id) {
                found = true;
                break;
            }
            else if (existingApp.name.toLower() > newApp.name.toLower()) {
                insertionIndex = i;
                break;
            }
        }

        if (!found) {
            beginInsertRows(QModelIndex(), insertionIndex, insertionIndex);
            m_VisibleApps.insert(insertionIndex, newApp);
            endInsertRows();
        }
    }

    Q_ASSERT(newVisibleList == m_VisibleApps);
}

void AppModel::setAppHidden(int appIndex, bool hidden)
{
    Q_ASSERT(appIndex < m_VisibleApps.count());
    int appId = m_VisibleApps.at(appIndex).id;

    {
        QWriteLocker lock(&m_Computer->lock);

        for (NvApp& app : m_Computer->appList) {
            if (app.id == appId) {
                app.hidden = hidden;
                break;
            }
        }
    }

    m_ComputerManager->clientSideAttributeUpdated(m_Computer);
}

void AppModel::setAppDirectLaunch(int appIndex, bool directLaunch)
{
    Q_ASSERT(appIndex < m_VisibleApps.count());
    int appId = m_VisibleApps.at(appIndex).id;

    {
        QWriteLocker lock(&m_Computer->lock);

        for (NvApp& app : m_Computer->appList) {
            if (directLaunch) {
                // We must clear direct launch from all other apps
                // to set it on the new app.
                app.directLaunch = app.id == appId;
            }
            else if (app.id == appId) {
                // If we're clearing direct launch, we're done once we
                // find our matching app ID.
                app.directLaunch = false;
                break;
            }
        }
    }

    m_ComputerManager->clientSideAttributeUpdated(m_Computer);
}

void AppModel::handleComputerStateChanged(NvComputer* computer)
{
    // Ignore updates for computers that aren't ours
    if (computer != m_Computer) {
        return;
    }

    // If the computer has gone offline or we've been unpaired,
    // signal the UI so we can go back to the PC view.
    if (m_Computer->state == NvComputer::CS_OFFLINE ||
            m_Computer->pairState == NvComputer::PS_NOT_PAIRED) {
        emit computerLost();
        return;
    }

    // First, process additions/removals from the app list. This
    // is required because the new game may now be running, so
    // we can't check that first.
    if (computer->appList != m_AllApps) {
        updateAppList(computer->appList);
    }

    // Finally, process changes to the active app
    if (computer->currentGameId != m_CurrentGameId) {
        // First, invalidate the running state of newly running game
        for (int i = 0; i < m_VisibleApps.count(); i++) {
            if (m_VisibleApps[i].id == computer->currentGameId) {
                emit dataChanged(createIndex(i, 0),
                                 createIndex(i, 0),
                                 QVector<int>() << RunningRole);
                break;
            }
        }

        // Next, invalidate the running state of the old game (if it exists)
        if (m_CurrentGameId != 0) {
            for (int i = 0; i < m_VisibleApps.count(); i++) {
                if (m_VisibleApps[i].id == m_CurrentGameId) {
                    emit dataChanged(createIndex(i, 0),
                                     createIndex(i, 0),
                                     QVector<int>() << RunningRole);
                    break;
                }
            }
        }

        // Now update our internal state
        m_CurrentGameId = m_Computer->currentGameId;
    }
}

void AppModel::handleBoxArtLoaded(NvComputer* computer, NvApp app, QUrl /* image */)
{
    Q_ASSERT(computer == m_Computer);

    int index = m_VisibleApps.indexOf(app);

    // Make sure we're not delivering a callback to an app that's already been removed
    if (index >= 0) {
        // Let our view know the box art data has changed for this app
        emit dataChanged(createIndex(index, 0),
                         createIndex(index, 0),
                         QVector<int>() << BoxArtRole);
    }
    else {
        qWarning() << "App not found for box art callback:" << app.name;
    }
}

void AppModel::handleNetworkQualityChanged()
{
    // Network quality changes are handled via the statsUpdated signal connection
    // This slot is provided for future extensibility
}

void AppModel::createDesktopShortcut(int appIndex)
{
    Q_ASSERT(appIndex < m_VisibleApps.count());
    NvApp app = m_VisibleApps.at(appIndex);

#ifdef Q_OS_WIN32
    // Capture data by value to avoid thread safety issues if the model/computer is destroyed
    QString computerUuid = m_Computer->uuid;
    QString computerName = m_Computer->name;
    QString appName = app.name;
    QString appPath = QCoreApplication::applicationFilePath();

    QThreadPool::globalInstance()->start([computerUuid, computerName, appName, appPath]() {
        QString desktopPath = QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
        QString linkName = appName;
        // Sanitize filename - use manual character replacement for better performance
        // than QRegularExpression for simple character substitution
        for (int i = 0; i < linkName.size(); ++i) {
            QChar c = linkName.at(i);
            if (c == u'\\' || c == u'/' || c == u':' || c == u'*' ||
                c == u'?' || c == u'"' || c == u'<' || c == u'>' || c == u'|') {
                linkName[i] = u'_';
            }
        }
        QString linkPath = QDir(desktopPath).filePath(linkName + ".lnk");

        QString nativeAppPath = QDir::toNativeSeparators(appPath);

        // Quote the app name if it contains spaces
        QString arguments = QString("stream \"%1\" \"%2\" --resolution auto").arg(computerUuid).arg(appName);

        // Initialize COM library for this worker thread
        CoInitialize(nullptr);

        // Use RAII wrappers for COM pointers to ensure proper cleanup
        ComPtr<IShellLink> psl;
        HRESULT hres = CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                                        IID_IShellLink, reinterpret_cast<LPVOID*>(psl.put()));
        if (SUCCEEDED(hres)) {
            psl->SetPath(reinterpret_cast<LPCWSTR>(nativeAppPath.utf16()));
            psl->SetArguments(reinterpret_cast<LPCWSTR>(arguments.utf16()));
            psl->SetDescription(reinterpret_cast<LPCWSTR>(
                QString("Stream %1 from %2").arg(appName).arg(computerName).utf16()));

            // Set the icon to the Moonlight executable
            psl->SetIconLocation(reinterpret_cast<LPCWSTR>(nativeAppPath.utf16()), 0);

            ComPtr<IPersistFile> ppf;
            hres = psl->QueryInterface(IID_IPersistFile, reinterpret_cast<LPVOID*>(ppf.put()));
            if (SUCCEEDED(hres)) {
                ppf->Save(reinterpret_cast<LPCWSTR>(linkPath.utf16()), TRUE);
            }
            // ComPtr automatically releases ppf and psl when going out of scope
        }

        CoUninitialize();
    });
#else
    // TODO: Implement for other platforms
    Q_UNUSED(app);
#endif
}
