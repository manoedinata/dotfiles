import QtQuick
import qs.Common
import qs.Modules.Plugins

PluginComponent {
    id: root

    // One of: none, extend, mirror. Comes from `display-mode status`.
    property string mode: "none"

    readonly property var script: ["sh", "-c", "exec \"$HOME/.local/bin/display-mode\" \"$0\""]

    function refresh() {
        Proc.runCommand("displayMode.status", script.concat(["status"]), (stdout, exitCode) => {
            if (exitCode === 0)
                root.mode = stdout.trim();
        }, 0);
    }

    ccWidgetIcon: "screen_share"
    ccWidgetPrimaryText: "Mirror Display"
    ccWidgetSecondaryText: mode === "mirror" ? "Mirror" : mode === "extend" ? "Extend" : "No external display"
    ccWidgetIsActive: mode === "mirror"

    onCcWidgetToggled: {
        Proc.runCommand("displayMode.toggle", script.concat(["toggle"]), (stdout, exitCode) => {
            root.refresh();
        }, 0);
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
