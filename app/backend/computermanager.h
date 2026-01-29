#pragma once

#include "nvcomputer.h"
#include "nvhttp.h"
#include "nvpairingmanager.h"
#include "settings/streamingpreferences.h"
#include "settings/compatfetcher.h"

#include <QNetworkAccessManager>
#include <QDebug>
#include <QCoreApplication>
#include <QtEndian>
#include <qmdnsengine/server.h>
#include <qmdnsengine/cache.h>
#include <qmdnsengine/browser.h>
#include <qmdnsengine/service.h>
#include <qmdnsengine/resolver.h>

#include <QThread>
#include <QReadWriteLock>
#include <QSettings>
#include <QRunnable>
#include <QTimer>
#include <QMutex>
#include <QWaitCondition>
#include <memory>
#include <map>
#include <vector>

class ComputerManager;

class DelayedFlushThread : public QThread
{
    Q_OBJECT

public:
    DelayedFlushThread(ComputerManager* cm)
        : m_ComputerManager(cm)
    {
        setObjectName("CM Delayed Flush Thread");
    }

    void run();

private:
    ComputerManager* m_ComputerManager;
};









class MdnsPendingComputer : public QObject
{
    Q_OBJECT

public:
    explicit MdnsPendingComputer(const QSharedPointer<QMdnsEngine::Server> server,
                                 const QMdnsEngine::Service& service)
        : m_Hostname(service.hostname()),
          m_Port(service.port()),
          m_ServerWeak(server),
          m_Resolver(nullptr)
    {
        // Start resolving
        resolve();
    }

    virtual ~MdnsPendingComputer()
    {
    }

    QString hostname()
    {
        return m_Hostname;
    }

    uint16_t port()
    {
        return m_Port;
    }

private slots:
    void handleResolvedTimeout()
    {
        if (m_Addresses.isEmpty()) {
            if (m_Retries-- > 0) {
                // Try again
                qInfo() << "Resolving" << hostname() << "timed out. Retrying...";
                resolve();
            }
            else {
                qWarning() << "Giving up on resolving" << hostname() << "after repeated failures";
                cleanup();
            }
        }
        else {
            Q_ASSERT(!m_Addresses.isEmpty());
            emit resolvedHost(this, m_Addresses);
        }
    }

    void handleResolvedAddress(const QHostAddress& address)
    {
        qInfo() << "Resolved" << hostname() << "to" << address;
        m_Addresses.push_back(address);
    }

signals:
    void resolvedHost(MdnsPendingComputer*,QVector<QHostAddress>&);

private:
    void cleanup()
    {
        // Delete our resolver, so we're guaranteed that nothing is referencing m_Server.
        m_Resolver.reset();

        // Now delete our strong reference that we held on behalf of m_Resolver.
        // The server may be destroyed after we make this call.
        m_Server.reset();
    }

    void resolve()
    {
        // Clean up any existing resolver object and server references
        cleanup();

        // Re-acquire a strong reference if the server still exists.
        m_Server = m_ServerWeak.toStrongRef();
        if (!m_Server) {
            return;
        }

        m_Resolver.reset(new QMdnsEngine::Resolver(m_Server.data(), m_Hostname));
        connect(m_Resolver.get(), &QMdnsEngine::Resolver::resolved,
                this, &MdnsPendingComputer::handleResolvedAddress);
        QTimer::singleShot(2000, this, &MdnsPendingComputer::handleResolvedTimeout);
    }

    QByteArray m_Hostname;
    uint16_t m_Port;
    QWeakPointer<QMdnsEngine::Server> m_ServerWeak;
    QSharedPointer<QMdnsEngine::Server> m_Server;
    std::unique_ptr<QMdnsEngine::Resolver> m_Resolver;
    QVector<QHostAddress> m_Addresses;
    int m_Retries = 10;
};

class PcMonitorThread : public QThread
{
    Q_OBJECT

#define TRIES_BEFORE_OFFLINING 2
#define POLLS_PER_APPLIST_FETCH 10

public:
    PcMonitorThread(NvComputer* computer)
        : m_Computer(computer)
    {
        setObjectName("Polling thread for " + computer->name);
    }

