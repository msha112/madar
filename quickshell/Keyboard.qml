pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

// Madar — current keyboard language (English / Arabic)
Singleton {
    id: kb

    property string layout: "English (US)"
    readonly property bool arabic: layout.toLowerCase().includes("arab")
    readonly property string name: arabic ? "Arabic" : "English"
    readonly property string badge: arabic ? "ع" : "EN"

    function next() { Hyprland.dispatch("exec hyprctl switchxkblayout all next") }

    Process {
        id: query
        running: true
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const kbs = JSON.parse(this.text).keyboards;
                    const main = kbs.find(k => k.main) ?? kbs[0];
                    if (main) kb.layout = main.active_keymap;
                } catch (e) {}
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "activelayout") return;
            const parts = event.data.split(",");
            kb.layout = parts[parts.length - 1];
        }
    }
}
