#include "Limelight-internal.h"

#define FIRST_FRAME_MAX 1500
#define FIRST_FRAME_TIMEOUT_SEC 10

#define FIRST_FRAME_PORT 47996

static RTP_VIDEO_QUEUE rtpQueue;

static SOCKET rtpSocket = INVALID_SOCKET;
static SOCKET firstFrameSocket = INVALID_SOCKET;

static PPLT_CRYPTO_CONTEXT decryptionCtx;

static PLT_THREAD udpPingThread;
static PLT_THREAD receiveThread;
static PLT_THREAD decoderThread;

static bool receivedDataFromPeer;
static uint64_t firstDataTimeMs;
static bool receivedFullFrame;

// We can't request an IDR frame until the depacketizer knows
// that a packet was lost. This timeout bounds the time that
// the RTP queue will wait for missing/reordered packets.
#define RTP_QUEUE_DELAY 10

// This is the desired number of video packets that can be
// stored in the socket's receive buffer. 8192 supports
// 4K high bitrate streams with large I-frames and provides
// better burst tolerance for network jitter and server hiccups.
#define RTP_RECV_PACKETS_BUFFERED 8192

// Initialize the video stream
void initializeVideoStream(void) {
    initializeVideoDepacketizer(StreamConfig.packetSize);
    RtpvInitializeQueue(&rtpQueue);
    decryptionCtx = PltCreateCryptoContext();
    receivedDataFromPeer = false;
    firstDataTimeMs = 0;
    receivedFullFrame = false;
}

// Clean up the video stream
void destroyVideoStream(void) {
    PltDestroyCryptoContext(decryptionCtx);
    destroyVideoDepacketizer();
    RtpvCleanupQueue(&rtpQueue);
}

// UDP Ping proc
static void VideoPingThreadProc(void* context) {
    char legacyPingData[] = { 0x50, 0x49, 0x4E, 0x47 };
    LC_SOCKADDR saddr;

    LC_ASSERT(VideoPortNumber != 0);

    memcpy(&saddr, &RemoteAddr, sizeof(saddr));
    SET_PORT(&saddr, VideoPortNumber);

    // We do not check for errors here. Socket errors will be handled
    // on the read-side in ReceiveThreadProc(). This avoids potential
    // issues related to receiving ICMP port unreachable messages due
    // to sending a packet prior to the host PC binding to that port.
    int pingCount = 0;
    while (!PltIsThreadInterrupted(&udpPingThread)) {
        if (VideoPingPayload.payload[0] != 0) {
            pingCount++;
            VideoPingPayload.sequenceNumber = BE32(pingCount);

            sendto(rtpSocket, (char*)&VideoPingPayload, sizeof(VideoPingPayload), 0, (struct sockaddr*)&saddr, AddrLen);
        }
        else {
            sendto(rtpSocket, legacyPingData, sizeof(legacyPingData), 0, (struct sockaddr*)&saddr, AddrLen);
        }

        PltSleepMsInterruptible(&udpPingThread, 500);
    }
}

// Network diagnostics - set to 1 to enable (adds ~8ms latency overhead)
#define NET_DIAG_ENABLED 0