    void stop()
    {
        requestInterruption();
        QMutexLocker locker(&m_WakeLock);
        m_WakeCondition.wakeAll();
    }

private:
    bool tryPollComputer(QNetworkAccessManager* nam, NvAddress address, bool& changed)
    {
        NvHTTP http(address, 0, m_Computer->serverCert, nam);

        QString serverInfo;
        try {
            serverInfo = http.getServerInfo(NvHTTP::NvLogLevel::NVLL_NONE, true);
        } catch (...) {
            return false;
        }

        NvComputer newState(http, serverInfo);

        // Ensure the machine that responded is the one we intended to contact
        if (m_Computer->uuid != newState.uuid) {
            qInfo() << "Found unexpected PC" << newState.name << "looking for" << m_Computer->name;
            return false;
        }

        changed = m_Computer->update(newState);
        return true;
    }

    bool updateAppList(QNetworkAccessManager* nam, bool& changed)
    {
        NvHTTP http(m_Computer, nam);

        QVector<NvApp> appList;

        try {
            appList = http.getAppList();
            if (appList.isEmpty()) {
                return false;
            }
        } catch (...) {
            return false;
        }

        QWriteLocker lock(&m_Computer->lock);
        changed = m_Computer->updateAppList(appList);
        return true;
    }

    void run() override
    {
        // Reduce the power and performance impact of our
        // computer status polling while it's running.
        setPriority(QThread::LowPriority);
#if QT_VERSION >= QT_VERSION_CHECK(6, 9, 0)
        setServiceLevel(QThread::QualityOfService::Eco);
#endif

        // Share the QNetworkAccessManager to conserve resources when polling.
        // Each instance creates a worker thread, so sharing them ensures that
        // we are not spamming a new thread for every single polling attempt.
        //
        // Since QThread inherit the priority of the current thread, this also
        // ensures that the NAM's worker thread will inherit our lower priority.
        QNetworkAccessManager nam;

        // Always fetch the applist the first time
        int pollsSinceLastAppListFetch = POLLS_PER_APPLIST_FETCH;
        while (!isInterruptionRequested()) {
            bool stateChanged = false;
            bool online = false;
            bool wasOnline = m_Computer->state == NvComputer::CS_ONLINE;
            for (int i = 0; i < (wasOnline ? TRIES_BEFORE_OFFLINING : 1) && !online; i++) {
                for (auto& address : m_Computer->uniqueAddresses()) {
                    if (isInterruptionRequested()) {
                        return;
                    }

                    if (tryPollComputer(&nam, address, stateChanged)) {
                        if (!wasOnline) {
                            qInfo() << m_Computer->name << "is now online at" << m_Computer->activeAddress.toString();
                        }
                        online = true;
                        break;
                    }
                }
            }

            // Check if we failed after all retry attempts
            // Note: we don't need to acquire the read lock here,
            // because we're on the writing thread.
            if (!online && m_Computer->state != NvComputer::CS_OFFLINE) {
                qInfo() << m_Computer->name << "is now offline";
                
                // Acquire lock before modifying state to avoid race with DelayedFlushThread
                QWriteLocker lock(&m_Computer->lock);
                m_Computer->state = NvComputer::CS_OFFLINE;
                stateChanged = true;
            }

            // Grab the applist if it's empty or it's been long enough that we need to refresh
            pollsSinceLastAppListFetch++;
            if (m_Computer->state == NvComputer::CS_ONLINE &&
                    m_Computer->pairState == NvComputer::PS_PAIRED &&
                    (m_Computer->appList.isEmpty() || pollsSinceLastAppListFetch >= POLLS_PER_APPLIST_FETCH)) {
                // Notify prior to the app list poll since it may take a while, and we don't
                // want to delay onlining of a machine, especially if we already have a cached list.
                if (stateChanged) {
                    emit computerStateChanged(m_Computer);
                    stateChanged = false;
                }

                if (updateAppList(&nam, stateChanged)) {
                    pollsSinceLastAppListFetch = 0;
                }
            }

            if (stateChanged) {
                // Tell anyone listening that we've changed state
                emit computerStateChanged(m_Computer);
            }

            // Wait a bit to poll again
            QMutexLocker locker(&m_WakeLock);
            if (!isInterruptionRequested()) {
                m_WakeCondition.wait(&m_WakeLock, 3000);
            }
        }
    }

signals:
   void computerStateChanged(NvComputer* computer);

private:
    NvComputer* m_Computer;
    QMutex m_WakeLock;
    QWaitCondition m_WakeCondition;
};

