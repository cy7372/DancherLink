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

void LatencyMeasurer::start(const QString &address, quint16 port)
{
    if (m_Timer && m_Timer->isActive()) {
        if (m_Address == address && m_Port == port) {
            // Already measuring same target
            return;
        }
        stop();
    }

    m_Address = address;
    m_Port = port;
    m_MeasuredRttMedian = -1;
    m_MeasurementBatch = 0;
    m_LatencySamples.clear();

    if (!m_Timer) {
        m_Timer = new QTimer(this);
        m_Timer->setSingleShot(false);
        connect(m_Timer, &QTimer::timeout, this, &LatencyMeasurer::measureSample);
    }

    m_Timer->start(SAMPLE_INTERVAL_MS);
    emit measuringStateChanged(true);
    qDebug() << "[LatencyMeasurer] Started measurement to" << address << ":" << port;
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
    emit measuringStateChanged(false);
    qDebug() << "[LatencyMeasurer] Stopped measurement";
}

QString LatencyMeasurer::qualityString() const
{
    if (m_MeasuredRttMedian < 0) {
        return QObject::tr("Unknown");
    }
    if (m_MeasuredRttMedian < 10)  return QObject::tr("Excellent");
    if (m_MeasuredRttMedian < 20)  return QObject::tr("Good");
    if (m_MeasuredRttMedian < 30)  return QObject::tr("Fair");
    if (m_MeasuredRttMedian < 50)  return QObject::tr("Poor");
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

void LatencyMeasurer::measureSample()
{
    // If we have enough samples for this batch, process them and wait
    if (m_LatencySamples.size() >= SAMPLE_COUNT) {
        // Calculate median of samples
        QVector<int> sorted = m_LatencySamples;
        std::sort(sorted.begin(), sorted.end());
        m_MeasuredRttMedian = sorted[sorted.size() / 2];

        qDebug() << "[LatencyMeasurer] Batch" << m_MeasurementBatch
                 << "completed, median RTT:" << m_MeasuredRttMedian << "ms";

        emit latencyChanged(m_MeasuredRttMedian);

        // Clear samples for next batch and restart timer with longer interval
        m_LatencySamples.clear();
        m_MeasurementBatch++;

        if (m_Timer) {
            m_Timer->start(BATCH_INTERVAL_MS);
        }
        return;
    }

    // If a previous measurement is still running, skip this one
    if (m_Watcher) {
        return;
    }

    // Start async measurement
    m_Watcher = new QFutureWatcher<int>(this);
    connect(m_Watcher, &QFutureWatcher<int>::finished, this, &LatencyMeasurer::handleSampleFinished);

    QFuture<int> future = QtConcurrent::run(&LatencyMeasurer::measureOnce, m_Address, m_Port);
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
                 << "RTT:" << rttMs << "ms";
    }

    // If we've collected enough samples, the next measureSample() call will process them
    // Otherwise, the timer will trigger another sample
}
