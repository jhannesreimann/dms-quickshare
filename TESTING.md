# Testing DankQuickShare Locally

Because DankMaterialShell relies on specific Wayland compositors and Quickshell components, testing on a system without DMS requires isolating the components. 

Here is how you can test the **backend (Daemon)** and **frontend (QML)** independently when you switch to your target machine.

---

## 1. Testing the Rust Daemon (Backend)

The daemon is completely standalone and does not require DMS to be running. It only requires a working D-Bus session.

### Build and Run
```bash
cd daemon
cargo build --release
RUST_LOG=debug ./target/release/dms-quickshare-daemon
```
You should see output indicating that the D-Bus interface `org.danklinux.QuickShare` has successfully registered.

### Simulating QML (Testing D-Bus directly)
While the daemon is running, open a second terminal. You can use standard Linux tools (`gdbus` or `dbus-send`) to test the API without the QML UI:

**1. Turn Discoverability ON:**
```bash
dbus-send --session --type=method_call --dest=org.danklinux.QuickShare \
  /org/danklinux/QuickShare org.danklinux.QuickShare.SetVisibility boolean:true
```
*(Now try to find your PC from your Android Phone using Quick Share)*

**2. Start Scanning for Android Devices:**
```bash
dbus-send --session --type=method_call --dest=org.danklinux.QuickShare \
  /org/danklinux/QuickShare org.danklinux.QuickShare.StartDiscovery
```

**3. Monitor for incoming D-Bus signals (e.g. `DeviceDiscovered`):**
```bash
dbus-monitor "type='signal',interface='org.danklinux.QuickShare'"
```

---

## 2. Testing the QML UI (Frontend)

To test the QML UI, you need to be on a system with DankMaterialShell installed.

### Loading the Plugin
1. Create a symlink from your Git repository to the DMS plugins folder:
```bash
mkdir -p ~/.config/DankMaterialShell/plugins
ln -s /path/to/your/cloned/dms-quickshare ~/.config/DankMaterialShell/plugins/DankQuickShare
```
2. Restart DankMaterialShell or reload plugins:
```bash
dms ipc call plugins reload quickshare
```
*(Alternatively, open the DMS Settings UI, go to Plugins, click "Scan for Plugins", and toggle it on).*

### Debugging the UI
To see the `console.log` outputs from the QML (e.g., when buttons are pressed or D-Bus signals are received):
```bash
journalctl -f -t quickshell | grep -i quickshare
```
