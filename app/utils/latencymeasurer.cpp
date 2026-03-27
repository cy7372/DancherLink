#include "latencymeasurer.h"

#include <QDebug>
#include <QtMath>
#include <QTcpSocket>
#include <QNetworkProxy>
#include <QElapsedTimer>
#include <QTimer>
#include <QtConcurrent>
#include <QFutureWatcher>
#include <algorithm>

LatencyMeasurer::LatencyMeasurer(QObject *parent)
    : QObject(parent)
{
}

LatencyMeasurer::~LatencyMeasurer()
{
    stop();
}

void LatencyMeasurer::start(NvComputer *computer)
{
    if (!computer) {
        qWarning() << "[LatencyMeasurer] Cannot start with null computer";
        return;
    }

    if (m_Timer && m_Timer->isActive()) {
        if (m_Computer == computer) {
            // Already measuring same computer
            return;
        }
        stop();
    }

    m_Computer = computer;
    m_MeasurementBatch = 0;
    m_EmaLatency = -1.0;
    m_LastDisplayedLatency = -1;

    // Initialize computer's latency state
    {
        QWriteLocker lock(&m_Computer->lock);
        m_Computer->measuredLatencyMs = -2;  // Measuring
        m_Computer->latencyMeasurementBatch = 0;
        m_Computer->latencySamples.clear();
    }

    m_LatencySamples.clear();

    if (!m_Timer) {
        m_Timer = new QTimer(this);
        m_Timer->setSingleShot(false);
        connect(m_Timer, &QTimer::timeout, this, &LatencyMeasurer::measureSample);
    }

    m_Timer->start(SAMPLE_INTERVAL_MS);
    qDebug() << "[LatencyMeasurer] Started measurement for" << computer->name;
}

void LatencyMeasurer::stop()
{
    if (m_Timer) {
        m_Timer->stop();
    }

    if (m_Watcher) {
        m_Watcher->disconnect();
        m_Watcher->deleteLater();
        m_Watcher = nullptr;
    }

    m_LatencySamples.clear();
    m_EmaLatency = -1.0;
    m_LastDisplayedLatency = -1;

    // Mark measurement as stopped in computer
    if (m_Computer) {
        QWriteLocker lock(&m_Computer->lock);
        if (m_Computer->measuredLatencyMs == -2) {
            m_Computer->measuredLatencyMs = -1;  // Unknown
        }
        m_Computer = nullptr;
    }

    qDebug() << "[LatencyMeasurer] Stopped measurement";
}

QString LatencyMeasurer::qualityString(int latencyMs)
{
    if (latencyMs < 0) {
        return QObject::tr("Unknown");
    }
    if (latencyMs < 10)  return QObject::tr("Excellent");
    if (latencyMs < 20)  return QObject::tr("Good");
    if (latencyMs < 30)  return QObject::tr("Fair");
    if (latencyMs < 50)  return QObject::tr("Poor");
    return QObject::tr("Bad");
}

int LatencyMeasurer::measureOnce(const QString &address, quint16 port)
{
    QTcpSocket socket;
    QElapsedTimer timer;

    socket.setProxy(QNetworkProxy::NoProxy);
    timer.start();
    socket.connectToHost(address, port);

    if (!socket.waitForConnected(2000)) {
        return -1;
    }

    int rttMs = timer.elapsed();
    socket.disconnectFromHost();

    return rttMs;
}

int LatencyMeasurer::calculateMedian(const QVector<int> &sortedSamples)
{
    if (sortedSamples.isEmpty()) return -1;
    return sortedSamples[sortedSamples.size() / 2];
}

int LatencyMeasurer::smoothLatency(int newValue)
{
    if (newValue < 0) return newValue;

    if (m_EmaLatency < 0) {
        m_EmaLatency = newValue;
    } else {
        // Exponential moving average: EMA = α * new + (1-α) * old
        m_EmaLatency = EMA_ALPHA * newValue + (1.0 - EMA_ALPHA) * m_EmaLatency;
    }

    return static_cast<int>(m_EmaLatency + 0.5);  // Round to nearest int
}

void LatencyMeasurer::measureSample()
{
    if (!m_Computer) {
        stop();
        return;
    }

    // If we have enough samples for this batch, process them
    if (m_LatencySamples.size() >= SAMPLE_COUNT) {
        // Calculate median of samples
        QVector<int> sorted = m_LatencySamples;
        std::sort(sorted.begin(), sorted.end());
        int median = calculateMedian(sorted);

        qDebug() << "[LatencyMeasurer] Batch" << m_MeasurementBatch
                 << "completed for" << m_Computer->name
                 << ", median RTT:" << median << "ms";

        // Smooth the latency value
        int smoothedLatency = smoothLatency(median);

        // Store result in computer
        {
            QWriteLocker lock(&m_Computer->lock);
            m_Computer->measuredLatencyMs = smoothedLatency;
            m_Computer->latencyMeasurementBatch = m_MeasurementBatch;
            m_Computer->lastLatencyUpdate = QDateTime::currentDateTime();
        }

        emit latencyChanged(smoothedLatency);

        // Clear samples for next batch
        m_LatencySamples.clear();
        m_MeasurementBatch++;

        // Continue with next batch immediately (BATCH_INTERVAL_MS = 0)
        if (m_Timer && BATCH_INTERVAL_MS > 0) {
            m_Timer->start(BATCH_INTERVAL_MS);
        }
        return;
    }

    // If a previous measurement is still running, skip this one
    if (m_Watcher) {
        return;
    }

    // Get address from computer
    QString address;
    quint16 port;
    {
        QReadLocker lock(&m_Computer->lock);
        address = m_Computer->activeAddress.address();
        port = m_Computer->activeAddress.port();
    }

    if (address.isEmpty()) {
        qDebug() << "[LatencyMeasurer] No active address for" << m_Computer->name;
        return;
    }

    // Start async measurement
    m_Watcher = new QFutureWatcher<int>(this);
    connect(m_Watcher, &QFutureWatcher<int>::finished, this, &LatencyMeasurer::handleSampleFinished);

    QFuture<int> future = QtConcurrent::run(&LatencyMeasurer::measureOnce, address, port);
    m_Watcher->setFuture(future);
}

void LatencyMeasurer::handleSampleFinished()
{
    if (!m_Watcher) return;

    int rttMs = m_Watcher->result();
    m_Watcher->deleteLater();
    m_Watcher = nullptr;

    if (rttMs > 0) {
        m_LatencySamples.append(rttMs);
        qDebug() << "[LatencyMeasurer] Sample" << m_LatencySamples.size()
                 << "RTT:" << rttMs << "ms for" << (m_Computer ? m_Computer->name : "unknown");

        // Update computer with running median during first batch for fast initial display
        if (m_Computer && m_MeasurementBatch == 0 && m_LatencySamples.size() < SAMPLE_COUNT) {
            QVector<int> sorted = m_LatencySamples;
            std::sort(sorted.begin(), sorted.end());
            int runningMedian = calculateMedian(sorted);

            // Smooth the running median
            int smoothedRunningMedian = smoothLatency(runningMedian);

            {
                QWriteLocker lock(&m_Computer->lock);
                m_Computer->measuredLatencyMs = smoothedRunningMedian;
            }
            emit latencyChanged(smoothedRunningMedian);
        }
    } else {
        qDebug() << "[LatencyMeasurer] Sample failed for" << (m_Computer ? m_Computer->name : "unknown");
    }

    // Continue collecting samples
}
