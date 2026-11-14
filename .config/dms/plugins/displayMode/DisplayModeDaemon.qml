import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.WindowManager
import qs.Common
import qs.Modals.Common
import qs.Modules.Plugins
import qs.DCommon.Widgets

PluginComponent {
    id: root

    // One of: none, extend, mirror, internal, external. Comes from `display-mode status`.
    property string mode: "none"
    readonly property bool hasExternal: mode !== "none"
    property int selectedIndex: 0

    // External display modes, from `display-mode modes`.
    property var displayModes: []
    property string selectedResolution: ""
    // Set while a new mode waits for confirmation. display-mode reverts it itself.
    property string pendingMode: ""
    property int revertCountdown: 0
    // One of: left, above, right. Comes from `display-mode placement`.
    property string placement: "right"

    readonly property var placements: [
        {
            "key": "left",
            "label": "Left",
            "icon": "arrow_back"
        },
        {
            "key": "above",
            "label": "Above",
            "icon": "arrow_upward"
        },
        {
            "key": "right",
            "label": "Right",
            "icon": "arrow_forward"
        }
    ]

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
        },
        {
            "key": "internal",
            "label": "Internal Only",
            "icon": "laptop",
            "description": "Use only the laptop screen and turn the external display off"
        },
        {
            "key": "external",
            "label": "External Only",
            "icon": "monitor",
            "description": "Use only the external display and turn the laptop screen off"
        }
    ]

    // Per-output workspaces (labwc with <desktops perOutput="yes">).
    // Names of the workspaces that live on the external display, saved in plugin settings.
    readonly property var externalWorkspaces: pluginData.externalWorkspaces || []
    readonly property var internalScreen: Quickshell.screens.find(s => isInternal(s.name)) || null
    readonly property var externalScreen: Quickshell.screens.find(s => !isInternal(s.name)) || null
    readonly property var internalProjection: internalScreen ? WindowManager.screenProjection(internalScreen) : null
    readonly property var externalProjection: externalScreen ? WindowManager.screenProjection(externalScreen) : null
    // Workspaces can only move between displays when labwc runs with per-output workspaces.
    readonly property bool canBindWorkspaces: !!internalProjection && !!externalProjection && WindowManager.windowsets.some(w => w.canSetProjection)
    readonly property var workspaceList: WindowManager.windowsets.filter(w => w.shouldDisplay !== false).sort((a, b) => a.name.localeCompare(b.name, undefined, {
            "numeric": true
        }))
    readonly property int workspaceRows: Math.max(1, Math.ceil(workspaceList.length / 6))
    readonly property int workspaceSectionHeight: canBindWorkspaces ? Theme.spacingL + Theme.fontSizeSmall * 3 + Theme.spacingS * 2 + workspaceRows * 36 + (workspaceRows - 1) * Theme.spacingS + 8 : 0

    function isInternal(name) {
        return /^(eDP|LVDS|DSI)/.test(name);
    }

    function isOnScreen(windowset, screen) {
        const projection = windowset.projection;
        return !!projection && !!screen && projection.screens.some(s => s.name === screen.name);
    }

    function shortName(name) {
        const match = /^Workspace (.+)$/.exec(name);
        return match ? match[1] : name;
    }

    // Moves a workspace to the other display and remembers the choice.
    // labwc refuses to move the last workspace off a display.
    function toggleWorkspace(windowset) {
        const toExternal = !isOnScreen(windowset, externalScreen);
        windowset.setProjection(toExternal ? externalProjection : internalProjection);
        const list = externalWorkspaces.filter(n => n !== windowset.name);
        if (toExternal)
            list.push(windowset.name);
        pluginService.savePluginData(pluginId, "externalWorkspaces", list);
    }

    // Puts the saved workspaces on the external display, e.g. after it is plugged in.
    // Workspaces labwc placed there on its own go back to the laptop screen.
    function applyWorkspaces() {
        if (!canBindWorkspaces || externalWorkspaces.length === 0)
            return;
        const all = WindowManager.windowsets.filter(w => w.canSetProjection);
        const extra = all.filter(w => !externalWorkspaces.includes(w.name) && isOnScreen(w, externalScreen));
        // Move the wanted ones first, so the external display is never left empty.
        for (const w of all) {
            if (externalWorkspaces.includes(w.name) && !isOnScreen(w, externalScreen))
                w.setProjection(externalProjection);
        }
        for (const w of extra)
            w.setProjection(internalProjection);
    }

    onExternalWorkspacesChanged: applyTimer.restart()
    onExternalProjectionChanged: applyTimer.restart()
    onCanBindWorkspacesChanged: applyTimer.restart()

    Timer {
        id: applyTimer
        interval: 800
        onTriggered: root.applyWorkspaces()
    }

    function openDialog() {
        Proc.runCommand("displayMode.dialogStatus", script.concat(["status"]), (stdout, exitCode) => {
            if (exitCode === 0)
                root.mode = stdout.trim();
            root.selectedIndex = Math.max(0, root.modes.findIndex(m => m.key === root.mode));
            root.loadModes();
            root.loadPlacement();
            modal.open();
        }, 0);
    }

    // Keeps the dialog right when a display is plugged in or removed while it is open.
    function pollStatus() {
        Proc.runCommand("displayMode.pollStatus", script.concat(["status"]), (stdout, exitCode) => {
            const next = stdout.trim();
            if (exitCode !== 0 || next === root.mode)
                return;
            root.mode = next;
            root.loadModes();
            root.loadPlacement();
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

    function loadPlacement() {
        Proc.runCommand("displayMode.placement", script.concat(["placement"]), (stdout, exitCode) => {
            if (exitCode === 0)
                root.placement = stdout.trim();
        }, 0);
    }

    function choosePlacement(key) {
        Proc.runCommand("displayMode.setPlacement", script.concat(["set-placement", key]), (stdout, exitCode) => root.loadPlacement(), 0);
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
        if (!hasExternal)
            return;
        modal.close();
        Proc.runCommand("displayMode.apply", script.concat([modes[index].key]), (stdout, exitCode) => {}, 0);
    }

    Timer {
        interval: 2000
        repeat: true
        running: modal.shouldBeVisible
        onTriggered: root.pollStatus()
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
        modalWidth: 540
        modalHeight: {
            if (root.mode === "none" || root.mode === "internal")
                return 226;
            if (root.mode === "external")
                return 530 - (Theme.fontSizeSmall + Theme.spacingS + 40 + Theme.spacingL);
            return 530 + (root.mode === "extend" ? root.workspaceSectionHeight : 0);
        }
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
            case Qt.Key_3:
                root.apply(2);
                event.accepted = true;
                break;
            case Qt.Key_4:
                root.apply(3);
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

                                readonly property bool isSelected: root.hasExternal && root.selectedIndex === index
                                readonly property bool isActive: root.mode === modelData.key

                                width: (parent.width - Theme.spacingM * (root.modes.length - 1)) / root.modes.length
                                height: 120
                                radius: Theme.cornerRadius
                                opacity: root.hasExternal ? 1 : 0.4
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
                                    enabled: root.hasExternal
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
                        visible: root.mode !== "none" && root.mode !== "internal" && root.pendingMode === ""

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
                        spacing: Theme.spacingS
                        visible: root.mode !== "none" && root.mode !== "internal" && root.mode !== "external" && root.pendingMode === ""

                        StyledText {
                            text: "Monitor Placement"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceTextMedium
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.spacingM

                            Repeater {
                                model: root.placements

                                Rectangle {
                                    id: placementButton
                                    required property var modelData

                                    readonly property bool isActive: root.placement === modelData.key

                                    width: (parent.width - Theme.spacingM * 2) / 3
                                    height: 40
                                    radius: Theme.cornerRadius
                                    color: isActive ? Theme.selectedContainer : placementMouse.containsMouse ? Theme.primaryHoverLight : Theme.floatingWindowNestedSurface

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: Theme.spacingXS

                                        DIcon {
                                            name: placementButton.modelData.icon
                                            size: Theme.iconSize - 4
                                            color: placementButton.isActive ? Theme.accentOnSelectedContainer : Theme.surfaceText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            text: placementButton.modelData.label
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: placementButton.isActive ? Theme.onSelectedContainer : Theme.surfaceText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    MouseArea {
                                        id: placementMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.choosePlacement(placementButton.modelData.key)
                                    }
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: root.mode === "extend" && root.pendingMode === "" && root.canBindWorkspaces

                        StyledText {
                            text: "Workspaces on External Display"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceTextMedium
                        }

                        Flow {
                            width: parent.width
                            spacing: Theme.spacingS

                            Repeater {
                                model: root.workspaceList

                                Rectangle {
                                    id: workspaceChip
                                    required property var modelData

                                    readonly property bool isActive: root.isOnScreen(modelData, root.externalScreen)

                                    width: (parent.width - Theme.spacingS * 5) / 6
                                    height: 36
                                    radius: Theme.cornerRadius
                                    color: isActive ? Theme.selectedContainer : workspaceMouse.containsMouse ? Theme.primaryHoverLight : Theme.floatingWindowNestedSurface

                                    StyledText {
                                        anchors.centerIn: parent
                                        width: parent.width - Theme.spacingS
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        text: root.shortName(workspaceChip.modelData.name)
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: workspaceChip.isActive ? Theme.onSelectedContainer : Theme.surfaceText
                                    }

                                    MouseArea {
                                        id: workspaceMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleWorkspace(workspaceChip.modelData)
                                    }
                                }
                            }
                        }

                        StyledText {
                            text: "Highlighted workspaces are on the external display."
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceTextMedium
                            width: parent.width
                            wrapMode: Text.WordWrap
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
