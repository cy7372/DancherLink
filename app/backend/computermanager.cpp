#include "computermanager.h"
#include "boxartmanager.h"
#include "nvhttp.h"
#include "nvpairingmanager.h"

#include <Limelight.h>
#include <QtEndian>

#include <QThread>
#include <QThreadPool>
#include <QCoreApplication>
#include <QRandomGenerator>

#define SER_HOSTS "hosts"
#define SER_HOSTS_BACKUP "hostsbackup"

ComputerManager::ComputerManager(StreamingPreferences* prefs)
    : m_Prefs(prefs),
      m_PollingRef(0),
      m_MdnsBrowser(nullptr),
      m_CompatFetcher(nullptr),
      m_NeedsDelayedFlush(false)
{
    QSettings settings;

    // If there's a hosts backup copy, we must have failed to commit
    // a previous update before exiting. Restore the backup now.
    int hosts = settings.beginReadArray(SER_HOSTS_BACKUP);
    if (hosts == 0) {
        // If there's no host backup, read from the primary location.
        settings.endArray();
        hosts = settings.beginReadArray(SER_HOSTS);
    }

    // Inflate our hosts from QSettings
    for (int i = 0; i < hosts; i++) {
        settings.setArrayIndex(i);
        NvComputer* computer = new NvComputer(settings);
        m_KnownHosts[computer->uuid] = computer;
        m_LastSerializedHosts[computer->uuid] = *computer;
    }
    settings.endArray();

    // Fetch latest compatibility data asynchronously
    m_CompatFetcher.start();

    // Start the delayed flush thread to handle saveHosts() calls
    m_DelayedFlushThread = new DelayedFlushThread(this);
    m_DelayedFlushThread->start();

    // To quit in a timely manner, we must block additional requests
    // after we receive the aboutToQuit() signal. This is necessary
    // because NvHTTP uses aboutToQuit() to abort requests in progress
    // while quitting, however this is a one time signal - additional
    // requests would not be aborted and block termination.
    connect(QCoreApplication::instance(), &QCoreApplication::aboutToQuit, this, &ComputerManager::handleAboutToQuit);
}

ComputerManager::~ComputerManager()
{
    // Stop the delayed flush thread before acquiring the lock in write mode
    // to avoid deadlocking with a flush that needs the lock in read mode.
    {
        // Wake the delayed flush thread
        m_DelayedFlushThread->requestInterruption();
        m_DelayedFlushCondition.wakeOne();

        // Wait for it to terminate (and finish any pending flush)
        m_DelayedFlushThread->wait();
        delete m_DelayedFlushThread;

        // Delayed flushes should have completed by now
        Q_ASSERT(!m_NeedsDelayedFlush);
    }

    QWriteLocker lock(&m_Lock);

    // Delete machines that haven't been resolved yet
    m_PendingResolution.clear();

    // Delete the browser to stop discovery
    delete m_MdnsBrowser;
    m_MdnsBrowser = nullptr;

    // Delete all polling entries (and associated threads)
    for (auto const& [uuid, entry] : m_PollEntries) {
        entry->interrupt();
    }
    
    // std::unique_ptr will handle deletion automatically
    m_PollEntries.clear();

    // Destroy all NvComputer objects now that polling is halted
    qDeleteAll(m_KnownHosts);
    m_KnownHosts.clear();
}

