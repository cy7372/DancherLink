#include "audioqualitymonitor.h"

#include <QtGlobal>

AudioQualityMonitor* AudioQualityMonitor::s_Instance = nullptr;

AudioQualityMonitor::AudioQualityMonitor(QObject* parent)
    : QObject(parent)
{
}

AudioQualityMonitor* AudioQualityMonitor::instance()
{
    static AudioQualityMonitor* s_Instance = nullptr;
    if (s_Instance == nullptr) {
        s_Instance = new AudioQualityMonitor();
    }
    return s_Instance;
}

void AudioQualityMonitor::start()
{
    QWriteLocker locker(&m_StatsLock);
    m_Running = true;
    m_CurrentStats = AudioStats();
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
    QWriteLocker locker(&m_StatsLock);

    if (!m_Running) {
        return;
    }

    m_CurrentStats.audioPackets = audioPackets;
    m_CurrentStats.fecPackets = fecPackets;
    m_CurrentStats.fecRecovered = fecRecovered;
    m_CurrentStats.fecFailed = fecFailed;
    m_CurrentStats.outOfSequence = outOfSequence;

    // Calculate packet loss rate
    // Total expected packets = audio packets + FEC packets
    // Lost packets = FEC failed (packets that couldn't be recovered)
    quint32 totalPackets = audioPackets + fecPackets;
    if (totalPackets > 0) {
        // FEC failed represents packets that were lost and couldn't be recovered
        m_CurrentStats.packetLossRate = static_cast<float>(fecFailed) / totalPackets;

        // FEC recovery rate = successfully recovered / total FEC sent
        if (fecPackets > 0) {
            m_CurrentStats.fecRecoveryRate = static_cast<float>(fecRecovered) / fecPackets;
        } else {
            m_CurrentStats.fecRecoveryRate = 0.0f;
        }
    }

    // Update quality assessment
    updateQualityAssessment();

    emit statsUpdated();
}

void AudioQualityMonitor::updateQualityAssessment()
{
    float lossRate = m_CurrentStats.packetLossRate;
    float fecRate = m_CurrentStats.fecRecoveryRate;

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

    emit qualityChanged();
}

QString AudioQualityMonitor::qualityString() const
{
    QReadLocker locker(&m_StatsLock);

    switch (m_CurrentStats.quality) {
    case AudioQuality::Excellent:
        return tr("Excellent");
    case AudioQuality::Good:
        return tr("Good");
    case AudioQuality::Fair:
        return tr("Fair");
    case AudioQuality::Poor:
        return tr("Poor");
    case AudioQuality::Bad:
        return tr("Bad");
    }

    return tr("Unknown");
}
