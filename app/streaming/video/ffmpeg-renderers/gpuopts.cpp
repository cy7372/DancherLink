#include "gpuopts.h"

#include <SDL_log.h>
#include <windows.h>
#include <d3dkmthk.h>

// NT_SUCCESS macro for user mode
#ifndef NT_SUCCESS
#define NT_SUCCESS(Status) (((NTSTATUS)(Status)) >= 0)
#endif

namespace GpuOpts {

// D3DKMT function typedefs for dynamic loading
typedef NTSTATUS(WINAPI* PD3DKMTOpenAdapterFromLuid)(D3DKMT_OPENADAPTERFROMLUID*);
typedef NTSTATUS(WINAPI* PD3DKMTQueryAdapterInfo)(D3DKMT_QUERYADAPTERINFO*);
typedef NTSTATUS(WINAPI* PD3DKMTCloseAdapter)(const D3DKMT_CLOSEADAPTER*);
typedef NTSTATUS(WINAPI* PD3DKMTSetProcessSchedulingPriorityClass)(HANDLE, D3DKMT_SCHEDULINGPRIORITYCLASS);

HagsInfo detectHags(LUID adapterLuid)
{
    HagsInfo result = { false, false };

    HMODULE gdi32 = GetModuleHandleW(L"GDI32");
    if (!gdi32) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "[GpuOpts] Failed to get GDI32 module handle");
        return result;
    }

    auto d3dkmtOpenAdapter = (PD3DKMTOpenAdapterFromLuid)GetProcAddress(gdi32, "D3DKMTOpenAdapterFromLuid");
    auto d3dkmtQueryAdapterInfo = (PD3DKMTQueryAdapterInfo)GetProcAddress(gdi32, "D3DKMTQueryAdapterInfo");
    auto d3dkmtCloseAdapter = (PD3DKMTCloseAdapter)GetProcAddress(gdi32, "D3DKMTCloseAdapter");

    if (!d3dkmtOpenAdapter || !d3dkmtQueryAdapterInfo || !d3dkmtCloseAdapter) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "[GpuOpts] D3DKMT functions not available (older Windows version)");
        return result;
    }

    D3DKMT_OPENADAPTERFROMLUID openAdapter = { adapterLuid };
    NTSTATUS status = d3dkmtOpenAdapter(&openAdapter);
    if (!NT_SUCCESS(status)) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "[GpuOpts] D3DKMTOpenAdapterFromLuid failed: 0x%08X", status);
        return result;
    }

    D3DKMT_WDDM_2_7_CAPS wddmCaps = {};
    D3DKMT_QUERYADAPTERINFO queryInfo = {};
    queryInfo.hAdapter = openAdapter.hAdapter;
    queryInfo.Type = KMTQAITYPE_WDDM_2_7_CAPS;
    queryInfo.pPrivateDriverData = &wddmCaps;
    queryInfo.PrivateDriverDataSize = sizeof(wddmCaps);

    status = d3dkmtQueryAdapterInfo(&queryInfo);

    D3DKMT_CLOSEADAPTER closeAdapter = { openAdapter.hAdapter };
    d3dkmtCloseAdapter(&closeAdapter);

    if (NT_SUCCESS(status)) {
        result.detected = true;
        result.enabled = wddmCaps.HwSchEnabled != 0;
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "[GpuOpts] HAGS detected: %s", result.enabled ? "enabled" : "disabled");
    } else {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "[GpuOpts] KMTQAITYPE_WDDM_2_7_CAPS query failed: 0x%08X (driver may not support HAGS)", status);
    }

    return result;
}

