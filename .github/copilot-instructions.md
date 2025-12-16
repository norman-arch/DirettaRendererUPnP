# Diretta UPnP Renderer - AI Coding Agent Instructions

## Project Overview

This is a **native UPnP/DLNA audio renderer** that streams high-resolution audio using the proprietary **Diretta protocol** for bit-perfect playback. The renderer decodes audio files (FLAC, WAV, DSD) via FFmpeg and sends PCM/DSD samples to a Diretta Target endpoint over Ethernet, bypassing the OS audio stack entirely.

**Critical**: The Diretta Host SDK is proprietary software for personal use only. Commercial use is prohibited.

## Architecture & Signal Flow

```
UPnP Control Point → DirettaRenderer (UPnP + FFmpeg decode) → Diretta Target → DAC
                     [3 components: UPnPDevice, AudioEngine, DirettaOutput]
```

### Core Components

1. **UPnPDevice** ([src/UPnPDevice.hpp](src/UPnPDevice.hpp)): Handles UPnP/DLNA protocol via libupnp
   - SSDP discovery, SOAP actions (AVTransport, RenderingControl)
   - Event notifications to subscribers
   - Thread-safe state management with `std::mutex`

2. **AudioEngine** ([src/AudioEngine.h](src/AudioEngine.h)): FFmpeg-based audio decoder
   - Decodes FLAC/ALAC/WAV/DSD files from HTTP URIs
   - Format detection with `TrackInfo` struct (sampleRate, bitDepth, channels, isDSD)
   - Sample buffering and format conversion

3. **DirettaOutput** ([src/DirettaOutput.h](src/DirettaOutput.h)): Diretta SDK integration
   - Uses `Diretta::SyncBuffer` for gapless playback
   - Automatic target discovery and format negotiation
   - Adaptive packet sizing based on sample rate (1-3k for CD, ~16k for DSD)

4. **DirettaRenderer** ([src/DirettaRenderer.h](src/DirettaRenderer.h)): Orchestrator
   - Manages 4 threads: audio, UPnP, SSDP, position tracking
   - Coordinates state between UPnP commands and audio playback
   - Implements gapless playback via SetNextURI queuing

## Critical Threading Model

**4 concurrent threads** communicate via atomic flags and mutexes:

- **audioThreadFunc()**: Pulls decoded samples from AudioEngine, pushes to DirettaOutput
  - **Timing-critical**: Uses `sleep_until()` for microsecond-precise pacing based on sample rate
  - Example: At 44.1kHz, sleeps exactly 1/44100 seconds per sample
- **upnpThreadFunc()**: Handles UPnP control requests
- **ssdpThreadFunc()**: Broadcasts device presence
- **positionThreadFunc()**: Updates playback position for UPnP eventing

