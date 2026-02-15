#pragma once

// ============================================================================
// CLI Common Constants
// Shared constants for CLI commands
// ============================================================================

namespace CliConstants {

// Computer seek timeout for operations that need to start a stream (longer)
constexpr int COMPUTER_SEEK_TIMEOUT_STREAM_MS = 30000;

// Computer seek timeout for quick operations like pairing and quitting (shorter)
constexpr int COMPUTER_SEEK_TIMEOUT_QUICK_MS = 10000;

// App seek timeout for operations that need to find an app
constexpr int APP_SEEK_TIMEOUT_MS = 10000;

}  // namespace CliConstants

// Convenience macros for backwards compatibility
#define COMPUTER_SEEK_TIMEOUT CliConstants::COMPUTER_SEEK_TIMEOUT_STREAM_MS