void DelayedFlushThread::run() {
    for (;;) {
        // Wait for a delayed flush request or an interruption
        {
            QMutexLocker locker(&m_ComputerManager->m_DelayedFlushMutex);

            while (!QThread::currentThread()->isInterruptionRequested() && !m_ComputerManager->m_NeedsDelayedFlush) {
                m_ComputerManager->m_DelayedFlushCondition.wait(&m_ComputerManager->m_DelayedFlushMutex);
            }

            // Bail without flushing if we woke up for an interruption alone.
            // If we have both an interruption and a flush request, do the flush.
            if (!m_ComputerManager->m_NeedsDelayedFlush) {
                Q_ASSERT(QThread::currentThread()->isInterruptionRequested());
                break;
            }

            // Reset the delayed flush flag to ensure any racing saveHosts() call will set it again
            m_ComputerManager->m_NeedsDelayedFlush = false;

            // Update the last serialized hosts map under the delayed flush mutex
            m_ComputerManager->m_LastSerializedHosts.clear();
            for (const NvComputer* computer : m_ComputerManager->m_KnownHosts) {
                // Copy the current state of the NvComputer to allow us to check later if we need
                // to serialize it again when attribute updates occur.
                QReadLocker computerLock(&computer->lock);
                m_ComputerManager->m_LastSerializedHosts[computer->uuid] = *computer;
            }
        }

        // Perform the flush
        {
            QSettings settings;

            // First, write to the backup location
            settings.beginWriteArray(SER_HOSTS_BACKUP);
            {
                QReadLocker lock(&m_ComputerManager->m_Lock);
                int i = 0;
                for (const NvComputer* computer : m_ComputerManager->m_KnownHosts) {
                    settings.setArrayIndex(i++);
                    computer->serialize(settings, false);
                }
            }
            settings.endArray();

            // Next, write to the primary location
            settings.remove(SER_HOSTS);
            settings.beginWriteArray(SER_HOSTS);
            {
                QReadLocker lock(&m_ComputerManager->m_Lock);
                int i = 0;
                for (const NvComputer* computer : m_ComputerManager->m_KnownHosts) {
                    settings.setArrayIndex(i++);
                    computer->serialize(settings, true);
                }
            }
            settings.endArray();

            // Finally, delete the backup copy
            settings.remove(SER_HOSTS_BACKUP);
        }
    }
}

void ComputerManager::saveHosts()
{
    Q_ASSERT(m_DelayedFlushThread != nullptr && m_DelayedFlushThread->isRunning());

    // Punt to a worker thread because QSettings on macOS can take ages (> 500 ms)
    // to persist our host list to disk (especially when a host has a bunch of apps).
    QMutexLocker locker(&m_DelayedFlushMutex);
    m_NeedsDelayedFlush = true;
    m_DelayedFlushCondition.wakeOne();
}

QHostAddress ComputerManager::getBestGlobalAddressV6(QVector<QHostAddress> &addresses)
{
    for (const QHostAddress& address : addresses) {
        if (address.protocol() == QAbstractSocket::IPv6Protocol) {
            if (address.isInSubnet(QHostAddress("fe80::"), 10)) {
                // Link-local
                continue;
            }

            if (address.isInSubnet(QHostAddress("fec0::"), 10)) {
                qInfo() << "Ignoring site-local address:" << address;
                continue;
            }

            if (address.isInSubnet(QHostAddress("fc00::"), 7)) {
                qInfo() << "Ignoring ULA:" << address;
                continue;
            }

            if (address.isInSubnet(QHostAddress("2002::"), 16)) {
                qInfo() << "Ignoring 6to4 address:" << address;
                continue;
            }

            if (address.isInSubnet(QHostAddress("2001::"), 32)) {
                qInfo() << "Ignoring Teredo address:" << address;
                continue;
            }

            return address;
        }
    }

    return QHostAddress();
}

void ComputerManager::startPolling()
{
    QWriteLocker lock(&m_Lock);

    if (++m_PollingRef > 1) {
        return;
    }

    if (m_Prefs->enableMdns) {
        // Start an MDNS query for GameStream hosts
        m_MdnsServer.reset(new QMdnsEngine::Server());
        m_MdnsBrowser = new QMdnsEngine::Browser(m_MdnsServer.data(), "_nvstream._tcp.local.");
        connect(m_MdnsBrowser, &QMdnsEngine::Browser::serviceAdded,
                this, [this](const QMdnsEngine::Service& service) {
            qInfo() << "Discovered mDNS host:" << service.hostname();

            MdnsPendingComputer* pendingComputer = new MdnsPendingComputer(m_MdnsServer, service);
            connect(pendingComputer, &MdnsPendingComputer::resolvedHost,
                    this, &ComputerManager::handleMdnsServiceResolved);
            m_PendingResolution.push_back(std::unique_ptr<MdnsPendingComputer>(pendingComputer));
        });
    }
    else {
        qWarning() << "mDNS is disabled by user preference";
    }

    // Start polling threads for each known host
    QMapIterator<QString, NvComputer*> i(m_KnownHosts);
    while (i.hasNext()) {
        i.next();
        startPollingComputer(i.value());
    }
}