// Receive thread proc
static void VideoReceiveThreadProc(void* context) {
    int err;
    int bufferSize, receiveSize, decryptedSize, minSize;
    char* buffer;
    char* encryptedBuffer;
    int queueStatus;
    bool useSelect;
    int waitingForVideoMs;
    bool encrypted;

#if NET_DIAG_ENABLED
    // Network diagnostics counters
    uint64_t totalPacketsReceived = 0;
    uint64_t lastDiagTimeMs = 0;
    uint64_t diagIntervalPackets = 0;
    uint64_t lastPacketTimeMs = 0;
    uint64_t maxPacketGapMs = 0;
    uint64_t consecutiveTimeouts = 0;
    #define NET_DIAG_INTERVAL_MS 5000  // Log every 5 seconds
    #define PACKET_GAP_WARNING_MS 100  // Warn if no packet for 100ms

    // Enhanced timing diagnostics
    uint64_t totalDecryptTimeUs = 0;
    uint64_t totalQueueTimeUs = 0;
    uint64_t maxDecryptTimeUs = 0;
    uint64_t maxQueueTimeUs = 0;
    uint64_t maxSocketQueueBytes = 0;
    uint64_t decryptCount = 0;
    uint32_t lastSeqNum = 0;
    uint32_t seqNumDiscontinuities = 0;
    bool firstPacket = true;
#endif

    encrypted = !!(EncryptionFeaturesEnabled & SS_ENC_VIDEO);
    decryptedSize = StreamConfig.packetSize + MAX_RTP_HEADER_SIZE;
    minSize = sizeof(RTP_PACKET) + ((EncryptionFeaturesEnabled & SS_ENC_VIDEO) ? sizeof(ENC_VIDEO_HEADER) : 0);
    receiveSize = decryptedSize + ((EncryptionFeaturesEnabled & SS_ENC_VIDEO) ? sizeof(ENC_VIDEO_HEADER) : 0);
    bufferSize = decryptedSize + sizeof(RTPV_QUEUE_ENTRY);
    buffer = NULL;

    if (setNonFatalRecvTimeoutMs(rtpSocket, UDP_RECV_POLL_TIMEOUT_MS) < 0) {
        // SO_RCVTIMEO failed, so use select() to wait
        useSelect = true;
    }
    else {
        // SO_RCVTIMEO timeout set for recv()
        useSelect = false;
    }

    // Allocate a staging buffer to use for each received packet
    if (encrypted) {
        encryptedBuffer = (char*)malloc(receiveSize);
        if (encryptedBuffer == NULL) {
            Limelog("Video Receive: malloc() failed\n");
            ListenerCallbacks.connectionTerminated(-1);
            return;
        }
    }
    else {
        encryptedBuffer = NULL;
    }

    waitingForVideoMs = 0;
    while (!PltIsThreadInterrupted(&receiveThread)) {
        PRTP_PACKET packet;

        if (buffer == NULL) {
            buffer = (char*)malloc(bufferSize);
            if (buffer == NULL) {
                Limelog("Video Receive: malloc() failed\n");
                ListenerCallbacks.connectionTerminated(-1);
                break;
            }
        }

        err = recvUdpSocket(rtpSocket,
                            encrypted ? encryptedBuffer : buffer,
                            receiveSize,
                            useSelect);
        if (err < 0) {
            ListenerCallbacks.connectionTerminated(LastSocketFail());
            break;
        }
        else if  (err == 0) {
#if NET_DIAG_ENABLED
            consecutiveTimeouts++;
            // Log warning if we get multiple consecutive timeouts (indicates network issue)
            if (consecutiveTimeouts >= 10 && receivedDataFromPeer) {
                Limelog("[NET_DIAG] WARNING: %llu consecutive receive timeouts (no data for ~%llums)\n",
                        (unsigned long long)consecutiveTimeouts,
                        (unsigned long long)(consecutiveTimeouts * UDP_RECV_POLL_TIMEOUT_MS));
            }
#endif

            if (!receivedDataFromPeer) {
                // If we wait many seconds without ever receiving a video packet,
                // assume something is broken and terminate the connection.
                waitingForVideoMs += UDP_RECV_POLL_TIMEOUT_MS;
                if (waitingForVideoMs >= FIRST_FRAME_TIMEOUT_SEC * 1000) {
                    Limelog("Terminating connection due to lack of video traffic\n");
                    ListenerCallbacks.connectionTerminated(ML_ERROR_NO_VIDEO_TRAFFIC);
                    break;
                }
            }

            // Receive timed out; try again
            continue;
        }

#if NET_DIAG_ENABLED
        // Reset consecutive timeout counter on successful receive
        if (consecutiveTimeouts > 0 && receivedDataFromPeer) {
            Limelog("[NET_DIAG] Receive recovered after %llu timeouts (~%llums gap)\n",
                    (unsigned long long)consecutiveTimeouts,
                    (unsigned long long)(consecutiveTimeouts * UDP_RECV_POLL_TIMEOUT_MS));
        }
        consecutiveTimeouts = 0;

        // Check socket buffer status (how many bytes are waiting)
        #ifdef LC_WINDOWS
        u_long socketQueueBytes = 0;
        if (ioctlsocket(rtpSocket, FIONREAD, &socketQueueBytes) == 0) {
            if (socketQueueBytes > maxSocketQueueBytes) {
                maxSocketQueueBytes = socketQueueBytes;
            }
            // Warn if buffer is getting full (arbitrary threshold: 2MB)
            if (socketQueueBytes > 2 * 1024 * 1024) {
                Limelog("[NET_DIAG] WARNING: Socket buffer high: %llu bytes pending\n",
                        (unsigned long long)socketQueueBytes);
            }
        }
        #endif
#endif

        if (!receivedDataFromPeer) {
            receivedDataFromPeer = true;
            Limelog("Received first video packet after %d ms\n", waitingForVideoMs);

            firstDataTimeMs = PltGetMillis();
        }

#ifndef LC_FUZZING
        if (!receivedFullFrame) {
            if (PltGetMillis() - firstDataTimeMs >= FIRST_FRAME_TIMEOUT_SEC * 1000) {
                Limelog("Terminating connection due to lack of a successful video frame\n");
                ListenerCallbacks.connectionTerminated(ML_ERROR_NO_VIDEO_FRAME);
                break;
            }
        }
#endif

        if (err < minSize) {
            // Runt packet
            continue;
        }

        // Decrypt the packet into the buffer if encryption is enabled
        if (encrypted) {
            PENC_VIDEO_HEADER encHeader = (PENC_VIDEO_HEADER)encryptedBuffer;

            // If this frame is below our current frame number, discard it before decryption
            // to save CPU cycles decrypting FEC shards for a frame we already reassembled.
            //
            // Since this is happening _before_ decryption, this packet is not trusted yet.
            // It's imperative that we do not mutate any state based on this packet until
            // after it has been decrypted successfully!
            //
            // It's possible for an attacker to inject a fake packet that has any value of
            // header fields they want, however this provides them no benefit because we will
            // simply drop said packet here (if it's below the current frame number) or it
            // will pass this check and be dropped during decryption (if contents is tampered)
            // or after decryption in the RTP queue (if it's a replay of a previous authentic
            // packet from the host).
            //
            // In short, an attacker spoofing this value via MITM or sending malicious values
            // impersonating the host from off-link doesn't gain them anything. If they have
            // a true MITM, they can DoS our connection by just dropping all our traffic, so
            // tampering with packets to fail this check doesn't accomplish anything they
            // couldn't already do. If they're not on-link, we just throw their malicious
            // traffic away (as mentioned in the paragraph above) and continue accepting
            // legitmate video traffic.
            if (encHeader->frameNumber && LE32(encHeader->frameNumber) < RtpvGetCurrentFrameNumber(&rtpQueue)) {
                continue;
            }

#if NET_DIAG_ENABLED
            uint64_t decryptStartUs = PltGetMicroseconds();
#endif
            if (!PltDecryptMessage(decryptionCtx, ALGORITHM_AES_GCM, 0,
                                   (unsigned char*)StreamConfig.remoteInputAesKey, sizeof(StreamConfig.remoteInputAesKey),
                                   encHeader->iv, sizeof(encHeader->iv),
                                   encHeader->tag, sizeof(encHeader->tag),
                                   ((unsigned char*)(encHeader + 1)), err - sizeof(ENC_VIDEO_HEADER), // The ciphertext is after the header
                                   (unsigned char*)buffer, &err)) {
                Limelog("Failed to decrypt video packet!\n");
                continue;
            }
#if NET_DIAG_ENABLED
            uint64_t decryptEndUs = PltGetMicroseconds();

            // Track decrypt timing
            uint64_t decryptTimeUs = decryptEndUs - decryptStartUs;
            totalDecryptTimeUs += decryptTimeUs;
            if (decryptTimeUs > maxDecryptTimeUs) {
                maxDecryptTimeUs = decryptTimeUs;
            }
            decryptCount++;

            // Warn if decryption is slow (over 1ms)
            if (decryptTimeUs > 1000) {
                Limelog("[NET_DIAG] Slow decrypt: %llu us\n", (unsigned long long)decryptTimeUs);
            }
#endif
        }

        // Convert fields to host byte-order
        packet = (PRTP_PACKET)&buffer[0];
        packet->sequenceNumber = BE16(packet->sequenceNumber);
        packet->timestamp = BE32(packet->timestamp);
        packet->ssrc = BE32(packet->ssrc);

#if NET_DIAG_ENABLED
        // Track sequence number discontinuities (potential packet loss)
        if (!firstPacket) {
            uint16_t seqDiff = (uint16_t)(packet->sequenceNumber - lastSeqNum);
            if (seqDiff > 1 && seqDiff < 32768) {  // Not wrap-around
                seqNumDiscontinuities += seqDiff - 1;
                if (seqDiff > 10) {
                    Limelog("[NET_DIAG] Large seq jump: %u -> %u (gap=%u)\n",
                            lastSeqNum, packet->sequenceNumber, seqDiff - 1);
                }
            }
        }
        lastSeqNum = packet->sequenceNumber;
        firstPacket = false;

        // Time the queue operation
        uint64_t queueStartUs = PltGetMicroseconds();
        queueStatus = RtpvAddPacket(&rtpQueue, packet, err, (PRTPV_QUEUE_ENTRY)&buffer[decryptedSize]);
        uint64_t queueEndUs = PltGetMicroseconds();

        // Track queue timing
        uint64_t queueTimeUs = queueEndUs - queueStartUs;
        totalQueueTimeUs += queueTimeUs;
        if (queueTimeUs > maxQueueTimeUs) {
            maxQueueTimeUs = queueTimeUs;
        }

        // Warn if queue operation is slow (over 500us - could indicate FEC reconstruction)
        if (queueTimeUs > 500) {
            Limelog("[NET_DIAG] Slow queue op: %llu us (FEC recovery?)\n", (unsigned long long)queueTimeUs);
        }

        // Network diagnostics: count packets and log periodically
        totalPacketsReceived++;
        diagIntervalPackets++;

        if (receivedDataFromPeer) {
            uint64_t nowMs = PltGetMillis();
            if (lastDiagTimeMs == 0) {
                lastDiagTimeMs = nowMs;
            }
            else if (nowMs - lastDiagTimeMs >= NET_DIAG_INTERVAL_MS) {
                uint64_t packetsPerSec = (diagIntervalPackets * 1000) / (nowMs - lastDiagTimeMs);

                // Calculate average processing times
                uint64_t avgDecryptUs = decryptCount > 0 ? totalDecryptTimeUs / decryptCount : 0;
                uint64_t avgQueueUs = diagIntervalPackets > 0 ? totalQueueTimeUs / diagIntervalPackets : 0;

                Limelog("[NET_DIAG] === Video Stream Stats ===\n");
                Limelog("[NET_DIAG] Packets: %llu total, %llu/sec, size=%d, maxGap=%llums\n",
                        (unsigned long long)totalPacketsReceived,
                        (unsigned long long)packetsPerSec,
                        StreamConfig.packetSize,
                        (unsigned long long)maxPacketGapMs);
                Limelog("[NET_DIAG] Timing: decrypt avg=%lluus max=%lluus, queue avg=%lluus max=%lluus\n",
                        (unsigned long long)avgDecryptUs,
                        (unsigned long long)maxDecryptTimeUs,
                        (unsigned long long)avgQueueUs,
                        (unsigned long long)maxQueueTimeUs);
                Limelog("[NET_DIAG] Socket buffer max=%llu bytes, seq discontinuities=%u\n",
                        (unsigned long long)maxSocketQueueBytes,
                        seqNumDiscontinuities);

                // Get RTP queue stats
                const RTP_VIDEO_STATS* stats = LiGetRTPVideoStats();
                Limelog("[NET_DIAG] RTP stats: video=%u fec=%u recovered=%u failed=%u oos=%u\n",
                        stats->packetCountVideo,
                        stats->packetCountFec,
                        stats->packetCountFecRecovered,
                        stats->packetCountFecFailed,
                        stats->packetCountOOS);
                Limelog("[NET_DIAG] ==============================\n");

                // Reset interval counters
                diagIntervalPackets = 0;
                maxPacketGapMs = 0;
                totalDecryptTimeUs = 0;
                totalQueueTimeUs = 0;
                maxDecryptTimeUs = 0;
                maxQueueTimeUs = 0;
                maxSocketQueueBytes = 0;
                decryptCount = 0;
                seqNumDiscontinuities = 0;
                lastDiagTimeMs = nowMs;
            }
        }
#else
        // Without diagnostics, just queue the packet directly
        queueStatus = RtpvAddPacket(&rtpQueue, packet, err, (PRTPV_QUEUE_ENTRY)&buffer[decryptedSize]);
#endif

        if (queueStatus == RTPF_RET_QUEUED) {
            // The queue owns the buffer
            buffer = NULL;
        }
    }

    if (buffer != NULL) {
        free(buffer);
    }

    if (encryptedBuffer != NULL) {
        free(encryptedBuffer);
    }
}

