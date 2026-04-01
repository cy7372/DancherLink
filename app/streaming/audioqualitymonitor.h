#pragma once

#include <QObject>
#include <QReadWriteLock>
#include <QString>
#include <QList>

// Audio quality level enumeration
enum class AudioQuality {
    Excellent,  // < 1% packet loss, FEC recovery < 5%
    Good,       // 1-3% packet loss, FEC recovery 5-15%
    Fair,       // 3-5% packet loss, FEC recovery 15-30%
    Poor,       // 5-10% packet loss, FEC recovery 30-50%
    Bad         // > 10% packet loss, FEC recovery > 50%
};

// Audio statistics snapshot
struct AudioStats {
    // Packet counts
    quint32 audioPackets = 0;
    quint32 fecPackets = 0;
    quint32 fecRecovered = 0;
    quint32 fecFailed = 0;
    quint32 outOfSequence = 0;

    // Calculated metrics
    float packetLossRate = 0.0f;      // Estimated packet loss rate (0-1)
    float fecRecoveryRate = 0.0f;     // FEC recovery success rate (0-1)

    // Quality assessment
    AudioQuality quality = AudioQuality::Excellent;
};

// Smoothing parameters for audio quality
struct AudioSmoothingParams {
    int windowSize = 5;           // Number of samples to average
    float alpha = 0.3f;           // Exponential smoothing factor
    int updateIntervalMs = 500;   // Minimum time between quality updates
};

class AudioQualityMonitor : public QObject
{
    Q_OBJECT
    Q_PROPERTY(AudioQuality quality READ quality NOTIFY qualityChanged)
    Q_PROPERTY(float packetLossRate READ packetLossRate NOTIFY statsUpdated)
    Q_PROPERTY(float fecRecoveryRate READ fecRecoveryRate NOTIFY statsUpdated)
    Q_PROPERTY(QString qualityString READ qualityString NOTIFY qualityChanged)

public:
    static AudioQualityMonitor* instance();

    void start();
    void stop();

    void updateStats(quint32 audioPackets, quint32 fecPackets,
                     quint32 fecRecovered, quint32 fecFailed,
                     quint32 outOfSequence);

    AudioQuality quality() const { return m_CurrentStats.quality; }
    float packetLossRate() const { return m_CurrentStats.packetLossRate; }
    float fecRecoveryRate() const { return m_CurrentStats.fecRecoveryRate; }
    QString qualityString() const;

    AudioStats currentStats() const { return m_CurrentStats; }

signals:
    void qualityChanged();
    void statsUpdated();

private:
    AudioQualityMonitor(QObject* parent = nullptr);

    void updateQualityAssessment();
    void updateSmoothedMetrics();

    AudioStats m_CurrentStats;
    AudioStats m_PreviousStats;
    mutable QReadWriteLock m_StatsLock;
    bool m_Running = false;

    // Smoothing state
    float m_SmoothedLossRate = 0.0f;
    float m_SmoothedRecoveryRate = 0.0f;
    QList<float> m_LossRateHistory;
    QList<float> m_RecoveryRateHistory;
    quint32 m_LastUpdateTime = 0;
    AudioQuality m_PreviousQuality = AudioQuality::Excellent;

    AudioSmoothingParams m_SmoothingParams;
};
