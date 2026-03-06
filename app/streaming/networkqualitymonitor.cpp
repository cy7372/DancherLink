#include "networkqualitymonitor.h"
#include "Limelight.h"

#include <QDebug>
#include <SDL.h>

NetworkQualityMonitor* NetworkQualityMonitor::s_Instance = nullptr;

NetworkQualityMonitor::NetworkQualityMonitor(QObject* parent)
    : QObject(parent)
    , m_SmoothedLossRate(0.0f)
    , m_SmoothedRecoveryRate(0.0f)
    , m_CurrentBitrate(0)
    , m_OriginalBitrate(0)
    , m_LastUpdateTime(0)
    , m_FrameCount(0)
    , m_PreviousQuality(NetworkQuality::Excellent)
    , m_LastIdrRequestTime(0)
{
}

NetworkQualityMonitor::~NetworkQualityMonitor()
{
    stop();
}

NetworkQualityMonitor* NetworkQualityMonitor::instance()
{
    if (!s_Instance) {
        s_Instance = new NetworkQualityMonitor();
    }
    return s_Instance;
}

void NetworkQualityMonitor::start(quint32 initialBitrate)
{
    QWriteLocker lock(&m_Lock);

    // Reset all stats
    m_CurrentStats = NetworkStats();
    m_PreviousStats = NetworkStats();
    m_SmoothedLossRate = 0.0f;
    m_SmoothedRecoveryRate = 0.0f;
    m_LossRateHistory.clear();

    m_CurrentBitrate = initialBitrate;
    m_OriginalBitrate = initialBitrate;
    m_CurrentStats.currentBitrate = initialBitrate;

    // Reset timing
    m_LastUpdateTime = SDL_GetTicks();
    m_FrameCount = 0;

    // Reset IDR tracking
    m_PreviousQuality = NetworkQuality::Excellent;
    m_LastIdrRequestTime = 0;

    qDebug() << "[NetQuality] Monitor started with bitrate:" << initialBitrate << "kbps";
}

void NetworkQualityMonitor::stop()
{
    qDebug() << "[NetQuality] Monitor stopped";
}

void NetworkQualityMonitor::updateStats(quint32 videoPackets, quint32 fecPackets,
                                         quint32 fecRecovered, quint32 fecFailed,
                                         quint32 outOfSequence)
{
    QWriteLocker lock(&m_Lock);

    m_CurrentStats.videoPackets = videoPackets;
    m_CurrentStats.fecPackets = fecPackets;
    m_CurrentStats.fecRecovered = fecRecovered;
    m_CurrentStats.fecFailed = fecFailed;
    m_CurrentStats.outOfSequence = outOfSequence;

    // Only process every ~60 frames (~1 second at 60fps) to reduce overhead
    m_FrameCount++;
    if (m_FrameCount < 60) {
        return;
    }
    m_FrameCount = 0;

    // Calculate deltas from last update
    m_DeltaVideoPackets = m_CurrentStats.videoPackets - m_PreviousStats.videoPackets;
    m_DeltaFecRecovered = m_CurrentStats.fecRecovered - m_PreviousStats.fecRecovered;
    m_DeltaFecFailed = m_CurrentStats.fecFailed - m_PreviousStats.fecFailed;

    // Store previous stats
    m_PreviousStats = m_CurrentStats;

    // Calculate metrics
    calculateMetrics();

    // Assess quality
    assessQuality();

    // Calculate recommendations
    calculateRecommendations();

    emit statsUpdated();
}

void NetworkQualityMonitor::calculateMetrics()
{
    // Calculate packet loss rate estimation
    // Loss rate = (recovered + failed) / (video packets + recovered + failed)
    // This estimates actual loss since FEC can recover some packets
    quint32 totalPacketsExpected = m_DeltaVideoPackets + m_DeltaFecRecovered + m_DeltaFecFailed;

    if (totalPacketsExpected > 0) {
        float instantLossRate = (float)(m_DeltaFecRecovered + m_DeltaFecFailed) / totalPacketsExpected;

        // Smooth the loss rate using exponential moving average
        m_SmoothedLossRate = m_SmoothedLossRate * 0.7f + instantLossRate * 0.3f;
        m_CurrentStats.packetLossRate = m_SmoothedLossRate;

        // Add to history for trend analysis
        m_LossRateHistory.append(instantLossRate);
        if (m_LossRateHistory.size() > HISTORY_SIZE) {
            m_LossRateHistory.removeFirst();
        }
    }

    // Calculate FEC recovery rate
    quint32 totalFecAttempts = m_DeltaFecRecovered + m_DeltaFecFailed;
    if (totalFecAttempts > 0) {
        float instantRecoveryRate = (float)m_DeltaFecRecovered / totalFecAttempts;
        m_SmoothedRecoveryRate = m_SmoothedRecoveryRate * 0.7f + instantRecoveryRate * 0.3f;
        m_CurrentStats.fecRecoveryRate = m_SmoothedRecoveryRate;
    } else {
        m_CurrentStats.fecRecoveryRate = 1.0f; // No FEC needed = perfect
    }

    // Calculate FEC efficiency (recovered / total FEC packets received)
    if (m_CurrentStats.fecPackets > 0) {
        m_CurrentStats.fecEfficiency = (float)m_CurrentStats.fecRecovered / m_CurrentStats.fecPackets;
    }
}