// Must hold m_Lock for write
void ComputerManager::startPollingComputer(NvComputer* computer)
{
    if (m_PollingRef == 0) {
        return;
    }

    ComputerPollingEntry* pollingEntry;

    auto it = m_PollEntries.find(computer->uuid);
    if (it == m_PollEntries.end()) {
        auto newEntry = std::make_unique<ComputerPollingEntry>();
        pollingEntry = newEntry.get();
        m_PollEntries.emplace(computer->uuid, std::move(newEntry));
    }
    else {
        pollingEntry = it->second.get();
    }

    if (!pollingEntry->isActive()) {
        PcMonitorThread* thread = new PcMonitorThread(computer);
        connect(thread, &PcMonitorThread::computerStateChanged,
                this, &ComputerManager::handleComputerStateChanged);
        pollingEntry->setActiveThread(thread);
        thread->start();
    }
}

void ComputerManager::handleMdnsServiceResolved(MdnsPendingComputer* computer,
                                                QVector<QHostAddress>& addresses)
{
    QHostAddress v6Global = getBestGlobalAddressV6(addresses);
    bool added = false;

    // Add the host using the IPv4 address
    for (const QHostAddress& address : addresses) {
        if (address.protocol() == QAbstractSocket::IPv4Protocol) {
            // NB: We don't just call addNewHost() here with v6Global because the IPv6
            // address may not be reachable (if the user hasn't installed the IPv6 helper yet
            // or if this host lacks outbound IPv6 capability). We want to add IPv6 even if
            // it's not currently reachable.
            addNewHost(NvAddress(address, computer->port()), true, NvAddress(v6Global, computer->port()));
            added = true;
            break;
        }
    }

    if (!added) {
        // If we get here, there wasn't an IPv4 address so we'll do it v6-only
        for (const QHostAddress& address : addresses) {
            if (address.protocol() == QAbstractSocket::IPv6Protocol) {
                // Use a link-local or site-local address for the "local address"
                if (address.isInSubnet(QHostAddress("fe80::"), 10) ||
                        address.isInSubnet(QHostAddress("fec0::"), 10) ||
                        address.isInSubnet(QHostAddress("fc00::"), 7)) {
                    addNewHost(NvAddress(address, computer->port()), true, NvAddress(v6Global, computer->port()));
                    break;
                }
            }
        }
    }

    auto it = std::find_if(m_PendingResolution.begin(), m_PendingResolution.end(),
                           [computer](const std::unique_ptr<MdnsPendingComputer>& ptr) {
                               return ptr.get() == computer;
                           });
    if (it != m_PendingResolution.end()) {
        MdnsPendingComputer* ptr = it->release();
        m_PendingResolution.erase(it);
        ptr->deleteLater();
    }
}

void ComputerManager::saveHost(NvComputer *computer)
{
    // If no serializable properties changed, don't bother saving hosts
    QMutexLocker lock(&m_DelayedFlushMutex);
    QReadLocker computerLock(&computer->lock);
    if (!m_LastSerializedHosts.value(computer->uuid).isEqualSerialized(*computer)) {
        // Queue a request for a delayed flush to QSettings outside of the lock
        computerLock.unlock();
        lock.unlock();
        saveHosts();
    }
}

void ComputerManager::handleComputerStateChanged(NvComputer* computer)
{
    emit computerStateChanged(computer);

    if (computer->pendingQuit && computer->currentGameId == 0) {
        computer->pendingQuit = false;
        emit quitAppCompleted(QVariant());
    }

    // Save updates to this host
    saveHost(computer);
}

QVector<NvComputer*> ComputerManager::getComputers()
{
    QReadLocker lock(&m_Lock);

    // Return a sorted host list
    auto hosts = QVector<NvComputer*>::fromList(m_KnownHosts.values());
    std::stable_sort(hosts.begin(), hosts.end(), [](const NvComputer* host1, const NvComputer* host2) {
        return host1->name.toLower() < host2->name.toLower();
    });
    return hosts;
}

class DeferredHostDeletionTask : public QRunnable
{
public:
    DeferredHostDeletionTask(ComputerManager* cm, NvComputer* computer)
        : m_Computer(computer),
          m_ComputerManager(cm) {}