class ComputerPollingEntry
{
public:
    ComputerPollingEntry()
        : m_ActiveThread(nullptr)
    {

    }

    virtual ~ComputerPollingEntry()
    {
        interrupt();

        // interrupt() should have taken care of this
        Q_ASSERT(m_ActiveThread == nullptr);

        for (PcMonitorThread* thread : m_InactiveList) {
            thread->wait();
            delete thread;
        }
    }

    bool isActive()
    {
        cleanInactiveList();

        return m_ActiveThread != nullptr;
    }

    void setActiveThread(PcMonitorThread* thread)
    {
        cleanInactiveList();

        Q_ASSERT(!isActive());
        m_ActiveThread = thread;
    }

    void interrupt()
    {
        cleanInactiveList();

        if (m_ActiveThread != nullptr) {
            // Interrupt the active thread
            m_ActiveThread->stop();

            // Place it on the inactive list awaiting death
            m_InactiveList.append(m_ActiveThread);

            m_ActiveThread = nullptr;
        }
    }

private:
    void cleanInactiveList()
    {
        QMutableListIterator<PcMonitorThread*> i(m_InactiveList);

        // Reap any threads that have finished
        while (i.hasNext()) {
            i.next();

            PcMonitorThread* thread = i.value();
            if (thread->isFinished()) {
                delete thread;
                i.remove();
            }
        }
    }

    PcMonitorThread* m_ActiveThread;
    QList<PcMonitorThread*> m_InactiveList;
};

class ComputerManager : public QObject
{
    Q_OBJECT

    friend class DeferredHostDeletionTask;
    friend class PendingPairingTask;
    friend class PendingQuitTask;
    friend class PendingAddTask;


public:
    explicit ComputerManager(StreamingPreferences* prefs);

    virtual ~ComputerManager();

    Q_INVOKABLE void startPolling();

    Q_INVOKABLE void stopPollingAsync();

    Q_INVOKABLE void addNewHostManually(QString address);

    void addNewHost(NvAddress address, bool mdns, NvAddress mdnsIpv6Address = NvAddress());

    QString generatePinString();

    void pairHost(NvComputer* computer, QString pin);

    void quitRunningApp(NvComputer* computer);

    QVector<NvComputer*> getComputers();

    // computer is deleted inside this call
    void deleteHost(NvComputer* computer);

    void renameHost(NvComputer* computer, QString name);

    void clientSideAttributeUpdated(NvComputer* computer);

signals:
    void computerStateChanged(NvComputer* computer);

    void pairingCompleted(NvComputer* computer, QString error);

    void computerAddCompleted(QVariant success, QVariant detectedPortBlocking);

    void quitAppCompleted(QVariant error);

private slots:
    void handleAboutToQuit();

    void handleComputerStateChanged(NvComputer* computer);

    void handleMdnsServiceResolved(MdnsPendingComputer* computer, QVector<QHostAddress>& addresses);

private:
    void saveHosts();

    void saveHost(NvComputer* computer);

    QHostAddress getBestGlobalAddressV6(QVector<QHostAddress>& addresses);

    void startPollingComputer(NvComputer* computer);

    StreamingPreferences* m_Prefs;
    int m_PollingRef;
    QReadWriteLock m_Lock;
    QMap<QString, NvComputer*> m_KnownHosts;
    std::map<QString, std::unique_ptr<ComputerPollingEntry>> m_PollEntries;
    QHash<QString, NvComputer> m_LastSerializedHosts; // Protected by m_DelayedFlushMutex
    QSharedPointer<QMdnsEngine::Server> m_MdnsServer;
    QMdnsEngine::Browser* m_MdnsBrowser;
    std::vector<std::unique_ptr<MdnsPendingComputer>> m_PendingResolution;
    CompatFetcher m_CompatFetcher;
    DelayedFlushThread* m_DelayedFlushThread;
    QMutex m_DelayedFlushMutex; // Lock ordering: Must never be acquired while holding NvComputer lock
    QWaitCondition m_DelayedFlushCondition;
    bool m_NeedsDelayedFlush;

