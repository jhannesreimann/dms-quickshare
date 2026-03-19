import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import qs.Modals.FileBrowser
import Quickshell
import Quickshell.Io
import "./services"
import "./components"

PluginComponent {
    id: root

    layerNamespacePlugin: "quickshare"
    
    // Default properties and state
    property bool isEnabled: pluginData.isEnabled ?? true
    property bool autoAccept: pluginData.autoAccept ?? false

    // State lists. Now using ListModel for better performance
    property ListModel mockDevicesModel: ListModel {}
    property ListModel pendingTransfersModel: ListModel {}
    property ListModel activeTransfersModel: ListModel {}
    
    // Control Center capability
    ccWidgetIcon: isEnabled ? "share" : "share"
    ccWidgetPrimaryText: "Quick Share"
    ccWidgetSecondaryText: isEnabled ? (QuickShareService.isScanning ? "Scanning..." : (QuickShareService.available ? "Active" : "Daemon stopped")) : "Inactive"
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
            QuickShareService.available = false;
        }
        
        onStarted: {
            console.log("QuickShare Daemon started.");
            QuickShareService.available = true;
            // Initially set visibility based on settings
            QuickShareService.setVisibility(root.isEnabled);
        }
    }

    onCcWidgetToggled: {
        isEnabled = !isEnabled
        if (pluginService) {
            pluginService.savePluginData(pluginId, "isEnabled", isEnabled)
        }
        QuickShareService.setVisibility(isEnabled);
    }

    // Set up D-Bus subscriptions when component is created
    Component.onCompleted: {
        // Start daemon if not running
        QuickShareService.checkDaemon((isRunning) => {
            if (!isRunning) {
                console.log("Daemon not running. Starting it...");
                daemonProcess.running = true;
            }
        });
    }
    
    Connections {
        target: QuickShareService
        
        function onDeviceDiscovered(id, name, ip) {
            let exists = false;
            for (let i = 0; i < root.mockDevicesModel.count; ++i) {
                if (root.mockDevicesModel.get(i).id === id) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                root.mockDevicesModel.append({
                    id: id,
                    name: name,
                    ip: ip,
                    type: "phone"
                });
            }
        }
        
        function onTransferRequested(id, deviceName, pin) {
            const autoAcceptEnabled = root.pluginData.autoAccept ?? root.autoAccept;
            
            if (autoAcceptEnabled) {
                ToastService.showInfo("Quick Share", "Auto-accepting transfer from " + deviceName);
                QuickShareService.acceptTransfer(id);
                return;
            }
            
            let notifyCmd = [
                "notify-send", 
                "-a", "Quick Share",
                "-i", "document-send",
                "--action=accept=Accept",
                "--action=reject=Reject",
                "--wait", 
                "Incoming File", 
                `${deviceName} wants to send you a file (PIN: ${pin}).`
            ];

            Quickshell.exec(notifyCmd, function(out, err, code) {
                if (code === 0 && out.trim() === "accept") {
                    QuickShareService.acceptTransfer(id);
                    removePendingTransfer(id);
                } else if (code === 0 && out.trim() === "reject") {
                    QuickShareService.rejectTransfer(id);
                    removePendingTransfer(id);
                }
            });
            
            root.pendingTransfersModel.append({
                id: id,
                deviceName: deviceName,
                pin: pin
            });
        }
        
        function onTransferProgress(id, state, bytesAck, bytesTotal) {
            if (state === "ReceivingFiles" || state === "SendingFiles") {
                let existingIdx = -1;
                for (let i = 0; i < root.activeTransfersModel.count; ++i) {
                    if (root.activeTransfersModel.get(i).id === id) {
                        existingIdx = i;
                        break;
                    }
                }
                
                let progress = bytesTotal > 0 ? (bytesAck / bytesTotal) : 0;
                let bytesStr = Math.round(bytesAck / 1024 / 1024) + " / " + Math.round(bytesTotal / 1024 / 1024) + " MB";
                
                if (existingIdx !== -1) {
                    root.activeTransfersModel.setProperty(existingIdx, "progress", progress);
                    root.activeTransfersModel.setProperty(existingIdx, "state", state);
                    root.activeTransfersModel.setProperty(existingIdx, "bytesStr", bytesStr);
                } else {
                    root.activeTransfersModel.append({
                        id: id,
                        state: state,
                        progress: progress,
                        bytesStr: "Starting..."
                    });
                }
            }
            
            if (state === "Finished") {
                ToastService.showInfo("Quick Share", "Transfer completed successfully!");
                removePendingTransfer(id);
                removeActiveTransfer(id);
            } else if (state === "Rejected" || state === "Cancelled" || state === "Disconnected") {
                removePendingTransfer(id);
                removeActiveTransfer(id);
            }
        }
    }

    function removePendingTransfer(id) {
        for (let i = 0; i < root.pendingTransfersModel.count; ++i) {
            if (root.pendingTransfersModel.get(i).id === id) {
                root.pendingTransfersModel.remove(i);
                break;
            }
        }
    }
    
    function removeActiveTransfer(id) {
        for (let i = 0; i < root.activeTransfersModel.count; ++i) {
            if (root.activeTransfersModel.get(i).id === id) {
                root.activeTransfersModel.remove(i);
                break;
            }
        }
    }

    Component.onDestruction: {
        if (daemonProcess.running) {
            daemonProcess.running = false;
        }
    }

    // DropArea for full-screen dragging
    DropArea {
        anchors.fill: parent
        onDropped: (drop) => {
            if (drop.hasUrls) {
                const files = drop.urls.map(url => url.toString().replace("file://", ""));
                if (files.length > 0) {
                    root.pluginService.savePluginState(root.pluginId, "selectedFiles", files);
                    ToastService.showInfo("Quick Share", files.length + " file(s) dropped. Tap a device to send.");
                    drop.accept();
                    
                    if (!QuickShareService.isScanning) {
                        root.mockDevicesModel.clear();
                        QuickShareService.startDiscovery();
                    }
                }
            }
        }
    }

    // Bar pills
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS

            DankIcon {
                name: (root.pendingTransfersModel.count > 0 || root.activeTransfersModel.count > 0) ? "downloading" : "share"
                size: root.iconSize
                color: (root.pendingTransfersModel.count > 0 || root.activeTransfersModel.count > 0) ? Theme.success : (root.isEnabled && QuickShareService.available ? Theme.primary : Theme.surfaceVariantText)
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.activeTransfersModel.count > 0 ? "Transferring" : (root.pendingTransfersModel.count > 0 ? "Incoming" : "Share")
                font.pixelSize: Theme.fontSizeSmall
                color: root.isEnabled && QuickShareService.available ? Theme.surfaceText : Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
                visible: root.isEnabled
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DankIcon {
                name: (root.pendingTransfersModel.count > 0 || root.activeTransfersModel.count > 0) ? "downloading" : "share"
                size: root.iconSize
                color: (root.pendingTransfersModel.count > 0 || root.activeTransfersModel.count > 0) ? Theme.success : (root.isEnabled && QuickShareService.available ? Theme.primary : Theme.surfaceVariantText)
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    FileBrowserSurfaceModal {
        id: fileBrowser

        browserTitle: "Select File to Send"
        browserIcon: "upload_file"
        browserType: "generic"
        showHiddenFiles: false
        fileExtensions: ["*"]
        parentPopout: popoutColumn

        onFileSelected: path => {
            const files = [path];
            root.pluginService.savePluginState(root.pluginId, "selectedFiles", files);
            ToastService.showInfo("Quick Share", "1 file selected. Tap a device to send.");
        }
    }

    // Main Popout Widget
    popoutContent: Component {
        PopoutComponent {
            id: popoutColumn

            headerText: "Quick Share"
            detailsText: QuickShareService.available ? "Share with nearby devices (Drag & Drop files here)" : "Daemon not running! Please install dms-quickshare-daemon."
            showCloseButton: true

            Item {
                width: parent.width
                implicitHeight: root.popoutHeight - popoutColumn.headerHeight - popoutColumn.detailsHeight - Theme.spacingXL

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingM

                    // --- ACTIVE TRANSFERS SECTION ---
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingS
                        visible: root.activeTransfersModel.count > 0

                        StyledText {
                            text: "Active Transfers"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                            color: Theme.primary
                        }

                        Repeater {
                            model: root.activeTransfersModel
                            delegate: TransferCard {
                                state: model.state
                                progress: model.progress
                                bytesStr: model.bytesStr
                            }
                        }
                    }

                    // --- INCOMING TRANSFERS SECTION ---
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingS
                        visible: root.pendingTransfersModel.count > 0

                        StyledText {
                            text: "Incoming Requests"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                            color: Theme.success
                        }

                        Repeater {
                            model: root.pendingTransfersModel
                            delegate: IncomingRequestCard {
                                transferId: model.id
                                deviceName: model.deviceName
                                pin: model.pin
                                onRequestHandled: (tId) => {
                                    root.removePendingTransfer(tId);
                                }
                            }
                        }
                    }

                    // --- OUTBOUND SECTION ---
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingM
                        opacity: QuickShareService.available ? 1.0 : 0.5
                        enabled: QuickShareService.available

                        StyledButton {
                            text: QuickShareService.isScanning ? "Scanning..." : "Scan for Devices"
                            icon: "search"
                            Layout.fillWidth: true
                            type: QuickShareService.isScanning ? "secondary" : "primary"
                            onClicked: {
                                root.mockDevicesModel.clear();
                                QuickShareService.startDiscovery();
                            }
                        }

                        StyledButton {
                            text: "Select File"
                            icon: "folder"
                            Layout.fillWidth: true
                            type: "secondary"
                            onClicked: {
                                fileBrowser.open()
                            }
                        }
                    }

                    StyledText {
                        text: "Nearby Devices"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        visible: (root.mockDevicesModel.count > 0 || QuickShareService.isScanning) && QuickShareService.available
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true // Let QML handle the height automatically now
                        model: root.mockDevicesModel
                        spacing: Theme.spacingS
                        clip: true

                        delegate: DeviceCard {
                            deviceId: model.id
                            deviceName: model.name
                            ip: model.ip
                            deviceType: model.type
                            
                            onClicked: {
                                const selectedFiles = root.pluginService.loadPluginState(root.pluginId, "selectedFiles", []);
                                if (!selectedFiles || selectedFiles.length === 0) {
                                    ToastService.showError("Quick Share", "Please select a file first using the 'Select File' button or drag and drop a file.");
                                    return;
                                }
                                
                                ToastService.showInfo("Quick Share", "Sending " + selectedFiles.length + " file(s) to " + model.name + "...");
                                QuickShareService.sendFiles(model.id, model.name, model.ip, selectedFiles);
                            }
                        }
                    }
                    
                    Item { Layout.fillHeight: true } // Fills remaining space
                }
            }
        }
    }

    popoutWidth: 400
    popoutHeight: 600
}
