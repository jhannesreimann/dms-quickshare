import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import Quickshell
import Quickshell.Io

PluginComponent {
    id: root

    layerNamespacePlugin: "quickshare"
    
    // Default properties and state
    property bool isEnabled: pluginData.isEnabled ?? true
    property bool isScanning: false
    property var mockDevices: []
    property var pendingTransfers: [] // Queue of incoming transfers waiting for accept/reject
    property bool daemonRunning: false

    // Control Center capability
    ccWidgetIcon: isEnabled ? "share" : "share"
    ccWidgetPrimaryText: "Quick Share"
    ccWidgetSecondaryText: isEnabled ? (isScanning ? "Scanning..." : (daemonRunning ? "Active" : "Daemon stopped")) : "Inactive"
    ccWidgetIsActive: isEnabled

    // Daemon background process
    Process {
        id: daemonProcess
        command: ["dms-quickshare-daemon"] // Expects the daemon to be in PATH
        running: false
        
        stdout: SplitParser {
            onRead: line => console.log("QuickShare Daemon:", line)
        }
        
        stderr: SplitParser {
            onRead: line => console.error("QuickShare Daemon Error:", line)
        }

        onExited: exitCode => {
            console.log("QuickShare Daemon exited with code:", exitCode);
            root.daemonRunning = false;
        }
        
        onStarted: {
            console.log("QuickShare Daemon started.");
            root.daemonRunning = true;
            // Initially set visibility based on settings
            Quickshell.execDetached(["dbus-send", "--session", "--type=method_call", "--dest=org.danklinux.QuickShare", "/org/danklinux/QuickShare", "org.danklinux.QuickShare.SetVisibility", "boolean:" + (root.isEnabled ? "true" : "false")])
        }
    }

    onCcWidgetToggled: {
        isEnabled = !isEnabled
        if (pluginService) {
            pluginService.savePluginData(pluginId, "isEnabled", isEnabled)
        }
        
        if (root.daemonRunning) {
            Quickshell.execDetached(["dbus-send", "--session", "--type=method_call", "--dest=org.danklinux.QuickShare", "/org/danklinux/QuickShare", "org.danklinux.QuickShare.SetVisibility", "boolean:" + (isEnabled ? "true" : "false")])
        }
    }

    // Set up D-Bus subscriptions when component is created
    Component.onCompleted: {
        // Start daemon if not running
        Quickshell.exec(["pgrep", "-f", "dms-quickshare-daemon"], function(out, err, code) {
            if (code !== 0) {
                console.log("Daemon not running. Starting it...");
                daemonProcess.running = true;
            } else {
                console.log("Daemon already running.");
                root.daemonRunning = true;
            }
        });

        if (DMSService) {
            // Subscription: Device found
            DMSService.dbusSubscribe(
                "session", 
                "org.danklinux.QuickShare", 
                "/org/danklinux/QuickShare", 
                "org.danklinux.QuickShare", 
                "DeviceDiscovered", 
                (response) => {
                    if (response && response.result) {
                        const id = response.result.arguments[0];
                        const name = response.result.arguments[1];
                        const ip = response.result.arguments[2];
                        
                        const exists = root.mockDevices.some(d => d.id === id);
                        if (!exists) {
                            let newDevices = root.mockDevices.slice();
                            newDevices.push({
                                id: id,
                                name: name,
                                ip: ip,
                                type: "phone"
                            });
                            root.mockDevices = newDevices;
                        }
                    }
                }
            );

            // Subscription: Incoming Transfer Request
            DMSService.dbusSubscribe(
                "session", 
                "org.danklinux.QuickShare", 
                "/org/danklinux/QuickShare", 
                "org.danklinux.QuickShare", 
                "TransferRequested", 
                (response) => {
                    if (response && response.result) {
                        const id = response.result.arguments[0];
                        const deviceName = response.result.arguments[1];
                        const pin = response.result.arguments[2];
                        
                        ToastService.showInfo("Quick Share", deviceName + " wants to send a file (PIN: " + pin + "). Open Quick Share to accept.");
                        
                        let newTransfers = root.pendingTransfers.slice();
                        newTransfers.push({
                            id: id,
                            deviceName: deviceName,
                            pin: pin
                        });
                        root.pendingTransfers = newTransfers;
                    }
                }
            );

            // Subscription: Transfer Progress (State updates)
            DMSService.dbusSubscribe(
                "session", 
                "org.danklinux.QuickShare", 
                "/org/danklinux/QuickShare", 
                "org.danklinux.QuickShare", 
                "TransferProgress", 
                (response) => {
                    if (response && response.result) {
                        const id = response.result.arguments[0];
                        const state = response.result.arguments[1];
                        
                        if (state === "Completed") {
                            ToastService.showInfo("Quick Share", "Transfer completed!");
                            root.pendingTransfers = root.pendingTransfers.filter(t => t.id !== id);
                        } else if (state === "Rejected" || state === "Cancelled" || state === "Failed") {
                            ToastService.showError("Quick Share", "Transfer " + state.toLowerCase());
                            root.pendingTransfers = root.pendingTransfers.filter(t => t.id !== id);
                        }
                    }
                }
            );
        }
    }

    Component.onDestruction: {
        // Stop daemon when plugin unloads if we started it
        if (daemonProcess.running) {
            daemonProcess.running = false;
        }
    }

    // Bar pills
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS

            DankIcon {
                name: root.pendingTransfers.length > 0 ? "downloading" : "share"
                size: root.iconSize
                color: root.pendingTransfers.length > 0 ? Theme.success : (root.isEnabled && root.daemonRunning ? Theme.primary : Theme.surfaceVariantText)
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.pendingTransfers.length > 0 ? "Incoming" : "Share"
                font.pixelSize: Theme.fontSizeSmall
                color: root.isEnabled && root.daemonRunning ? Theme.surfaceText : Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
                visible: root.isEnabled
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DankIcon {
                name: root.pendingTransfers.length > 0 ? "downloading" : "share"
                size: root.iconSize
                color: root.pendingTransfers.length > 0 ? Theme.success : (root.isEnabled && root.daemonRunning ? Theme.primary : Theme.surfaceVariantText)
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // Main Popout Widget
    popoutContent: Component {
        PopoutComponent {
            id: popoutColumn

            headerText: "Quick Share"
            detailsText: root.daemonRunning ? "Share with nearby devices" : "Daemon not running! Please install dms-quickshare-daemon."
            showCloseButton: true

            Item {
                width: parent.width
                implicitHeight: root.popoutHeight - popoutColumn.headerHeight - popoutColumn.detailsHeight - Theme.spacingXL

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingM

                    // --- INCOMING TRANSFERS SECTION ---
                    Column {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: root.pendingTransfers.length > 0

                        StyledText {
                            text: "Incoming Transfers"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                            color: Theme.success
                        }

                        Repeater {
                            model: root.pendingTransfers
                            
                            StyledRect {
                                width: parent.width
                                height: 80
                                radius: Theme.cornerRadius
                                color: Theme.surfaceContainerHighest
                                
                                Column {
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingS
                                    spacing: 4

                                    StyledText {
                                        text: modelData.deviceName + " is sending a file"
                                        font.pixelSize: Theme.fontSizeMedium
                                        color: Theme.surfaceText
                                    }
                                    
                                    StyledText {
                                        text: modelData.pin !== "" ? "PIN: " + modelData.pin : ""
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                        visible: modelData.pin !== ""
                                    }

                                    Row {
                                        spacing: Theme.spacingS
                                        
                                        StyledButton {
                                            text: "Accept"
                                            type: "primary"
                                            height: 30
                                            onClicked: {
                                                Quickshell.execDetached([
                                                    "dbus-send", "--session", "--type=method_call", 
                                                    "--dest=org.danklinux.QuickShare", 
                                                    "/org/danklinux/QuickShare", 
                                                    "org.danklinux.QuickShare.AcceptTransfer", 
                                                    "string:" + modelData.id
                                                ]);
                                            }
                                        }

                                        StyledButton {
                                            text: "Reject"
                                            type: "secondary"
                                            height: 30
                                            onClicked: {
                                                Quickshell.execDetached([
                                                    "dbus-send", "--session", "--type=method_call", 
                                                    "--dest=org.danklinux.QuickShare", 
                                                    "/org/danklinux/QuickShare", 
                                                    "org.danklinux.QuickShare.RejectTransfer", 
                                                    "string:" + modelData.id
                                                ]);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // --- OUTBOUND SECTION ---
                    Row {
                        width: parent.width
                        spacing: Theme.spacingM
                        opacity: root.daemonRunning ? 1.0 : 0.5
                        enabled: root.daemonRunning

                        StyledButton {
                            text: root.isScanning ? "Scanning..." : "Scan for Devices"
                            icon: "search"
                            width: (parent.width - Theme.spacingM) / 2
                            type: root.isScanning ? "secondary" : "primary"
                            onClicked: {
                                root.isScanning = true;
                                root.mockDevices = [];
                                
                                Quickshell.execDetached([
                                    "dbus-send", "--session", "--type=method_call", 
                                    "--dest=org.danklinux.QuickShare", "/org/danklinux/QuickShare", 
                                    "org.danklinux.QuickShare.StartDiscovery"
                                ]);

                                Timer {
                                    interval: 15000; running: true; repeat: false
                                    onTriggered: {
                                        root.isScanning = false;
                                        if (root.mockDevices.length === 0) {
                                            ToastService.showInfo("Quick Share", "No devices found nearby.")
                                        }
                                    }
                                }
                            }
                        }

                        StyledButton {
                            text: "Select File"
                            icon: "folder"
                            width: (parent.width - Theme.spacingM) / 2
                            type: "secondary"
                            onClicked: {
                                Quickshell.exec(["zenity", "--file-selection", "--multiple", "--title=Select files to send"], function(output, err, exitCode) {
                                    if (exitCode === 0 && output.trim() !== "") {
                                        const files = output.trim().split("|");
                                        root.pluginService.savePluginState(root.pluginId, "selectedFiles", files);
                                        ToastService.showInfo("Quick Share", files.length + " file(s) selected. Tap a device to send.");
                                    }
                                });
                            }
                        }
                    }

                    StyledText {
                        text: "Nearby Devices"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        visible: (root.mockDevices.length > 0 || root.isScanning) && root.daemonRunning
                    }

                    ListView {
                        width: parent.width
                        height: parent.height - 180
                        model: root.mockDevices
                        spacing: Theme.spacingS

                        delegate: StyledRect {
                            width: parent.width
                            height: 60
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainerHighest
                            
                            Row {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingM

                                DankIcon {
                                    name: modelData.type === "phone" ? "smartphone" : "tablet_mac"
                                    size: Theme.iconSizeLarge
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: modelData.name
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Item { Layout.fillWidth: true } // Spacer
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const selectedFiles = root.pluginService.loadPluginState(root.pluginId, "selectedFiles", []);
                                    if (!selectedFiles || selectedFiles.length === 0) {
                                        ToastService.showError("Quick Share", "Please select a file first using the 'Select File' button.");
                                        return;
                                    }
                                    
                                    ToastService.showInfo("Quick Share", "Sending " + selectedFiles.length + " file(s) to " + modelData.name + "...");
                                    
                                    let filesArray = "['" + selectedFiles.join("', '") + "']";
                                    let gdbusCmd = [
                                        "gdbus", "call", "--session", 
                                        "--dest", "org.danklinux.QuickShare", 
                                        "--object-path", "/org/danklinux/QuickShare", 
                                        "--method", "org.danklinux.QuickShare.SendFiles", 
                                        "'" + modelData.id + "'", 
                                        "'" + modelData.name + "'", 
                                        "'" + modelData.ip + "'", 
                                        filesArray
                                    ];
                                    
                                    Quickshell.execDetached(["bash", "-c", gdbusCmd.join(" ")]);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    popoutWidth: 400
    popoutHeight: 600
}