bool setGpuProcessPriority(bool hagsEnabled, UINT vendorId)
{
    HMODULE gdi32 = GetModuleHandleW(L"GDI32");
    if (!gdi32) {
        return false;
    }

    auto d3dkmtSetPriority = (PD3DKMTSetProcessSchedulingPriorityClass)GetProcAddress(
        gdi32, "D3DKMTSetProcessSchedulingPriorityClass");
    if (!d3dkmtSetPriority) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "[GpuOpts] D3DKMTSetProcessSchedulingPriorityClass not available");
        return false;
    }

    // Default to realtime priority for best GPU scheduling
    D3DKMT_SCHEDULINGPRIORITYCLASS priority = D3DKMT_SCHEDULINGPRIORITYCLASS_REALTIME;

    // NVIDIA driver bug workaround: HAGS + realtime can cause encoding freezes or driver crashes
    // See: https://github.com/LizardByte/Sunshine/issues/891
    if (vendorId == VENDOR_NVIDIA && hagsEnabled) {
        priority = D3DKMT_SCHEDULINGPRIORITYCLASS_HIGH;
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "[GpuOpts] Using HIGH priority for NVIDIA + HAGS (realtime may cause issues)");
    }

    NTSTATUS status = d3dkmtSetPriority(GetCurrentProcess(), priority);
    if (!NT_SUCCESS(status)) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "[GpuOpts] D3DKMTSetProcessSchedulingPriorityClass failed: 0x%08X "
                    "(may need admin privileges)", status);
        return false;
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "[GpuOpts] GPU process priority set to %s",
                priority == D3DKMT_SCHEDULINGPRIORITYCLASS_REALTIME ? "REALTIME" : "HIGH");
    return true;
}

bool setGpuThreadPriority(ID3D11Device* device, int priority)
{
    if (!device) {
        return false;
    }

    IDXGIDevice* dxgiDevice = nullptr;
    HRESULT hr = device->QueryInterface(__uuidof(IDXGIDevice), (void**)&dxgiDevice);
    if (FAILED(hr)) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "[GpuOpts] QueryInterface(IDXGIDevice) failed: 0x%08X", hr);
        return false;
    }

    hr = dxgiDevice->SetGPUThreadPriority(priority);
    dxgiDevice->Release();

    if (FAILED(hr)) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "[GpuOpts] SetGPUThreadPriority(%d) failed: 0x%08X", priority, hr);
        return false;
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "[GpuOpts] GPU thread priority set to %d", priority);
    return true;
}

void applyGpuOptimizations(ID3D11Device* device, LUID adapterLuid, UINT vendorId)
{
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "[GpuOpts] Applying GPU optimizations for vendor 0x%04X", vendorId);

    // Detect Intel Lakefield (ThinkPad X1 Fold Gen 1) via PROCESSOR_IDENTIFIER environment variable
    bool isIntelLakefield = false;
    wchar_t processorId[256] = {0};
    DWORD size = sizeof(processorId);
    if (GetEnvironmentVariableW(L"PROCESSOR_IDENTIFIER", processorId, size) > 0) {
        // Case-insensitive substring search
        if (_wcsicmp(processorId, L"Lakefield") != 0 && wcsstr(processorId, L"Lakefield") != NULL) {
            isIntelLakefield = true;
        }
        if (_wcsicmp(processorId, L"i5-L16G7") != 0 && wcsstr(processorId, L"i5-L16G7") != NULL) {
            isIntelLakefield = true;
        }
    }

    bool lowLatencyMode = isIntelLakefield;

    // Detect HAGS status
    HagsInfo hags = detectHags(adapterLuid);

    // Set GPU process scheduling priority
    setGpuProcessPriority(hags.enabled, vendorId);

    // Set GPU thread priority (higher = better for streaming)
    // For X1 Fold / low latency mode, use maximum priority (7)
    // For standard mode, also use 7 for best performance
    int threadPriority = 7;

    // Intel Gen9 GPU specific optimization (X1 Fold uses Gen9)
    if (vendorId == VENDOR_INTEL && lowLatencyMode) {
        // On Intel iGPUs, higher thread priority helps reduce frame pacing issues
        threadPriority = 7;  // Maximum priority
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "[GpuOpts] Intel GPU detected (X1 Fold mode): using maximum thread priority");
    }

    setGpuThreadPriority(device, threadPriority);

    if (isIntelLakefield) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "[GpuOpts] ThinkPad X1 Fold detected: applying Intel Lakefield optimizations");
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "[GpuOpts] GPU optimization complete (HAGS: %s)",
                hags.detected ? (hags.enabled ? "enabled" : "disabled") : "unknown");
}

} // namespace GpuOpts
