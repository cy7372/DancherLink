#pragma once

#include <d3d11.h>
#include <dxgi1_6.h>

namespace GpuOpts {

// GPU vendor IDs
constexpr UINT VENDOR_NVIDIA = 0x10DE;
constexpr UINT VENDOR_AMD = 0x1002;
constexpr UINT VENDOR_INTEL = 0x8086;

// HAGS (Hardware-accelerated GPU Scheduling) detection result
struct HagsInfo {
    bool enabled;
    bool detected;
};

// Detect HAGS status for the given adapter
HagsInfo detectHags(LUID adapterLuid);

// Set GPU process scheduling priority
// Returns true if successful
bool setGpuProcessPriority(bool hagsEnabled, UINT vendorId);

// Set GPU thread priority via IDXGIDevice
// Returns true if successful
bool setGpuThreadPriority(ID3D11Device* device, int priority = 7);

// Apply all GPU optimizations for streaming
// Call this after device creation succeeds
void applyGpuOptimizations(ID3D11Device* device, LUID adapterLuid, UINT vendorId);

} // namespace GpuOpts
