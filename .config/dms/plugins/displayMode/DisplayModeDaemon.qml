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

    // External display modes, from `display-mode modes`.
    property var displayModes: []
    property string selectedResolution: ""
    // Set while a new mode waits for confirmation. display-mode reverts it itself.
    property string pendingMode: ""
    property int revertCountdown: 0

    readonly property var resolutions: {
        const seen = {};
        const list = [];
        for (const m of displayModes) {
            const key = m.width + "x" + m.height;
            if (seen[key])
                continue;
            seen[key] = true;
            list.push({
                "key": key,
                "area": m.width * m.height
            });
        }
        return list.sort((a, b) => b.area - a.area);
    }
    readonly property var refreshRates: displayModes.filter(m => m.width + "x" + m.height === selectedResolution).sort((a, b) => b.refresh - a.refresh)

    readonly property var script: ["sh", "-c", "exec \"$HOME/.local/bin/display-mode\" \"$0\" \"$@\""]
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
            root.loadModes();
            modal.open();
        }, 0);
    }

    function loadModes() {
        Proc.runCommand("displayMode.modes", script.concat(["modes"]), (stdout, exitCode) => {
            if (exitCode !== 0)
                return;
            root.displayModes = JSON.parse(stdout).modes;
            const current = root.displayModes.find(m => m.current);
            if (current)
                root.selectedResolution = current.width + "x" + current.height;
        }, 0);
    }

    function chooseMode(id) {
        Proc.runCommand("displayMode.setMode", script.concat(["set-mode", id]), (stdout, exitCode) => {
            if (exitCode !== 0) {
                root.loadModes();
                return;
            }
            root.pendingMode = id;
            root.revertCountdown = 15;
            countdown.restart();
        }, 0);
    }

    function keepMode() {
        countdown.stop();
        root.pendingMode = "";
        Proc.runCommand("displayMode.confirmMode", script.concat(["confirm-mode"]), (stdout, exitCode) => root.loadModes(), 0);
    }

    function revertMode() {
        countdown.stop();
        root.pendingMode = "";
        Proc.runCommand("displayMode.revertMode", script.concat(["revert-mode"]), (stdout, exitCode) => root.loadModes(), 0);
    }

    function apply(index) {
        modal.close();
        Proc.runCommand("displayMode.apply", script.concat([modes[index].key]), (stdout, exitCode) => {}, 0);
    }

    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: {
            root.revertCountdown -= 1;
            if (root.revertCountdown > 0)
                return;
            stop();
            root.pendingMode = "";
            reload.restart();
        }
    }

    // Reads the modes back just after display-mode's own revert has run.
    Timer {
        id: reload
        interval: 1500
        onTriggered: root.loadModes()
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
        modalHeight: root.mode === "none" ? 226 : 446
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

                    Row {
                        width: parent.width
                        height: 170
                        spacing: Theme.spacingM
                        visible: root.mode !== "none" && root.pendingMode === ""

                        Repeater {
                            model: [
                                {
                                    "title": "Resolution",
                                    "rate": false
                                },
                                {
                                    "title": "Refresh rate",
                                    "rate": true
                                }
                            ]

                            Column {
                                id: modeColumn
                                required property var modelData

                                width: (parent.width - Theme.spacingM) / 2
                                spacing: Theme.spacingS

                                StyledText {
                                    text: modeColumn.modelData.title
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceTextMedium
                                }

                                ListView {
                                    width: parent.width
                                    height: 170 - Theme.fontSizeSmall - Theme.spacingL
                                    clip: true
                                    spacing: 2
                                    model: modeColumn.modelData.rate ? root.refreshRates : root.resolutions

                                    delegate: Rectangle {
                                        id: modeRow
                                        required property var modelData

                                        readonly property bool isRate: modeColumn.modelData.rate
                                        readonly property bool isActive: isRate ? modelData.current : modelData.key === root.selectedResolution

                                        width: ListView.view.width
                                        height: 32
                                        radius: Theme.cornerRadius
                                        color: isActive ? Theme.selectedContainer : rowMouse.containsMouse ? Theme.primaryHoverLight : Theme.floatingWindowNestedSurface

                                        StyledText {
                                            anchors.centerIn: parent
                                            text: modeRow.isRate ? modeRow.modelData.refresh.toFixed(2) + " Hz" : modeRow.modelData.key
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: modeRow.isActive ? Theme.onSelectedContainer : Theme.surfaceText
                                        }

                                        MouseArea {
                                            id: rowMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (!modeRow.isRate)
                                                    root.selectedResolution = modeRow.modelData.key;
                                                else if (!modeRow.modelData.current)
                                                    root.chooseMode(modeRow.modelData.id);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacingM
                        visible: root.pendingMode !== ""

                        StyledText {
                            text: "Keep " + root.pendingMode + "? Reverting in " + root.revertCountdown + "s"
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.spacingM

                            Repeater {
                                model: [
                                    {
                                        "label": "Keep",
                                        "keep": true
                                    },
                                    {
                                        "label": "Revert",
                                        "keep": false
                                    }
                                ]

                                Rectangle {
                                    id: confirmButton
                                    required property var modelData

                                    width: (parent.width - Theme.spacingM) / 2
                                    height: 40
                                    radius: Theme.cornerRadius
                                    color: modelData.keep ? Theme.selectedContainer : Theme.floatingWindowNestedSurface

                                    StyledText {
                                        anchors.centerIn: parent
                                        text: confirmButton.modelData.label
                                        font.pixelSize: Theme.fontSizeMedium
                                        color: confirmButton.modelData.keep ? Theme.onSelectedContainer : Theme.surfaceText
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: confirmButton.modelData.keep ? root.keepMode() : root.revertMode()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
