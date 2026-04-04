# Server Session Reuse Fix - "Failed to decrypt RTSP response"

## Problem

When quickly reconnecting after early cancellation (canceling between HTTP /resume response and RTSP handshake completion), the client received "Failed to decrypt RTSP response" errors.

### Root Cause

The foundation-sunshine server reuses a previous session with an already-incremented `rtsp_iv_counter` when the client reconnects quickly. This causes an AES-GCM IV mismatch:

- Client expects: `seq=0, iv[0-3]=00000000` (fresh session)
- Server provides: `seq=1, iv[0-3]=01000000` (reused session with incremented counter)

The AES-GCM auth tag verification fails because the IVs don't match.

## Solution

Implemented a retry mechanism that detects session reuse and requests a fresh `/resume` from the server.

### Changes Made

#### 1. Rtsp.h - Added new error code
- `RTSP_ERROR_SESSION_REUSE -3` - Indicates server is reusing a previous session

#### 2. RtspConnection.c - Modified decryption error handling
- `unsealRtspMessage()`: Now returns `int` error code instead of `bool`
- When AES-GCM decryption fails, returns `RTSP_ERROR_SESSION_REUSE`
- Added detailed logging: `seq`, IV bytes, and "HR" marker
- Updated all RTSP transaction functions to propagate error codes:
  - `transactRtspMessageTcp()`
  - `transactRtspMessageEnet()`
  - `transactRtspMessage()`
  - `requestOptions()`
  - `requestDescribe()`
  - `setupStream()`
  - `playStream()`
  - `sendVideoAnnounce()`
  - `requestTeardown()`

#### 3. session.cpp - Implemented retry logic
- Added retry loop (max 2 retries) around `LiStartConnection()`
- On `RTSP_ERROR_SESSION_REUSE`:
  1. Call `LiStopConnection()` to clean up
  2. Request fresh `/resume` from server
  3. Update RTSP URL
  4. Retry connection
- Logs retry attempts for debugging

## Files Modified

1. `moonlight-common-c/moonlight-common-c/src/Rtsp.h`
2. `moonlight-common-c/moonlight-common-c/src/RtspConnection.c`
3. `app/streaming/session.cpp`

## Testing

Build version: 1.0.16.470-beta

Test scenario:
1. Start streaming
2. Cancel early (between HTTP /resume and RTSP handshake completion)
3. Immediately reconnect
4. Expected: Connection succeeds after retry
5. Previous behavior: "Failed to decrypt RTSP response" error

## Log Evidence

From `dl_0404_1524.log`:
```
Failed to decrypt RTSP response (seq=1, iv[0-3]=01000000, iv[10-11]=HR)
```

This shows the server was reusing a session with an already-incremented counter.

## Related Issues

- Early cancellation cleanup
- Server session state management
- AES-GCM encryption in RTSP handshake

## Future Improvements

1. Server-side fix: Ensure foundation-sunshine properly invalidates sessions on connection close
2. Consider implementing session ID tracking to detect reuse earlier
3. Add metrics to track how often retry is needed

## Update 2026-04-04: Cancellation Cooldown (Final Solution)

### Problem with Retry Approach

The retry mechanism was removed because it's not the right approach. The correct solution is **prevention + cooling period**, not post-failure retry.

### Root Cause

When the user cancels a connection attempt quickly (between HTTP /resume and RTSP handshake completion), the server doesn't have enough time to clean up its RTSP session state. If the user immediately reconnects, the server reuses the previous session with an already-incremented AES-GCM IV counter, causing decryption failure.

### Final Solution (v1.0.16.505)

**1. Prevention:** `/cancel` API is called when user cancels, telling the server to clean up.

**2. Cooldown:** After cancellation, a 3-second cooldown period is enforced before allowing a new connection attempt.

### Changes Made

#### 1. NvComputer.h - Added cooldown field
```cpp
// Cancellation cooldown (ephemeral, not serialized)
qint64 cancelCooldownUntil = 0;  // Timestamp when cooldown expires (ms since epoch)
```

#### 2. session.cpp - requestCancel() sets cooldown
```cpp
// Set cancellation cooldown timestamp (3 seconds)
if (m_Computer) {
    m_Computer->cancelCooldownUntil = SDL_GetTicks() + 3000;
}
```

#### 3. session.cpp - startConnectionAsync() enforces cooldown
```cpp
// Check if cooldown is active and wait if necessary
if (m_Computer && m_Computer->cancelCooldownUntil > 0) {
    Uint32 remainingMs = cooldownEnd - currentTick;
    if (currentTick < cooldownEnd) {
        SDL_Delay(remainingMs);  // Block until cooldown expires
    }
    m_Computer->cancelCooldownUntil = 0;  // Clear flag
}
```

### Why Cooldown Works

- **3 seconds is enough** for the server to purge its session state
- **Blocking wait** ensures the user cannot accidentally reconnect too quickly
- **Simple and reliable** - no complex retry logic or state management
- **User-friendly** - shows a brief pause instead of multiple failed attempts

### Files Modified

- `app/backend/nvcomputer.h` - Added `cancelCooldownUntil` field
- `app/streaming/session.cpp` - Set cooldown in `requestCancel()`, enforce in `startConnectionAsync()`

### Testing

Build version: 1.0.16.505-beta

Test scenario:
1. Start streaming
2. Cancel early (during connection handshake)
3. Immediately try to reconnect
4. Expected: System waits ~3 seconds before attempting new connection
5. Result: Server has cleaned up session, connection succeeds
