#pragma once

#include "backend/nvcomputer.h"

#include <QObject>
#include <QFutureWatcher>
#include <QTimer>
#include <QVector>
#include <QtConcurrent>
#include <QTcpSocket>
#include <QElapsedTimer>

/**
 * @brief Shared latency measurement utility for network quality monitoring
 *
 * This class provides continuous latency measurement functionality
 * that stores results in NvComputer for sharing between models.
 */
class LatencyMeasurer : public QObject
{
    Q_OBJECT

public:
    explicit LatencyMeasurer(QObject *parent = nullptr);
    ~LatencyMeasurer();

    /**
     * @brief Start continuous latency measurement for the specified computer
     * @param computer The computer to measure (results stored in this object)
     */
    Q_INVOKABLE void start(NvComputer *computer);

    /**
     * @brief Stop latency measurement
     */
    Q_INVOKABLE void stop();

    bool isMeasuring() const { return m_Timer && m_Timer->isActive(); }

    /**
     * @brief Get quality string for a latency value
     */
    static QString qualityString(int latencyMs);

    /**
     * @brief Static helper to measure latency once
     * @param address Target address
     * @param port Target port
     * @return RTT in ms, or -1 on failure
     */
    static int measureOnce(const QString &address, quint16 port);

signals:
    void latencyChanged(int rttMs);

private slots:
    void measureSample();
    void handleSampleFinished();

private:
    NvComputer *m_Computer = nullptr;

    // Measurement state (temporary, results go to m_Computer)
    int m_MeasurementBatch = 0;
    QVector<int> m_LatencySamples;
    QFutureWatcher<int> *m_Watcher = nullptr;
    QTimer *m_Timer = nullptr;

    static constexpr int SAMPLE_COUNT = 5;
    static constexpr int SAMPLE_INTERVAL_MS = 100;
    static constexpr int BATCH_INTERVAL_MS = 3000;
};