    void run()
    {
        std::unique_ptr<ComputerPollingEntry> pollingEntryPtr;

        // Only do the minimum amount of work while holding the writer lock.
        // We must release it before calling saveHosts().
        {
            QWriteLocker lock(&m_ComputerManager->m_Lock);

            auto it = m_ComputerManager->m_PollEntries.find(m_Computer->uuid);
            if (it != m_ComputerManager->m_PollEntries.end()) {
                pollingEntryPtr = std::move(it->second);
                m_ComputerManager->m_PollEntries.erase(it);
            }

            m_ComputerManager->m_KnownHosts.remove(m_Computer->uuid);
        }

        // Persist the new host list with this computer deleted
        m_ComputerManager->saveHosts();

        // Delete the polling entry first. This will stop all polling threads too.
        // We explicitly reset the unique_ptr here to ensure the polling entry is destroyed
        // (and threads stopped) before we proceed to delete the box art and computer object.
        if (pollingEntryPtr) {
            pollingEntryPtr.reset();
        }

        // Delete cached box art
        BoxArtManager::deleteBoxArt(m_Computer);

        // Finally, delete the computer itself. This must be done
        // last because the polling thread might be using it.
        delete m_Computer;
    }

private:
    NvComputer* m_Computer;
    ComputerManager* m_ComputerManager;
};

void ComputerManager::deleteHost(NvComputer* computer)
{
    // Punt to a worker thread to avoid stalling the
    // UI while waiting for the polling thread to die
    QThreadPool::globalInstance()->start(new DeferredHostDeletionTask(this, computer));
}

void ComputerManager::renameHost(NvComputer* computer, QString name)
{
    {
        QWriteLocker lock(&computer->lock);

        computer->name = name;
        computer->hasCustomName = true;
    }

    // Notify the UI of the state change
    handleComputerStateChanged(computer);
}

void ComputerManager::clientSideAttributeUpdated(NvComputer* computer)
{
    // Notify the UI of the state change
    handleComputerStateChanged(computer);
}

void ComputerManager::handleAboutToQuit()
{
    QReadLocker lock(&m_Lock);

    // Interrupt polling threads immediately, so they
    // avoid making additional requests while quitting
    for (auto const& [uuid, entry] : m_PollEntries) {
        entry->interrupt();
    }
}



void ComputerManager::pairHost(NvComputer* computer, QString pin)
{
    // Punt to a worker thread to avoid stalling the
    // UI while waiting for pairing to complete
    PendingPairingTask* pairing = new PendingPairingTask(this, computer, pin);
    QThreadPool::globalInstance()->start(pairing);
}



void ComputerManager::quitRunningApp(NvComputer* computer)
{
    QWriteLocker lock(&computer->lock);
    computer->pendingQuit = true;

    PendingQuitTask* quit = new PendingQuitTask(this, computer);
    QThreadPool::globalInstance()->start(quit);
}

void ComputerManager::stopPollingAsync()
{
    QWriteLocker lock(&m_Lock);

    Q_ASSERT(m_PollingRef > 0);
    if (--m_PollingRef > 0) {
        return;
    }

    // Delete machines that haven't been resolved yet
    for (auto& entry : m_PendingResolution) {
        if (entry) {
            entry.release()->deleteLater();
        }
    }
    m_PendingResolution.clear();

    // Delete the browser and server to stop discovery and refresh polling
    delete m_MdnsBrowser;
    m_MdnsBrowser = nullptr;
    m_MdnsServer.reset();

    // Interrupt all threads, but don't wait for them to terminate
    for (auto const& [uuid, entry] : m_PollEntries) {
        entry->interrupt();
    }
}

void ComputerManager::addNewHostManually(QString address)
{
    QUrl url = QUrl::fromUserInput("dancherlink://" + address);
    if (url.isValid() && !url.host().isEmpty() && url.scheme() == "dancherlink") {
        // If there wasn't a port specified, use the default
        addNewHost(NvAddress(url.host(), url.port(DEFAULT_HTTP_PORT)), false);
    }
    else if (QHostAddress(address).protocol() == QAbstractSocket::IPv6Protocol) {
        // The user specified an IPv6 literal without URL escaping, so use the default port
        addNewHost(NvAddress(address, DEFAULT_HTTP_PORT), false);
    }
    else {
        emit computerAddCompleted(false, false);
    }
}



void ComputerManager::addNewHost(NvAddress address, bool mdns, NvAddress mdnsIpv6Address)
{
    // Punt to a worker thread to avoid stalling the
    // UI while waiting for serverinfo query to complete
    PendingAddTask* addTask = new PendingAddTask(this, address, mdnsIpv6Address, mdns);
    QThreadPool::globalInstance()->start(addTask);
}

QString ComputerManager::generatePinString()
{
    return QString::asprintf("%04u", QRandomGenerator::system()->bounded(10000));
}


