import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import "../services"

StyledRect {
    id: root

    property string transferId
    property string deviceName
    property string pin

    signal requestHandled(string tId)

    width: parent.width
    height: 80
    radius: Theme.cornerRadius
    color: Theme.surfaceContainerHighest
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingS
        spacing: 4

        StyledText {
            text: root.deviceName + " is sending a file"
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceText
        }
        
        StyledText {
            text: root.pin !== "" ? "PIN: " + root.pin : ""
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            visible: root.pin !== ""
        }

        RowLayout {
            spacing: Theme.spacingS
            
            StyledButton {
                text: "Accept"
                type: "primary"
                Layout.preferredHeight: 30
                onClicked: {
                    QuickShareService.acceptTransfer(root.transferId);
                    root.requestHandled(root.transferId);
                }
            }

            StyledButton {
                text: "Reject"
                type: "secondary"
                Layout.preferredHeight: 30
                onClicked: {
                    QuickShareService.rejectTransfer(root.transferId);
                    root.requestHandled(root.transferId);
                }
            }
        }
    }
}
