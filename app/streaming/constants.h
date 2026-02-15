#pragma once

// ============================================================================
// DancherLink Streaming Constants
// Centralized definition of magic numbers used throughout the streaming module
// ============================================================================

namespace StreamingConstants {

// ----------------------------------------------------------------------------
// Resolution Constants
// ----------------------------------------------------------------------------

// Common resolution dimensions
constexpr int HD_WIDTH = 1280;
constexpr int HD_HEIGHT = 720;

constexpr int FHD_WIDTH = 1920;
constexpr int FHD_HEIGHT = 1080;

constexpr int QHD_WIDTH = 2560;
constexpr int QHD_HEIGHT = 1440;

constexpr int UHD_4K_WIDTH = 3840;
constexpr int UHD_4K_HEIGHT = 2160;

// Maximum dimensions for various encoders
constexpr int NVENC_MAX_DIMENSION = 4096;
constexpr int H264_MAX_DIMENSION = 4096;

// Default resolution for decoder probing
constexpr int PROBE_WIDTH = FHD_WIDTH;
constexpr int PROBE_HEIGHT = FHD_HEIGHT;
constexpr int PROBE_FPS = 60;

// ----------------------------------------------------------------------------
// Network Packet Size Constants
// ----------------------------------------------------------------------------

// Default packet size for LAN streaming (fits in most MTU with headers)
constexpr int DEFAULT_PACKET_SIZE = 1392;

// Packet size for VPN/remote streaming (conservative for tunneling overhead)
constexpr int VPN_PACKET_SIZE = 1024;

// Packet size for remote IPv6 streaming
constexpr int REMOTE_IPV6_PACKET_SIZE = 1184;

// Packet size alignment (FEC requires 16-byte alignment)
constexpr int PACKET_SIZE_ALIGNMENT = 16;

// ----------------------------------------------------------------------------
// Timing Constants (milliseconds)
// ----------------------------------------------------------------------------

// Thread pool shutdown timeout
constexpr int THREAD_POOL_WAIT_TIMEOUT_MS = 30000;

// Socket write timeout
constexpr int SOCKET_WRITE_TIMEOUT_MS = 1000;

// Default window scale ratio
constexpr float DEFAULT_WINDOW_SCALE_RATIO = 0.80f;

// Common delay values
constexpr int SHORT_DELAY_MS = 500;          // Short delay for UI/cleanup operations
constexpr int MEDIUM_DELAY_MS = 1000;        // Medium delay for network operations
constexpr int LONG_DELAY_MS = 5000;          // Long delay for logging intervals

// Single instance socket timeouts
constexpr int SINGLE_INSTANCE_CONNECT_TIMEOUT_MS = 500;
constexpr int SINGLE_INSTANCE_WRITE_TIMEOUT_MS = 1000;

// Host connection timeouts
constexpr int HOST_REACHABILITY_TIMEOUT_MS = 3000;
constexpr int HOST_READY_CHECK_RETRY_DELAY_MS = 500;

// Service unavailable retry delay (seconds)
constexpr int SERVICE_UNAVAILABLE_RETRY_DELAY_SEC = 5;

// Async log flush timeout
constexpr int ASYNC_LOG_FLUSH_TIMEOUT_MS = 500;

// Steam Link window creation delay
constexpr int STEAM_LINK_WINDOW_CREATION_DELAY_MS = 500;

// Audio pipeline latency delay
constexpr int AUDIO_PIPELINE_LATENCY_DELAY_MS = 500;

// Bandwidth update interval
constexpr int BANDWIDTH_UPDATE_INTERVAL_MS = 1000;

// Resize reset cooldown
constexpr int RESIZE_RESET_COOLDOWN_MS = 500;

// Frame latency wait timeout
constexpr int FRAME_LATENCY_WAIT_TIMEOUT_MS = 1000;

// Pace history window
constexpr int PACE_HISTORY_WINDOW_MS = 500;

// Gamepad rumble duration
constexpr int GAMEPAD_RUMBLE_DURATION_MS = 30000;

// Stats measurement window (microseconds)
constexpr int STATS_MEASUREMENT_WINDOW_US = 1000000;

// VPN detection minimum MTU
constexpr int VPN_DETECTION_MIN_MTU = 1500;

// ----------------------------------------------------------------------------
// Bitrate Constants
// ----------------------------------------------------------------------------

// FEC overhead percentage (20% of video bitrate reserved for FEC)
constexpr float FEC_OVERHEAD_RATIO = 0.80f;

// Bitrate cap for remote streaming (Kbps)
constexpr int REMOTE_STREAM_BITRATE_CAP = 100000;

// Remote streaming audio/control overhead (Kbps)
constexpr int REMOTE_STREAM_OVERHEAD_KBPS = 500;

// ----------------------------------------------------------------------------
// Audio Constants
// ----------------------------------------------------------------------------

// Opus encoder settings
constexpr int OPUS_SAMPLE_RATE = 48000;
constexpr int OPUS_BITRATE = 64000;
constexpr int MAX_OPUS_PACKET_SIZE = 4000;

// Audio logging interval
constexpr int AUDIO_LOG_INTERVAL_MS = 5000;

// ----------------------------------------------------------------------------
// Display Constants
// ----------------------------------------------------------------------------

// Maximum display dimension for probing
constexpr int MAX_DISPLAY_DIMENSION = 8192;

// Test window dimensions for GPU capability probing
constexpr int TEST_WINDOW_WIDTH = 1280;
constexpr int TEST_WINDOW_HEIGHT = 720;

// Hidden cursor position
constexpr int CURSOR_HIDDEN_X = 0xFFFF;
constexpr int CURSOR_HIDDEN_Y = 0xFFFF;

// ----------------------------------------------------------------------------
// Platform-Specific Constants
// ----------------------------------------------------------------------------

// ThinkPad X1 Fold special resolution handling
// This device reports a non-standard resolution that requires special handling
namespace ThinkPadX1Fold {
    constexpr int WIDTH = 1536;
    constexpr int HEIGHT = 1006;
    constexpr int HEIGHT_TOLERANCE = 20;
    constexpr int ALIGNMENT = 16;
}

// ----------------------------------------------------------------------------
// Video Decoder Constants
// ----------------------------------------------------------------------------

// Decode buffer size
constexpr int DECODE_BUFFER_SIZE = 1024 * 1024;  // 1 MB

// FFmpeg timebase denominator
constexpr int TIMEBASE_DENOMINATOR = 90000;

// HDR colorimetry denominators
constexpr int DISPLAY_PRIMARIES_DENOMINATOR = 50000;
constexpr int WHITE_POINT_DENOMINATOR = 50000;
constexpr int MIN_LUMINANCE_DENOMINATOR = 10000;

}  // namespace StreamingConstants
