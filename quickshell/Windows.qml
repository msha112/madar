pragma Singleton

import Quickshell
import Quickshell.Hyprland
import QtQuick

// Madar — window helpers (focus · minimize · close) shared by the rail and the overview.
// "Minimized" windows live on a hidden workspace called special:minimized.
Singleton {
    id: win

    function addr(t) {
        const a = String(t.address);
        return a.startsWith("0x") ? a : "0x" + a;
    }
    function appId(t) {
        return t?.wayland?.appId || t?.lastIpcObject?.class || "";
    }
    function title(t) {
        return t?.wayland?.title || t?.title || t?.lastIpcObject?.title || "";
    }
    function isMinimized(t) {
        return (t?.workspace?.name ?? "") === "special:minimized";
    }
    function isActive(t) {
        return !isMinimized(t) && (t?.wayland?.activated ?? t?.activated ?? false);
    }
    function entryFor(id) {
        if (!id) return null;
        const _ = DesktopEntries.applications.values;     // re-run when the app list loads
        return DesktopEntries.byId(id)
            ?? (DesktopEntries.heuristicLookup ? DesktopEntries.heuristicLookup(id) : null);
    }

    function minimize(t) {
        Hyprland.dispatch("movetoworkspacesilent special:minimized,address:" + addr(t));
        refresh.restart();
    }
    function focus(t) {
        if (isMinimized(t)) {
            const ws = Hyprland.focusedWorkspace?.id ?? 1;
            Hyprland.dispatch("movetoworkspacesilent " + ws + ",address:" + addr(t));
        }
        Hyprland.dispatch("focuswindow address:" + addr(t));
        // floating windows: bring the focused one in front of the others
        Hyprland.dispatch("alterzorder top,address:" + addr(t));
        refresh.restart();
    }
    function close(t) {
        Hyprland.dispatch("closewindow address:" + addr(t));
    }

    // Keep window → workspace info fresh after we move things around
    Timer {
        id: refresh
        interval: 120
        onTriggered: {
            if (Hyprland.refreshToplevels) Hyprland.refreshToplevels();
            if (Hyprland.refreshWorkspaces) Hyprland.refreshWorkspaces();
        }
    }

    // Apps' own minimize buttons ask Hyprland to minimize — we honour that here
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "minimized") return;
            const parts = event.data.split(",");
            if (parts[1] !== "1") return;
            const a = parts[0].startsWith("0x") ? parts[0] : "0x" + parts[0];
            Hyprland.dispatch("movetoworkspacesilent special:minimized,address:" + a);
            refresh.restart();
        }
    }
}
