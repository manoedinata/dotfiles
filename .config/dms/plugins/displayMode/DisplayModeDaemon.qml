import QtQuick
import Quickshell.Io
import qs.Common
import qs.Modals.Common
import qs.Modules.Plugins
import qs.DCommon.Widgets

PluginComponent {
    id: root

    // One of: none, extend, mirror. Comes from `display-mode status`.
    property string mode: "none"
    property int selectedIndex: 0

    readonly property var script: ["sh", "-c", "exec \"$HOME/.local/bin/display-mode\" \"$0\""]
    readonly property var modes: [
        {
            "key": "extend",
            "label": "Extend",
            "icon": "desktop_windows",
            "description": "Use each screen separately"
        },
        {
            "key": "mirror",
            "label": "Mirror",
            "icon": "content_copy",
            "description": "Show the laptop screen on the external display"
        }
    ]

    function openDialog() {
        Proc.runCommand("displayMode.dialogStatus", script.concat(["status"]), (stdout, exitCode) => {
            if (exitCode === 0)
                root.mode = stdout.trim();
            root.selectedIndex = root.mode === "mirror" ? 1 : 0;
            modal.open();
        }, 0);
    }

    function apply(index) {
        modal.close();
        Proc.runCommand("displayMode.apply", script.concat([modes[index].key]), (stdout, exitCode) => {}, 0);
    }

    IpcHandler {
        target: "displayMode"

        function toggle(): string {
            if (modal.shouldBeVisible) {
                modal.close();
                return "closed";
            }
            root.openDialog();
            return "opened";
        }
    }

    DModal {
        id: modal

        layerNamespace: "dms:display-mode"
        keepPopoutsOpen: true
        shouldBeVisible: false
        modalWidth: 440
        modalHeight: 226
        enableShadow: true
        onBackgroundClicked: close()

        onShouldHaveFocusChanged: {
            if (shouldHaveFocus)
                Qt.callLater(() => modalFocusScope.forceActiveFocus());
        }

        modalFocusScope.Keys.onPressed: event => {
            if (event.isAutoRepeat) {
                event.accepted = true;
                return;
            }

            switch (event.key) {
            case Qt.Key_Left:
            case Qt.Key_Right:
            case Qt.Key_Up:
            case Qt.Key_Down:
            case Qt.Key_Tab:
            case Qt.Key_Backtab:
                root.selectedIndex = (root.selectedIndex + 1) % root.modes.length;
                event.accepted = true;
                break;
            case Qt.Key_Space:
            case Qt.Key_Return:
            case Qt.Key_Enter:
                root.apply(root.selectedIndex);
                event.accepted = true;
                break;
            case Qt.Key_1:
                root.apply(0);
                event.accepted = true;
                break;
            case Qt.Key_2:
                root.apply(1);
                event.accepted = true;
                break;
            case Qt.Key_Escape:
                modal.close();
                event.accepted = true;
                break;
            }
        }

        content: Component {
            Item {
                anchors.fill: parent

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingL
                    spacing: Theme.spacingL

                    Column {
                        width: parent.width
                        spacing: Theme.spacingXS

                        StyledText {
                            text: "Display Mode"
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Theme.fontWeightMedium
                            color: Theme.surfaceText
                        }

                        StyledText {
                            text: root.mode === "none" ? "No external display connected" : root.modes[root.selectedIndex].description
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceTextMedium
                            width: parent.width
                            elide: Text.ElideRight
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingM

                        Repeater {
                            model: root.modes

                            Rectangle {
                                id: modeButton
                                required property int index
                                required property var modelData

                                readonly property bool isSelected: root.selectedIndex === index
                                readonly property bool isActive: root.mode === modelData.key

                                width: (parent.width - Theme.spacingM) / 2
                                height: 120
                                radius: Theme.cornerRadius
                                color: {
                                    if (isActive)
                                        return Theme.selectedContainer;
                                    if (isSelected)
                                        return Theme.primaryHoverLight;
                                    return Theme.floatingWindowNestedSurface;
                                }
                                border.color: isSelected ? Theme.focusRingColor : Theme.outlineMedium
                                border.width: isSelected ? Theme.outlineWidthFocused : Theme.layerOutlineWidth

                                Column {
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingS

                                    DIcon {
                                        name: modeButton.modelData.icon
                                        size: Theme.iconSize + 16
                                        color: modeButton.isActive ? Theme.accentOnSelectedContainer : Theme.surfaceText
                                        filled: modeButton.isActive
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }

                                    StyledText {
                                        text: modeButton.modelData.label
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Theme.fontWeightMedium
                                        color: modeButton.isActive ? Theme.onSelectedContainer : Theme.surfaceText
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: root.selectedIndex = modeButton.index
                                    onClicked: root.apply(modeButton.index)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