**Thread safety pattern**: All state modifications use `std::lock_guard<std::mutex>` (see [UPnPDevice.cpp](src/UPnPDevice.cpp#L69))

## Build System Specifics

### Makefile Architecture Auto-Detection ([Makefile](Makefile))

The build system auto-detects CPU capabilities and selects optimal Diretta SDK libraries:

- **x64**: Detects AVX2/AVX512 support → selects v2/v3/v4/zen4 variants
- **aarch64**: Kernel version-based selection (k16 variant for kernel ≥4.16)
- **Library naming**: `libDirettaHost_x64-linux-15v3.a`, `libACQUA_x64-linux-15v3.a`

**Manual override**:
```bash
make VARIANT=15v4        # Force AVX512
make ARCH_NAME=aarch64-linux-15  # Cross-compile
make NOLOG=1             # Production build (no debug logs)
```

**SDK location**: Auto-detected from `~/DirettaHostSDK_147/`, `./DirettaHostSDK_147/`, etc.

### Build Commands

```bash
make           # Auto-detect and build
make clean     # Clean build artifacts
make install   # Copy binary to bin/
```

## Coding Conventions

### Error Handling Pattern

- **Console output**: Use `std::cout` for user-facing messages, `std::cerr` for errors
- **Debug logging**: All debug logs use `DEBUG_LOG(x)` macro (controlled by global `g_verbose` flag)
  - Defined in [DirettaRenderer.cpp](src/DirettaRenderer.cpp#L27): `#define DEBUG_LOG(x) if (g_verbose) { std::cout << x << std::endl; }`
  - **Never use raw `std::cout` for debug info** - always use `DEBUG_LOG()`

### Startup Sequence

Critical startup order ([DirettaRenderer.cpp](src/DirettaRenderer.cpp#L93)):

1. **Verify Diretta Target availability FIRST** (via `verifyTargetAvailable()`)
2. Configure MTU (default: 16128 bytes for jumbo frames)
3. Create UPnPDevice and set callbacks
4. Create AudioEngine
5. Start all 4 threads

**Rationale**: If no Diretta Target exists, renderer should fail immediately, not accept UPnP connections

### Configuration

Runtime config via command-line args ([main.cpp](src/main.cpp#L49)):

- `--port <n>`: UPnP control port (default: 4005)
- `--buffer <f>`: Audio buffer size in seconds (default: 2.0, range: 1.0-10.0)
- `--target <n>`: Diretta Target index (-1 = interactive selection)
- `--no-gapless`: Disable gapless playback
- `--verbose`: Enable debug logging (`g_verbose = true`)

### Format Detection & Conversion

**DSD handling** ([AudioFormat](src/DirettaOutput.h#L14)):
- Distinguish between DSF (LSB-first) and DFF (MSB-first)
- `isDSD` flag + `dsdFormat` enum

**Compressed vs. uncompressed** ([TrackInfo](src/AudioEngine.h#L28)):
- `isCompressed = true`: FLAC/ALAC (requires FFmpeg decoding)
- `isCompressed = false`: WAV/AIFF (copy raw samples)

## Network Optimization

**Adaptive packet sizing** ([DirettaRenderer.h](src/DirettaRenderer.h#L54)):
- MTU: `m_networkMTU = 16128` (hardcoded)
- CD-quality (44.1kHz): ~1-3k packets (prevents fragmentation)
- DSD512+: ~16k packets (maximizes throughput)

**Jumbo frames recommended**: Configure switch/NICs for MTU=9000

## Testing & Debugging

### List Diretta Targets

```bash
sudo ./bin/DirettaRendererUPnP --list-targets
```

Shows available Diretta Target endpoints on network.

### Verbose Mode

```bash
sudo ./bin/DirettaRendererUPnP --verbose
```

Enables all `DEBUG_LOG()` statements for troubleshooting.

### Common Issues

1. **"No Diretta Target available"**: Ensure target device is powered on and on same network
2. **Fragmentation warnings**: Reduce MTU or enable jumbo frames on network gear
3. **Timing drift**: Check `audioThreadFunc()` sleep precision
   - **RT kernel recommended**: Install `kernel-rt` (Fedora) or `linux-rt` (Ubuntu) for microsecond-accurate timing
   - Configure CPU isolation: `isolcpus=2,3` in kernel cmdline to dedicate cores to audio thread
   - Set thread priority: Use `chrt -f 80` for real-time scheduling (already handled in code if running as root)

## File Organization

```
src/
  main.cpp           - Entry point, CLI parsing
  DirettaRenderer.*  - Main orchestrator (4 threads)
  UPnPDevice.*       - UPnP/DLNA protocol handling
  AudioEngine.*      - FFmpeg audio decoding
  DirettaOutput.*    - Diretta SDK integration
  ProtocolInfoBuilder.h - UPnP format capability builder
docs/
  CONFIGURATION.md   - Runtime configuration guide
  TROUBLESHOOTING.md - Common issues
systemd/             - System service integration
```

## External Dependencies

- **libupnp**: UPnP device stack
- **FFmpeg**: Audio decoding (libavformat, libavcodec, libswresample)
- **Diretta Host SDK**: Proprietary audio streaming (version 147)
- **pthread**: Threading primitives

## Development Workflow

1. **Make code changes** in `src/`
2. **Build**: `make clean && make`
3. **Test**: `sudo ./bin/DirettaRendererUPnP --verbose --target 0`
4. **Check errors**: Look for mutex deadlocks, FFmpeg decode failures, Diretta connection issues
5. **Systemd install** (optional): `cd systemd && sudo ./install-systemd.sh`

## Project-Specific Patterns

### UUID Generation

UUIDs are **hostname-based** for stability across restarts ([DirettaRenderer.cpp](src/DirettaRenderer.cpp#L30)):
```cpp
std::hash<std::string> hasher;
size_t hash = hasher(std::string(hostname));
return "uuid:diretta-renderer-" + std::hex(hash);
```

This ensures UPnP control points recognize the renderer as the same device after reboot.

### Gapless Implementation

- **SetNextURI**: Queues `m_nextURI` and `m_nextMetadata`
- **handleEOF()**: Automatically loads next track without stopping Diretta output
- **SyncBuffer**: Diretta SDK component that handles seamless format transitions

### State Synchronization

All UPnP state changes (Play/Stop/Pause) propagate through:
1. UPnP callback → DirettaRenderer method
2. Update internal state with mutex lock
3. Call AudioEngine/DirettaOutput methods
4. Notify UPnP subscribers via `notifyStateChange()`

## When Modifying Code

- **Threading**: Always use mutexes for shared state; avoid race conditions
- **Timing**: Preserve microsecond-precise pacing in `audioThreadFunc()`
- **Logging**: Use `DEBUG_LOG()` exclusively for debug output (never raw `std::cout`)
- **SDK**: Never expose Diretta SDK internals publicly (license restriction)
- **Format changes**: Update both `AudioFormat` struct and UPnP `ProtocolInfo` builder
