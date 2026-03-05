#pragma once

#include <QObject>
#include <QReadWriteLock>

// Network quality level enumeration
enum class NetworkQuality {
    Excellent,  // < 1% packet loss, FEC recovery < 5%
    Good,       // 1-3% packet loss, FEC recovery 5-15%
    Fair,       // 3-5% packet loss, FEC recovery 15-30%
    Poor,       // 5-10% packet loss, FEC recovery 30-50%
    Bad         // > 10% packet loss, FEC recovery > 50%
};

// Network statistics snapshot
struct NetworkStats {
    // Packet counts
    quint32 videoPackets = 0;
    quint32 fecPackets = 0;
    quint32 fecRecovered = 0;
    quint32 fecFailed = 0;
    quint32 outOfSequence = 0;

    // Calculated metrics
    float packetLossRate = 0.0f;      // Estimated packet loss rate (0-1)
    float fecRecoveryRate = 0.0f;     // FEC recovery success rate (0-1)
    float fecEfficiency = 0.0f;       // FEC overhead vs benefit ratio

    // Quality assessment
    NetworkQuality quality = NetworkQuality::Excellent;

    // Recommendations
    quint32 recommendedBitrate = 0;    // Recommended bitrate in kbps
    quint32 currentBitrate = 0;        // Current streaming bitrate in kbps
    bool shouldReduceBitrate = false;
    bool shouldIncreaseFec = false;
};

class NetworkQualityMonitor : public QObject
{
    Q_OBJECT
    Q_PROPERTY(NetworkQuality quality READ quality NOTIFY qualityChanged)
    Q_PROPERTY(float packetLossRate READ packetLossRate NOTIFY statsUpdated)
    Q_PROPERTY(float fecRecoveryRate READ fecRecoveryRate NOTIFY statsUpdated)
    Q_PROPERTY(quint32 recommendedBitrate READ recommendedBitrate NOTIFY statsUpdated)
    Q_PROPERTY(QString qualityString READ qualityString NOTIFY qualityChanged)

public:
    static NetworkQualityMonitor* instance();

    // Start monitoring (call when streaming starts)
    void start(quint32 initialBitrate);

    // Stop monitoring (call when streaming ends)
    void stop();

    // Update stats from RTP data (call periodically)
    void updateStats(quint32 videoPackets, quint32 fecPackets,
                     quint32 fecRecovered, quint32 fecFailed,
                     quint32 outOfSequence);

    // Get current stats
    NetworkStats currentStats() const;

    // Quick accessors for QML
    NetworkQuality quality() const;
    float packetLossRate() const;
    float fecRecoveryRate() const;
    quint32 recommendedBitrate() const;
    QString qualityString() const;

    // Get bitrate adjustment suggestion (-1 = decrease, 0 = maintain, 1 = increase)
    int bitrateAdjustment() const;

    // Get suggested bitrate change percentage
    int suggestedBitrateChange() const;

signals:
    void qualityChanged(NetworkQuality newQuality);
    void statsUpdated();
    void bitrateRecommendationChanged(quint32 recommendedBitrate);
    void networkWarning(const QString& message);
    void idrFrameRequested();  // Emitted when network recovery needs IDR frame

private:
    explicit NetworkQualityMonitor(QObject* parent = nullptr);
    ~NetworkQualityMonitor();

    void calculateMetrics();
    void assessQuality();
    void calculateRecommendations();
    NetworkQuality assessQualityFromMetrics(float lossRate, float fecRate);

    static NetworkQualityMonitor* s_Instance;

    mutable QReadWriteLock m_Lock;

    // Current stats
    NetworkStats m_CurrentStats;
    NetworkStats m_PreviousStats;

    // Delta stats (for rate calculation)
    quint32 m_DeltaVideoPackets;
    quint32 m_DeltaFecRecovered;
    quint32 m_DeltaFecFailed;

    // Smoothing
    float m_SmoothedLossRate;
    float m_SmoothedRecoveryRate;

    // Bitrate tracking
    quint32 m_CurrentBitrate;
    quint32 m_OriginalBitrate;

    // Frame-based update control (instead of QTimer)
    quint32 m_LastUpdateTime;
    int m_FrameCount;

    // IDR request tracking
    NetworkQuality m_PreviousQuality;
    quint32 m_LastIdrRequestTime;
    static const int IDR_COOLDOWN_MS = 2000;  // Minimum time between IDR requests

    // History for trend analysis
    QList<float> m_LossRateHistory;
    static const int HISTORY_SIZE = 10;

    // Thresholds
    static constexpr float LOSS_RATE_EXCELLENT = 0.01f;
    static constexpr float LOSS_RATE_GOOD = 0.03f;
    static constexpr float LOSS_RATE_FAIR = 0.05f;
    static constexpr float LOSS_RATE_POOR = 0.10f;

    static constexpr float FEC_RATE_GOOD = 0.15f;
    static constexpr float FEC_RATE_FAIR = 0.30f;
    static constexpr float FEC_RATE_POOR = 0.50f;
};
