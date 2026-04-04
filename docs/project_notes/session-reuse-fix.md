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
