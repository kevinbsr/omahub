pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Column {
    id: root

    required property var panel

    width: parent ? parent.width : 0
    spacing: Style.space(6)
    visible: !!(panel && panel.device && panel.device.paired && panel.device.reachable)

    readonly property var bar: panel ? panel.bar : null
    readonly property var service: panel ? panel.service : null
    readonly property var device: panel ? panel.device : null
    readonly property color foreground: bar ? bar.foreground : "#ffffff"
    readonly property string fontFamily: bar ? bar.fontFamily : "sans-serif"

    PanelSectionHeader {
        text: (root.device && root.device.type && root.device.type !== "unknown") ? (root.device.type.toUpperCase() + " ACTIONS") : "ACTIONS"
        foreground: root.foreground
        fontFamily: root.fontFamily
    }

    Flow {
        width: parent.width
        spacing: Style.space(6)
        Repeater {
            model: panel ? panel.availableActions : []
            delegate: CursorSurface {
                required property string modelData
                required property int index
                readonly property string actionName: {
                    if (modelData === "ring") return "Ring"
                    if (modelData === "clipboard") return "Clipboard"
                    if (modelData === "file") return "File"
                    if (modelData === "sms") return "SMS"
                    if (modelData === "ping") return "Ping"
                    if (modelData === "text") return "Text"
                    return modelData
                }


                implicitWidth: actionBtnText.implicitWidth + Style.space(16)
                implicitHeight: actionBtnText.implicitHeight + Style.space(8)
                hasCursor: panel.cursorActive && panel.focusSection === "actions" && panel.actionSelectedIndex === index
                current: (modelData === "ping" && panel.activeComposer === "ping") || (modelData === "text" && panel.activeComposer === "text")
                foreground: root.foreground
                fill: Style.hoverFillFor(root.foreground, Color.accent)
                currentFill: Style.selectedFillFor(root.foreground, Color.accent)
                enabled: !root.service || (root.service.actionState !== "running" && !root.service.fileBusy)

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: {
                        panel.cursorActive = true
                        panel.focusSection = "actions"
                        panel.actionSelectedIndex = index
                    }
                    onClicked: panel.triggerAction(modelData)
                }

                Text {
                    id: actionBtnText
                    anchors.centerIn: parent
                    text: parent.actionName
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                }
            }
        }
    }
}