    friend class DeferredHostDeletionTask;
    friend class PendingPairingTask;
    friend class PendingQuitTask;
    friend class PendingAddTask;
    friend class DelayedFlushThread;
};

class PendingPairingTask : public QObject, public QRunnable
{
    Q_OBJECT

public:
    PendingPairingTask(ComputerManager* computerManager, NvComputer* computer, QString pin)
        : m_ComputerManager(computerManager),
          m_Computer(computer),
          m_Pin(pin)
    {
        connect(this, &PendingPairingTask::pairingCompleted,
                computerManager, &ComputerManager::pairingCompleted);
    }

signals:
    void pairingCompleted(NvComputer* computer, QString error);

private:
    void run() override
    {
        NvPairingManager pairingManager(m_Computer);

        try {
           NvPairingManager::PairState result = pairingManager.pair(m_Computer->appVersion, m_Pin, m_Computer->serverCert);
           switch (result)
           {
           case NvPairingManager::PairState::PIN_WRONG:
               emit pairingCompleted(m_Computer, tr("The PIN from the PC didn't match. Please try again."));
               break;
           case NvPairingManager::PairState::FAILED:
               if (m_Computer->currentGameId != 0) {
                   emit pairingCompleted(m_Computer, tr("You cannot pair while a previous session is still running on the host PC. Quit any running games or reboot the host PC, then try pairing again."));
               }
               else {
                   emit pairingCompleted(m_Computer, tr("Pairing failed. Please try again."));
               }
               break;
           case NvPairingManager::PairState::ALREADY_IN_PROGRESS:
               emit pairingCompleted(m_Computer, tr("Another pairing attempt is already in progress."));
               break;
           case NvPairingManager::PairState::PAIRED:
               // Persist the newly pinned server certificate for this host
               m_ComputerManager->saveHost(m_Computer);

               emit pairingCompleted(m_Computer, nullptr);
               break;
           }
        } catch (const GfeHttpResponseException& e) {
            emit pairingCompleted(m_Computer, tr("GeForce Experience returned error: %1").arg(e.toQString()));
        } catch (const QtNetworkReplyException& e) {
            emit pairingCompleted(m_Computer, e.toQString());
        }
    }

    ComputerManager* m_ComputerManager;
    NvComputer* m_Computer;
    QString m_Pin;
};

class PendingQuitTask : public QObject, public QRunnable
{
    Q_OBJECT

public:
    PendingQuitTask(ComputerManager* computerManager, NvComputer* computer)
        : m_Computer(computer)
    {
        connect(this, &PendingQuitTask::quitAppFailed,
                computerManager, &ComputerManager::quitAppCompleted);
    }

signals:
    void quitAppFailed(QString error);

private:
    void run() override
    {
        NvHTTP http(m_Computer);

        try {
            if (m_Computer->currentGameId != 0) {
                http.quitApp();
            }
        } catch (const GfeHttpResponseException& e) {
            {
                QWriteLocker lock(&m_Computer->lock);
                m_Computer->pendingQuit = false;
            }
            if (e.getStatusCode() == 599) {
                // 599 is a special code we make a custom message for
                emit quitAppFailed(tr("The running game wasn't started by this PC. "
                                      "You must quit the game on the host PC manually or use the device that originally started the game."));
            }
            else {
                emit quitAppFailed(e.toQString());
            }
        } catch (const QtNetworkReplyException& e) {
            {
                QWriteLocker lock(&m_Computer->lock);
                m_Computer->pendingQuit = false;
            }
            emit quitAppFailed(e.toQString());
        }
    }

    NvComputer* m_Computer;
};

class PendingAddTask : public QObject, public QRunnable
{
    Q_OBJECT

public:
    PendingAddTask(ComputerManager* computerManager, NvAddress address, NvAddress mdnsIpv6Address, bool mdns)
        : m_ComputerManager(computerManager),
          m_Address(address),
          m_MdnsIpv6Address(mdnsIpv6Address),
          m_Mdns(mdns),
          m_AboutToQuit(false)
    {
        connect(this, &PendingAddTask::computerAddCompleted,
                computerManager, &ComputerManager::computerAddCompleted);
        connect(this, &PendingAddTask::computerStateChanged,
                computerManager, &ComputerManager::handleComputerStateChanged);
        connect(QCoreApplication::instance(), &QCoreApplication::aboutToQuit,
                this, &PendingAddTask::handleAboutToQuit);
    }

signals:
    void computerAddCompleted(QVariant success, QVariant detectedPortBlocking);

