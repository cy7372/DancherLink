#pragma once

#include "backend/nvcomputer.h"

#include <QObject>
#include <QFutureWatcher>
#include <QTimer>
#include <QVector>
#include <QtConcurrent>
#include <QTcpSocket>
#include <QElapsedTimer>
#include <QDateTime>

/**
 * @brief Shared latency measurement utility for network quality monitoring
 *
 * This class provides continuous latency measurement functionality
 * that stores results in NvComputer for sharing between models.
 *
 * Optimized algorithm:
 * - Parallel sample collection (up to N concurrent measurements)
 * - Sliding window median for smooth updates
 * - Exponential moving average for trend detection
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
    /**
     * @brief Calculate median from sorted samples
     */
    static int calculateMedian(const QVector<int> &sortedSamples);

    /**
     * @brief Smooth the latency value using exponential moving average
     */
    int smoothLatency(int newValue);

private:
    NvComputer *m_Computer = nullptr;

    // Measurement state (temporary, results go to m_Converter)
    int m_MeasurementBatch = 0;
    QVector<int> m_LatencySamples;
    QFutureWatcher<int> *m_Watcher = nullptr;
    QTimer *m_Timer = nullptr;

    // Smoothing state
    double m_EmaLatency = -1.0;  // Exponential moving average
    int m_LastDisplayedLatency = -1;

    static constexpr int SAMPLE_COUNT = 5;       // Samples per batch
    static constexpr int SAMPLE_INTERVAL_MS = 200;  // Interval between samples
    static constexpr int BATCH_INTERVAL_MS = 0;     // No extra delay between batches
    static constexpr int MAX_CONCURRENT = 1;        // Concurrent measurements
    static constexpr double EMA_ALPHA = 0.3;        // Smoothing factor
};
