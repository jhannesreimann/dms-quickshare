# AI Context for DankQuickShare

This document serves as a handover for future AI coding sessions (e.g. via Windsurf/Cascade) when continuing work on this repository on a new machine.

## Project State
We are building a standalone third-party plugin for DankMaterialShell (DMS) that implements Android's Quick Share (Nearby Share) protocol.

### Architecture
1. **Frontend (`DankQuickShare.qml` & `Settings.qml`)**: 
   - A standard DMS plugin widget written in QML.
   - Communicates with the background service entirely over D-Bus (`org.danklinux.QuickShare`).
   - Automatically attempts to start the Rust daemon via `Quickshell.Io.Process`.
2. **Backend (`daemon/`)**:
   - A headless Rust daemon wrapping the [rquickshare](https://github.com/Martichou/rquickshare) library (`rqs_lib`).
   - Exposes D-Bus methods (`StartDiscovery`, `SetVisibility`, `SendFiles`, `AcceptTransfer`, `RejectTransfer`).
   - Emits D-Bus signals (`DeviceDiscovered`, `TransferRequested`, `TransferProgress`).

## What Works So Far
- **D-Bus Skeleton:** The QML frontend successfully subscribes to signals and triggers methods. The Rust daemon successfully registers the D-Bus interface.
- **Discovery:** Triggering a scan from QML invokes `rqs_lib` discovery, which emits a signal back to QML to populate the UI list.
- **UI Logic:** Selecting files (via `zenity`) and displaying pending transfers.
- **File Reception (Rust):** The daemon explicitly tells `rqs_lib` to save files to the user's `~/Downloads` directory (using the `dirs` crate).
- **Transfer Progress (QML + Rust):** The daemon extracts `ack_bytes` and `total_bytes` from the `rqs_lib` internal state and emits them over D-Bus. The QML frontend listens for `TransferProgress` and renders an active progress bar with megabyte counts.

## What Needs To Be Implemented Next
1. **Bluetooth LE (BLE) / mDNS Dependencies:**
   - `rquickshare` relies on `bluez` and Avahi/mDNS to discover devices. This requires proper permissions and background services running on the Linux host. We need to ensure the daemon logs explicitly state if these dependencies fail.
2. **Testing in real-world:**
   - On the new system, compile the daemon and verify that Android actually sees the PC and vice-versa. Sometimes firewall rules drop the mDNS multicasts.

## Setup Instructions for AI
1. Read `plugin.json` and `DankQuickShare.qml` to understand the QML structure.
2. Read `daemon/src/main.rs` to understand the D-Bus routing.
3. Check `TESTING.md` for local debugging steps.