    void computerStateChanged(NvComputer* computer);

private:
    void handleAboutToQuit()
    {
        m_AboutToQuit = true;
    }

    QString fetchServerInfo(NvHTTP& http)
    {
        QString serverInfo;

        // Do nothing if we're quitting
        if (m_AboutToQuit) {
            return QString();
        }

        try {
            // There's a race condition between GameStream servers reporting presence over
            // mDNS and the HTTPS server being ready to respond to our queries. To work
            // around this issue, we will issue the request again after a few seconds if
            // we see a ServiceUnavailableError error.
            try {
                serverInfo = http.getServerInfo(NvHTTP::NVLL_VERBOSE);
            } catch (const QtNetworkReplyException& e) {
                if (e.getError() == QNetworkReply::ServiceUnavailableError) {
                    qWarning() << "Retrying request in 5 seconds after ServiceUnavailableError";
                    QThread::sleep(5);
                    serverInfo = http.getServerInfo(NvHTTP::NVLL_VERBOSE);
                    qInfo() << "Retry successful";
                }
                else {
                    // Rethrow other errors
                    throw e;
                }
            }
            return serverInfo;
        } catch (...) {
            if (!m_Mdns) {
                unsigned int portTestResult;

                if (m_ComputerManager->m_Prefs->detectNetworkBlocking) {
                    // We failed to connect to the specified PC. Let's test to make sure this network
                    // isn't blocking Moonlight, so we can tell the user about it.
                    portTestResult = LiTestClientConnectivity("qt.conntest.moonlight-stream.org", 443,
                                                              ML_PORT_FLAG_TCP_47984 | ML_PORT_FLAG_TCP_47989);
                }
                else {
                    portTestResult = 0;
                }

                emit computerAddCompleted(false, portTestResult != 0 && portTestResult != ML_TEST_RESULT_INCONCLUSIVE);
            }
            return QString();
        }
    }

