#pragma once

#include "../../decoder.h"
#include "../renderer.h"

#include <QQueue>
#include <QMutex>
#include <QWaitCondition>
#include <memory>
#include <deque>

class IVsyncSource {
public:
    virtual ~IVsyncSource() {}
    virtual bool initialize(SDL_Window* window, int displayFps) = 0;

    // Asynchronous sources produce callbacks on their own, while synchronous
    // sources require calls to waitForVsync().
    virtual bool isAsync() = 0;

    virtual void waitForVsync() {
        // Synchronous sources must implement waitForVsync()!
        SDL_assert(false);
    }
};

struct AVFrameDeleter {
    void operator()(AVFrame* frame) {
        av_frame_free(&frame);
    }
};

using ScopedAVFrame = std::unique_ptr<AVFrame, AVFrameDeleter>;

class Pacer
{
public:
    Pacer(IFFmpegRenderer* renderer, PVIDEO_STATS videoStats);

    ~Pacer();

    // Takes ownership of the frame
    void submitFrame(AVFrame* frame);

    bool initialize(SDL_Window* window, int maxVideoFps, bool enablePacing);

    void signalVsync();

    void renderOnMainThread();

private:
    static int vsyncThread(void* context);

    static int renderThread(void* context);

    void handleVsync(int timeUntilNextVsyncMillis);

    void enqueueFrameForRenderingAndUnlock(ScopedAVFrame frame);

    void renderFrame(ScopedAVFrame frame);

    // Returns the dropped frame (if any) so it can be freed outside the lock
    ScopedAVFrame dropFrameForEnqueue(std::deque<ScopedAVFrame>& queue);

    // QQueue doesn't support move-only types like unique_ptr in all Qt versions,
    // but std::deque does.
    std::deque<ScopedAVFrame> m_RenderQueue;
    std::deque<ScopedAVFrame> m_PacingQueue;
    QQueue<int> m_PacingQueueHistory;
    QQueue<int> m_RenderQueueHistory;
    QMutex m_FrameQueueLock;
    QWaitCondition m_RenderQueueNotEmpty;
    QWaitCondition m_PacingQueueNotEmpty;
    QWaitCondition m_VsyncSignalled;
    SDL_Thread* m_RenderThread;
    SDL_Thread* m_VsyncThread;
    bool m_Stopping;

    IVsyncSource* m_VsyncSource;
    IFFmpegRenderer* m_VsyncRenderer;
    int m_MaxVideoFps;
    int m_DisplayFps;
    PVIDEO_STATS m_VideoStats;
    int m_RendererAttributes;
};