void NetworkQualityMonitor::assessQuality()
{
    NetworkQuality previousQuality = m_CurrentStats.quality;

    m_CurrentStats.quality = assessQualityFromMetrics(
        m_CurrentStats.packetLossRate,
        1.0f - m_CurrentStats.fecRecoveryRate
    );

    if (m_CurrentStats.quality != previousQuality) {
        qDebug() << "[NetQuality] Quality changed:"
                 << static_cast<int>(previousQuality) << "->"
                 << static_cast<int>(m_CurrentStats.quality)
                 << "Loss:" << m_CurrentStats.packetLossRate * 100 << "%"
                 << "FEC Recovery:" << m_CurrentStats.fecRecoveryRate * 100 << "%";
        emit qualityChanged(m_CurrentStats.quality);
    }

    // Smart IDR request: Request IDR frame when network is recovering
    // (quality improved from Bad/Poor to Fair/Good/Excellent)
    // or when quality is degraded to trigger faster recovery
    uint32_t now = SDL_GetTicks();
    bool shouldRequestIdr = false;

    if (now - m_LastIdrRequestTime >= IDR_COOLDOWN_MS) {
        // Case 1: Network recovery detected - request IDR to clean up artifacts
        if ((m_PreviousQuality == NetworkQuality::Bad || m_PreviousQuality == NetworkQuality::Poor) &&
            (m_CurrentStats.quality == NetworkQuality::Fair ||
             m_CurrentStats.quality == NetworkQuality::Good ||
             m_CurrentStats.quality == NetworkQuality::Excellent)) {
            qDebug() << "[NetQuality] Network recovery detected, requesting IDR frame";
            shouldRequestIdr = true;
        }
        // Case 2: Severe degradation - request IDR to help decoder recover
        else if (m_CurrentStats.quality == NetworkQuality::Bad &&
                 m_PreviousQuality != NetworkQuality::Bad) {
            qDebug() << "[NetQuality] Severe network degradation, requesting IDR frame";
            shouldRequestIdr = true;
        }
        // Case 3: High loss rate sustained - periodically request IDR
        else if (m_CurrentStats.packetLossRate > LOSS_RATE_POOR &&
                 now - m_LastIdrRequestTime >= IDR_COOLDOWN_MS * 3) {
            qDebug() << "[NetQuality] Sustained high loss rate, requesting IDR frame";
            shouldRequestIdr = true;
        }
    }

    if (shouldRequestIdr) {
        m_LastIdrRequestTime = now;
        emit idrFrameRequested();
    }

    m_PreviousQuality = m_CurrentStats.quality;

    // Emit warning for poor/bad quality
    if (m_CurrentStats.quality == NetworkQuality::Poor ||
        m_CurrentStats.quality == NetworkQuality::Bad) {
        QString message;
        if (m_CurrentStats.quality == NetworkQuality::Bad) {
            message = tr("Network quality is poor. Consider reducing bitrate or check your connection.");
        } else {
            message = tr("Network quality is degraded. Some frames may be dropped.");
        }
        emit networkWarning(message);
    }
}

NetworkQuality NetworkQualityMonitor::assessQualityFromMetrics(float lossRate, float fecFailureRate)
{
    // Combined scoring: consider both loss rate and FEC failure rate
    float combinedScore = lossRate * 0.6f + fecFailureRate * 0.4f;

    if (combinedScore < LOSS_RATE_EXCELLENT) {
        return NetworkQuality::Excellent;
    } else if (combinedScore < LOSS_RATE_GOOD) {
        return NetworkQuality::Good;
    } else if (combinedScore < LOSS_RATE_FAIR) {
        return NetworkQuality::Fair;
    } else if (combinedScore < LOSS_RATE_POOR) {
        return NetworkQuality::Poor;
    } else {
        return NetworkQuality::Bad;
    }
}