    void run() override
    {
        NvHTTP http(m_Address, 0, QSslCertificate());

        qInfo() << "Processing new PC at" << m_Address.toString() << "from" << (m_Mdns ? "mDNS" : "user") << "with IPv6 address" << m_MdnsIpv6Address.toString();

        // Perform initial serverinfo fetch over HTTP since we don't know which cert to use
        QString serverInfo = fetchServerInfo(http);
        if (serverInfo.isEmpty() && !m_MdnsIpv6Address.isNull()) {
            // Retry using the global IPv6 address if the IPv4 or link-local IPv6 address fails
            http.setAddress(m_MdnsIpv6Address);
            serverInfo = fetchServerInfo(http);
        }
        if (serverInfo.isEmpty()) {
            return;
        }

        // Create initial newComputer using HTTP serverinfo with no pinned cert
        NvComputer* newComputer = new NvComputer(http, serverInfo);

        // Check if we have a record of this host UUID to pull the pinned cert
        NvComputer* existingComputer;
        {
            QReadLocker lock(&m_ComputerManager->m_Lock);
            existingComputer = m_ComputerManager->m_KnownHosts.value(newComputer->uuid);
            if (existingComputer != nullptr) {
                http.setServerCert(existingComputer->serverCert);
            }
        }

        // Fetch serverinfo again over HTTPS with the pinned cert
        if (existingComputer != nullptr) {
            Q_ASSERT(http.httpsPort() != 0);
            serverInfo = fetchServerInfo(http);
            if (serverInfo.isEmpty()) {
                return;
            }

            // Update the polled computer with the HTTPS information
            NvComputer httpsComputer(http, serverInfo);
            newComputer->update(httpsComputer);
        }

        // Update addresses depending on the context
        if (m_Mdns) {
            // Only update local address if we actually reached the PC via this address.
            // If we reached it via the IPv6 address after the local address failed,
            // don't store the non-working local address.
            if (http.address() == m_Address) {
                newComputer->localAddress = m_Address;
            }

#if 0 // DancherLink: Disable STUN for privacy and independence
            // Get the WAN IP address using STUN if we're on mDNS over IPv4
            if (QHostAddress(newComputer->localAddress.address()).protocol() == QAbstractSocket::IPv4Protocol) {
                quint32 addr;
                int err = LiFindExternalAddressIP4("stun.moonlight-stream.org", 3478, &addr);
                if (err == 0) {
                    newComputer->setRemoteAddress(QHostAddress(qFromBigEndian(addr)));
                }
                else {
                    qWarning() << "STUN failed to get WAN address:" << err;
                }
            }
#endif

            if (!m_MdnsIpv6Address.isNull()) {
                Q_ASSERT(QHostAddress(m_MdnsIpv6Address.address()).protocol() == QAbstractSocket::IPv6Protocol);
                newComputer->ipv6Address = m_MdnsIpv6Address;
            }
        }
        else {
            newComputer->manualAddress = m_Address;
        }

        QHostAddress hostAddress(m_Address.address());
        bool addressIsSiteLocalV4 =
                hostAddress.isInSubnet(QHostAddress("10.0.0.0"), 8) ||
                hostAddress.isInSubnet(QHostAddress("172.16.0.0"), 12) ||
                hostAddress.isInSubnet(QHostAddress("192.168.0.0"), 16);

        {
            // Check if this PC already exists using opportunistic read lock
            m_ComputerManager->m_Lock.lockForRead();
            NvComputer* existingComputer = m_ComputerManager->m_KnownHosts.value(newComputer->uuid);

            // If it doesn't already exist, convert to a write lock in preparation for updating.
            //
            // NB: ComputerManager's lock protects the host map itself, not the elements inside.
            // Those are protected by their individual locks. Since we only mutate the map itself
            // when the PC doesn't exist, we need the lock in write-mode for that case only.
            if (existingComputer == nullptr) {
                m_ComputerManager->m_Lock.unlock();
                m_ComputerManager->m_Lock.lockForWrite();

                // Since we had to unlock to lock for write, someone could have raced and added
                // this PC before us. We have to check again whether it already exists.
                existingComputer = m_ComputerManager->m_KnownHosts.value(newComputer->uuid);
            }

            if (existingComputer != nullptr) {
                // Fold it into the existing PC
                bool changed = existingComputer->update(*newComputer);
                delete newComputer;

                // Drop the lock before notifying
                m_ComputerManager->m_Lock.unlock();

                // For non-mDNS clients, let them know it succeeded
                if (!m_Mdns) {
                    emit computerAddCompleted(true, false);
                }

                // Tell our client if something changed
                if (changed) {
                    qInfo() << existingComputer->name << "is now at" << existingComputer->activeAddress.toString();
                    emit computerStateChanged(existingComputer);
                }
            }
            else {
                // Store this in our active sets
                m_ComputerManager->m_KnownHosts[newComputer->uuid] = newComputer;

                // Start polling if enabled (write lock required)
                m_ComputerManager->startPollingComputer(newComputer);

                // Drop the lock before notifying
                m_ComputerManager->m_Lock.unlock();

                // If this wasn't added via mDNS but it is a RFC 1918 IPv4 address and not a VPN,
                // go ahead and do the STUN request now to populate an external address.
                if (!m_Mdns && addressIsSiteLocalV4 && newComputer->getActiveAddressReachability() != NvComputer::RI_VPN) {
                    quint32 addr;
                    int err = LiFindExternalAddressIP4("stun.moonlight-stream.org", 3478, &addr);
                    if (err == 0) {
                        newComputer->setRemoteAddress(QHostAddress(qFromBigEndian(addr)));
                    }
                    else {
                        qWarning() << "STUN failed to get WAN address:" << err;
                    }
                }

                // For non-mDNS clients, let them know it succeeded
                if (!m_Mdns) {
                    emit computerAddCompleted(true, false);
                }

                // Tell our client about this new PC
                emit computerStateChanged(newComputer);
            }
        }
    }

    ComputerManager* m_ComputerManager;
    NvAddress m_Address;
    NvAddress m_MdnsIpv6Address;
    bool m_Mdns;
    bool m_AboutToQuit;
};
