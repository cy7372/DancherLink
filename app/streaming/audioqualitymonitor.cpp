#include "audioqualitymonitor.h"

#include <QtGlobal>
#include <QCoreApplication>
#include <SDL.h>

AudioQualityMonitor* AudioQualityMonitor::instance()
{
    static AudioQualityMonitor* s_Instance = nullptr;
    if (s_Instance == nullptr) {
        s_Instance = new AudioQualityMonitor();
    }
    return s_Instance;
}

AudioQualityMonitor::AudioQualityMonitor(QObject* parent)
    : QObject(parent)
{
    // Initialize smoothing parameters
    m_SmoothingParams.windowSize = 5;
    m_SmoothingParams.alpha = 0.3f;
    m_SmoothingParams.updateIntervalMs = 500;
}

void AudioQualityMonitor::start()
{
    QWriteLocker locker(&m_StatsLock);
    m_Running = true;
    m_CurrentStats = AudioStats();
    m_PreviousStats = AudioStats();
    m_SmoothedLossRate = 0.0f;
    m_SmoothedRecoveryRate = 0.0f;
    m_LossRateHistory.clear();
    m_RecoveryRateHistory.clear();
    m_LastUpdateTime = 0;
    m_PreviousQuality = AudioQuality::Excellent;
}

void AudioQualityMonitor::stop()
{
    QWriteLocker locker(&m_StatsLock);
    m_Running = false;
}

void AudioQualityMonitor::updateStats(quint32 audioPackets, quint32 fecPackets,
                                       quint32 fecRecovered, quint32 fecFailed,
                                       quint32 outOfSequence)
{
    // Collect signal to emit after releasing the lock
    bool emitUpdate = false;

    {
        QWriteLocker locker(&m_StatsLock);

        if (!m_Running) {
            return;
        }

        // Update raw stats
        m_CurrentStats.audioPackets = audioPackets;
        m_CurrentStats.fecPackets = fecPackets;
        m_CurrentStats.fecRecovered = fecRecovered;
        m_CurrentStats.fecFailed = fecFailed;
        m_CurrentStats.outOfSequence = outOfSequence;

        // Calculate packet loss rate
        quint32 totalPackets = audioPackets + fecPackets;
        if (totalPackets > 0) {
            float lossRate = static_cast<float>(fecFailed) / totalPackets;
            float recoveryRate = (fecPackets > 0) ?
                                 static_cast<float>(fecRecovered) / fecPackets : 0.0f;

            // Add to history for smoothing
            m_LossRateHistory.append(lossRate);
            m_RecoveryRateHistory.append(recoveryRate);

            // Keep history window bounded
            while (m_LossRateHistory.size() > m_SmoothingParams.windowSize) {
                m_LossRateHistory.removeFirst();
            }
            while (m_RecoveryRateHistory.size() > m_SmoothingParams.windowSize) {
                m_RecoveryRateHistory.removeFirst();
            }

            // Update smoothed rates using exponential moving average
            updateSmoothedMetrics();

            // Apply smoothed values to current stats
            m_CurrentStats.packetLossRate = m_SmoothedLossRate;
            m_CurrentStats.fecRecoveryRate = m_SmoothedRecoveryRate;
        } else {
            m_CurrentStats.packetLossRate = 0.0f;
            m_CurrentStats.fecRecoveryRate = 0.0f;
        }

        // Rate-limit quality updates to avoid flickering
        quint32 currentTime = SDL_GetTicks();
        if (currentTime - m_LastUpdateTime >= static_cast<quint32>(m_SmoothingParams.updateIntervalMs)) {
            updateQualityAssessment();
            m_LastUpdateTime = currentTime;

            // Emit signals if quality changed
            if (m_CurrentStats.quality != m_PreviousQuality) {
                emitUpdate = true;
                m_PreviousQuality = m_CurrentStats.quality;
            }
        }
    }

    if (emitUpdate) {
        emit qualityChanged();
    }
    emit statsUpdated();
}

void AudioQualityMonitor::updateSmoothedMetrics()
{
    if (m_LossRateHistory.isEmpty()) {
        m_SmoothedLossRate = 0.0f;
        m_SmoothedRecoveryRate = 0.0f;
        return;
    }

    // Use EMA smoothing similar to LatencyMeasurer
    float alpha = m_SmoothingParams.alpha;

    if (m_SmoothedLossRate < 0.0f) {
        m_SmoothedLossRate = m_LossRateHistory.first();
    } else {
        // EMA: smoothed = α * new + (1-α) * old
        m_SmoothedLossRate = alpha * m_LossRateHistory.last() + (1.0f - alpha) * m_SmoothedLossRate;
    }

    if (m_SmoothedRecoveryRate < 0.0f) {
        m_SmoothedRecoveryRate = m_RecoveryRateHistory.first();
    } else {
        m_SmoothedRecoveryRate = alpha * m_RecoveryRateHistory.last() + (1.0f - alpha) * m_SmoothedRecoveryRate;
    }
}

void AudioQualityMonitor::updateQualityAssessment()
{
    float lossRate = m_CurrentStats.packetLossRate;
    float fecRate = m_CurrentStats.fecRecoveryRate;

    // Quality thresholds (using smoothed values)
    if (lossRate < 0.01f && fecRate < 0.05f) {
        m_CurrentStats.quality = AudioQuality::Excellent;
    } else if (lossRate < 0.03f && fecRate < 0.15f) {
        m_CurrentStats.quality = AudioQuality::Good;
    } else if (lossRate < 0.05f && fecRate < 0.30f) {
        m_CurrentStats.quality = AudioQuality::Fair;
    } else if (lossRate < 0.10f && fecRate < 0.50f) {
        m_CurrentStats.quality = AudioQuality::Poor;
    } else {
        m_CurrentStats.quality = AudioQuality::Bad;
    }
}

QString AudioQualityMonitor::qualityString() const
{
    QReadLocker locker(&m_StatsLock);

    switch (m_CurrentStats.quality) {
    case AudioQuality::Excellent:
        return QCoreApplication::translate("AudioQualityMonitor", "Excellent");
    case AudioQuality::Good:
        return QCoreApplication::translate("AudioQualityMonitor", "Good");
    case AudioQuality::Fair:
        return QCoreApplication::translate("AudioQualityMonitor", "Fair");
    case AudioQuality::Poor:
        return QCoreApplication::translate("AudioQualityMonitor", "Poor");
    case AudioQuality::Bad:
        return QCoreApplication::translate("AudioQualityMonitor", "Bad");
    }

    return QCoreApplication::translate("AudioQualityMonitor", "Unknown");
}
