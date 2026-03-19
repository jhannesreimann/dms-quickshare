import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

StyledRect {
    id: root

    property string state
    property string bytesStr
    property real progress

    width: parent.width
    height: 60
    radius: Theme.cornerRadius
    color: Theme.surfaceContainerHighest
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingS

        RowLayout {
            Layout.fillWidth: true
            
            StyledText {
                text: root.state === "ReceivingFiles" ? "Receiving..." : "Sending..."
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
                Layout.fillWidth: true
            }
            
            StyledText {
                text: root.bytesStr
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 4
            radius: 2
            color: Theme.surfaceVariant
            
            Rectangle {
                height: parent.height
                width: parent.width * root.progress
                radius: 2
                color: Theme.primary
                
                Behavior on width {
                    NumberAnimation { duration: 200 }
                }
            }
        }
    }
}