void notifyKeyFrameReceived(void) {
    // Remember that we got a full frame successfully
    receivedFullFrame = true;
}

// Decoder thread proc
static void VideoDecoderThreadProc(void* context) {
    while (!PltIsThreadInterrupted(&decoderThread)) {
        VIDEO_FRAME_HANDLE frameHandle;
        PDECODE_UNIT decodeUnit;

        if (!LiWaitForNextVideoFrame(&frameHandle, &decodeUnit)) {
            return;
        }

        LiCompleteVideoFrame(frameHandle, VideoCallbacks.submitDecodeUnit(decodeUnit));
    }
}

// Read the first frame of the video stream
int readFirstFrame(void) {
    // All that matters is that we close this socket.
    // This starts the flow of video on Gen 3 servers.

    closeSocket(firstFrameSocket);
    firstFrameSocket = INVALID_SOCKET;

    return 0;
}

// Terminate the video stream
void stopVideoStream(void) {
    if (!receivedDataFromPeer) {
        Limelog("No video traffic was ever received from the host!\n");
    }

    VideoCallbacks.stop();

    // Wake up client code that may be waiting on the decode unit queue
    stopVideoDepacketizer();

    PltInterruptThread(&udpPingThread);
    PltInterruptThread(&receiveThread);
    if ((VideoCallbacks.capabilities & (CAPABILITY_DIRECT_SUBMIT | CAPABILITY_PULL_RENDERER)) == 0) {
        PltInterruptThread(&decoderThread);
    }

    if (firstFrameSocket != INVALID_SOCKET) {
        shutdownTcpSocket(firstFrameSocket);
    }

    PltJoinThread(&udpPingThread);
    PltJoinThread(&receiveThread);
    if ((VideoCallbacks.capabilities & (CAPABILITY_DIRECT_SUBMIT | CAPABILITY_PULL_RENDERER)) == 0) {
        PltJoinThread(&decoderThread);
    }

    if (firstFrameSocket != INVALID_SOCKET) {
        closeSocket(firstFrameSocket);
        firstFrameSocket = INVALID_SOCKET;
    }
    if (rtpSocket != INVALID_SOCKET) {
        closeSocket(rtpSocket);
        rtpSocket = INVALID_SOCKET;
    }

    VideoCallbacks.cleanup();
}

