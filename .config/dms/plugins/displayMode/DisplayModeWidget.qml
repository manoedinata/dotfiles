import QtQuick
import qs.Common
import qs.Modules.Plugins

PluginComponent {
    id: root

    // One of: none, extend, mirror, internal, external. Comes from `display-mode status`.
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
    ccWidgetSecondaryText: mode === "mirror" ? "Mirror" : mode === "extend" ? "Extend" : mode === "internal" ? "Internal Only" : mode === "external" ? "External Only" : "No external display"
    ccWidgetIsActive: mode === "mirror" || mode === "internal" || mode === "external"

    onCcWidgetToggled: {
        // The dialog lives in the daemon. Close the Control Center first so it does not cover it.
        Proc.runCommand("displayMode.openDialog", ["sh", "-c", "dms ipc call control-center hide; dms ipc call displayMode toggle"], (stdout, exitCode) => {}, 0);
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