void NetworkQualityMonitor::calculateRecommendations()
{
    // Calculate recommended bitrate based on current quality
    // Bitrate multipliers: Excellent 100%, Good 90%, Fair 70%, Poor 50%, Bad 30%
    float bitrateMultiplier = 1.0f;

    switch (m_CurrentStats.quality) {
    case NetworkQuality::Excellent:
        // Can potentially increase bitrate if we're below original
        if (m_CurrentBitrate < m_OriginalBitrate) {
            bitrateMultiplier = 1.1f; // Try to recover
        }
        m_CurrentStats.shouldIncreaseFec = false;
        m_CurrentStats.shouldReduceBitrate = false;
        break;

    case NetworkQuality::Good:
        // Maintain current bitrate (90% of original)
        bitrateMultiplier = 0.90f;
        m_CurrentStats.shouldIncreaseFec = false;
        m_CurrentStats.shouldReduceBitrate = false;
        break;

    case NetworkQuality::Fair:
        // Reduce bitrate to 70% for stability
        bitrateMultiplier = 0.70f;
        m_CurrentStats.shouldIncreaseFec = true;
        m_CurrentStats.shouldReduceBitrate = true;
        break;

    case NetworkQuality::Poor:
        // Significantly reduce bitrate to 50%
        // Also recommend reducing FPS by 1 tier (e.g., 60→30, 120→60)
        bitrateMultiplier = 0.50f;
        m_CurrentStats.shouldIncreaseFec = true;
        m_CurrentStats.shouldReduceBitrate = true;
        break;

    case NetworkQuality::Bad:
        // Reduce to minimum viable bitrate (30%)
        // Also recommend reducing FPS by 2 tiers (e.g., 120→30, 60→30)
        bitrateMultiplier = 0.30f;
        m_CurrentStats.shouldIncreaseFec = true;
        m_CurrentStats.shouldReduceBitrate = true;
        break;
    }

    m_CurrentStats.recommendedBitrate = qMax(2000U,
        static_cast<quint32>(m_OriginalBitrate * bitrateMultiplier));
}

NetworkStats NetworkQualityMonitor::currentStats() const
{
    QReadLocker lock(&m_Lock);
    return m_CurrentStats;
}

NetworkQuality NetworkQualityMonitor::quality() const
{
    QReadLocker lock(&m_Lock);
    return m_CurrentStats.quality;
}

float NetworkQualityMonitor::packetLossRate() const
{
    QReadLocker lock(&m_Lock);
    return m_CurrentStats.packetLossRate;
}

float NetworkQualityMonitor::fecRecoveryRate() const
{
    QReadLocker lock(&m_Lock);
    return m_CurrentStats.fecRecoveryRate;
}

quint32 NetworkQualityMonitor::recommendedBitrate() const
{
    QReadLocker lock(&m_Lock);
    return m_CurrentStats.recommendedBitrate;
}

QString NetworkQualityMonitor::qualityString() const
{
    QReadLocker lock(&m_Lock);

    switch (m_CurrentStats.quality) {
    case NetworkQuality::Excellent:
        return tr("Excellent");
    case NetworkQuality::Good:
        return tr("Good");
    case NetworkQuality::Fair:
        return tr("Fair");
    case NetworkQuality::Poor:
        return tr("Poor");
    case NetworkQuality::Bad:
        return tr("Bad");
    default:
        return tr("Unknown");
    }
}

int NetworkQualityMonitor::bitrateAdjustment() const
{
    QReadLocker lock(&m_Lock);

    if (m_CurrentStats.recommendedBitrate < m_CurrentBitrate * 0.9f) {
        return -1; // Decrease
    } else if (m_CurrentStats.recommendedBitrate > m_CurrentBitrate * 1.1f) {
        return 1; // Increase
    }
    return 0; // Maintain
}

int NetworkQualityMonitor::suggestedBitrateChange() const
{
    QReadLocker lock(&m_Lock);

    if (m_CurrentBitrate == 0) return 0;

    int change = static_cast<int>(
        ((float)m_CurrentStats.recommendedBitrate / m_CurrentBitrate - 1.0f) * 100
    );
    return change;
}