// Start the video stream
int startVideoStream(void* rendererContext, int drFlags) {
    int err;

    firstFrameSocket = INVALID_SOCKET;

    // Log network configuration for diagnostics
    Limelog("[NET_DIAG] === Video Stream Configuration ===\n");
    Limelog("[NET_DIAG] Resolution: %dx%d @ %d fps\n", StreamConfig.width, StreamConfig.height, StreamConfig.fps);
    Limelog("[NET_DIAG] Packet size: %d bytes\n", StreamConfig.packetSize);
    Limelog("[NET_DIAG] Bitrate: %d kbps\n", StreamConfig.bitrate);
    Limelog("[NET_DIAG] RTP buffer: %d packets x %d bytes = %d bytes\n",
            RTP_RECV_PACKETS_BUFFERED,
            StreamConfig.packetSize + MAX_RTP_HEADER_SIZE,
            RTP_RECV_PACKETS_BUFFERED * (StreamConfig.packetSize + MAX_RTP_HEADER_SIZE));
    Limelog("[NET_DIAG] ==================================\n");

    // This must be called before the decoder thread starts submitting
    // decode units
    LC_ASSERT(NegotiatedVideoFormat != 0);
    err = VideoCallbacks.setup(NegotiatedVideoFormat, StreamConfig.width,
        StreamConfig.height, StreamConfig.fps, rendererContext, drFlags);
    if (err != 0) {
        return err;
    }

    rtpSocket = bindUdpSocket(RemoteAddr.ss_family, &LocalAddr, AddrLen,
                              RTP_RECV_PACKETS_BUFFERED * (StreamConfig.packetSize + MAX_RTP_HEADER_SIZE),
                              SOCK_QOS_TYPE_VIDEO);
    if (rtpSocket == INVALID_SOCKET) {
        VideoCallbacks.cleanup();
        return LastSocketError();
    }

    VideoCallbacks.start();

    err = PltCreateThread("VideoRecv", VideoReceiveThreadProc, NULL, &receiveThread);
    if (err != 0) {
        VideoCallbacks.stop();
        closeSocket(rtpSocket);
        VideoCallbacks.cleanup();
        return err;
    }

    if ((VideoCallbacks.capabilities & (CAPABILITY_DIRECT_SUBMIT | CAPABILITY_PULL_RENDERER)) == 0) {
        err = PltCreateThread("VideoDec", VideoDecoderThreadProc, NULL, &decoderThread);
        if (err != 0) {
            VideoCallbacks.stop();
            PltInterruptThread(&receiveThread);
            PltJoinThread(&receiveThread);
            closeSocket(rtpSocket);
            VideoCallbacks.cleanup();
            return err;
        }
    }

    if (AppVersionQuad[0] == 3) {
        // Connect this socket to open port 47998 for our ping thread
        firstFrameSocket = connectTcpSocket(&RemoteAddr, AddrLen,
                                            FIRST_FRAME_PORT, FIRST_FRAME_TIMEOUT_SEC);
        if (firstFrameSocket == INVALID_SOCKET) {
            VideoCallbacks.stop();
            stopVideoDepacketizer();
            PltInterruptThread(&receiveThread);
            if ((VideoCallbacks.capabilities & (CAPABILITY_DIRECT_SUBMIT | CAPABILITY_PULL_RENDERER)) == 0) {
                PltInterruptThread(&decoderThread);
            }
            PltJoinThread(&receiveThread);
            if ((VideoCallbacks.capabilities & (CAPABILITY_DIRECT_SUBMIT | CAPABILITY_PULL_RENDERER)) == 0) {
                PltJoinThread(&decoderThread);
            }
            closeSocket(rtpSocket);
            VideoCallbacks.cleanup();
            return LastSocketError();
        }
    }

    // Start pinging before reading the first frame so GFE knows where
    // to send UDP data
    err = PltCreateThread("VideoPing", VideoPingThreadProc, NULL, &udpPingThread);
    if (err != 0) {
        VideoCallbacks.stop();
        stopVideoDepacketizer();
        PltInterruptThread(&receiveThread);
        if ((VideoCallbacks.capabilities & (CAPABILITY_DIRECT_SUBMIT | CAPABILITY_PULL_RENDERER)) == 0) {
            PltInterruptThread(&decoderThread);
        }
        PltJoinThread(&receiveThread);
        if ((VideoCallbacks.capabilities & (CAPABILITY_DIRECT_SUBMIT | CAPABILITY_PULL_RENDERER)) == 0) {
            PltJoinThread(&decoderThread);
        }
        closeSocket(rtpSocket);
        if (firstFrameSocket != INVALID_SOCKET) {
            closeSocket(firstFrameSocket);
            firstFrameSocket = INVALID_SOCKET;
        }
        VideoCallbacks.cleanup();
        return err;
    }

    if (AppVersionQuad[0] == 3) {
        // Read the first frame to start the flow of video
        err = readFirstFrame();
        if (err != 0) {
            stopVideoStream();
            return err;
        }
    }

    return 0;
}

const RTP_VIDEO_STATS* LiGetRTPVideoStats(void) {
    return &rtpQueue.stats;
}
