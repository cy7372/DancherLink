#pragma once

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
 * that can be used by both ComputerModel and AppModel.
 */
class LatencyMeasurer : public QObject
{
    Q_OBJECT

    Q_PROPERTY(int latencyMs READ latencyMs NOTIFY latencyChanged)
    Q_PROPERTY(QString qualityString READ qualityString NOTIFY latencyChanged)
    Q_PROPERTY(bool isMeasuring READ isMeasuring NOTIFY measuringStateChanged)

public:
    explicit LatencyMeasurer(QObject *parent = nullptr);
    ~LatencyMeasurer();

    /**
     * @brief Start continuous latency measurement to the specified host
     * @param address Target host address
     * @param port Target port (usually HTTPS port)
     */
    Q_INVOKABLE void start(const QString &address, quint16 port);

    /**
     * @brief Stop latency measurement
     */
    Q_INVOKABLE void stop();

    int latencyMs() const { return m_MeasuredRttMedian; }
    QString qualityString() const;
    bool isMeasuring() const { return m_Timer && m_Timer->isActive(); }

    /**
     * @brief Static helper to measure latency once
     * @param address Target address
     * @param port Target port
     * @return RTT in ms, or -1 on failure
     */
    static int measureOnce(const QString &address, quint16 port);

signals:
    void latencyChanged(int rttMs);
    void measuringStateChanged(bool isMeasuring);

private slots:
    void measureSample();
    void handleSampleFinished();

private:
    QString m_Address;
    quint16 m_Port = 0;

    // Measurement state
    int m_MeasuredRttMedian = -1;              // Median of last completed batch
    int m_MeasurementBatch = 0;
    QVector<int> m_LatencySamples;
    QFutureWatcher<int> *m_Watcher = nullptr;
    QTimer *m_Timer = nullptr;

    static constexpr int SAMPLE_COUNT = 5;
    static constexpr int SAMPLE_INTERVAL_MS = 100;
    static constexpr int BATCH_INTERVAL_MS = 3000;
};
