pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Madar — shared colors and sizes.
// mode "auto" switches to day at 06:00 and to night at 18:00.
// Mode and accent are saved, so they survive a restart.
Singleton {
    id: theme

    // ── Saved settings (~/.local/state/madar.json) ──────────
    FileView {
        id: store
        path: Quickshell.env("HOME") + "/.local/state/madar.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: error => { if (error === FileViewError.FileNotFound) writeAdapter() }

        JsonAdapter {
            id: settings
            property string mode: "auto"      // "auto" | "day" | "night"
            property string accent: "amber"   // see accents below
            property string city: ""          // weather city, empty = detect automatically
            property string nightLight: "off" // "off" | "auto" (6 PM–6 AM) | "on"
            property string iconColor: "blue" // "blue" | "accent" (follow the accent colour)
            property string pinned: "firefox_firefox,org.gnome.Nautilus,org.gnome.TextEditor,kitty"   // rail apps
        }
    }

    readonly property string mode: settings.mode
    function cycleMode() { settings.mode = mode === "auto" ? "day" : (mode === "day" ? "night" : "auto") }

    readonly property string accentName: settings.accent
    readonly property string city: settings.city

    // Night light (warmer colours) — runs wlsunset while it's on
    readonly property string nightLight: settings.nightLight
    function cycleNightLight() {
        settings.nightLight = nightLight === "off" ? "auto" : (nightLight === "auto" ? "on" : "off");
    }
    Process { id: sunset }
    function applyNightLight() {
        sunset.running = false;
        if (nightLight === "off") return;
        sunset.command = nightLight === "on"
            ? ["wlsunset", "-t", "4200", "-T", "4201"]
            : ["wlsunset", "-t", "4200", "-T", "6500", "-S", "06:00", "-s", "18:00", "-d", "1800"];
        Qt.callLater(() => sunset.running = true);
    }
    onNightLightChanged: applyNightLight()

    // Apps pinned to the side rail (desktop-file ids)
    readonly property var pinned: settings.pinned.split(",").filter(x => x !== "")
    function isPinned(id) { return pinned.indexOf(id) >= 0 }
    function togglePin(id) {
        if (!id) return;
        const list = pinned.slice();
        const i = list.indexOf(id);
        if (i >= 0) list.splice(i, 1); else list.push(id);
        settings.pinned = list.join(",");
    }
    function setAccent(name) { settings.accent = name }

    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property int hour: clock.date.getHours()
    readonly property bool day: mode === "day" || (mode === "auto" && hour >= 6 && hour < 18)

    // ── Accent choices ───────────────────────────────────────
    readonly property var accents: ({
        amber: { name: "Amber", color: "#E8A33D", ink: "#14110C" },
        blue:  { name: "Blue",  color: "#5B9CF5", ink: "#0A1730" },
        teal:  { name: "Teal",  color: "#4FB3A3", ink: "#06201C" },
        coral: { name: "Coral", color: "#E8806E", ink: "#2A0E08" }
    })
    readonly property var accentKeys: ["amber", "blue", "teal", "coral"]
    readonly property var current: accents[accentName] ?? accents.amber

    readonly property color accent:      current.color
    readonly property color accentInk:   current.ink
    readonly property color accentInkSoft: Qt.rgba(accentInk.r, accentInk.g, accentInk.b, 0.75)
    readonly property color accentSoft:  Qt.rgba(accent.r, accent.g, accent.b, day ? 0.22 : 0.16)
    readonly property color accentLine:  Qt.rgba(accent.r, accent.g, accent.b, day ? 0.70 : 0.50)

    // Keep apps (GTK/libadwaita) in step with the shell: light/dark and icon theme
    Process { id: applyProc }
    // WhiteSur icons in the variant that matches the accent and day/night
    readonly property var iconVariant: ({ amber: "-yellow", blue: "", teal: "-green", coral: "-orange" })
    readonly property string iconColor: settings.iconColor
    readonly property string iconTheme: "WhiteSur"
        + (iconColor === "accent" ? (iconVariant[accentName] ?? "") : "")
        + (day ? "" : "-dark")
    function applySystem() {
        applyProc.running = false;
        applyProc.command = ["sh", "-c",
            'gsettings set org.gnome.desktop.interface color-scheme "$1"; ' +
            'if [ -d "$HOME/.local/share/icons/$2" ] || [ -d "/usr/share/icons/$2" ]; then ' +
            'gsettings set org.gnome.desktop.interface icon-theme "$2"; fi',
            "sh", day ? "default" : "prefer-dark", iconTheme];
        applyProc.running = true;
    }
    onDayChanged: applySystem()
    onAccentNameChanged: applySystem()
    onIconColorChanged: applySystem()
    Component.onCompleted: { applySystem(); applyNightLight() }

    readonly property color danger:      "#E07A6B"

    // ── Surfaces ─────────────────────────────────────────────
    readonly property color bg:          day ? "#F4EFE6" : "#0B0D12"
    readonly property color panel:       day ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(0.075, 0.086, 0.114, 0.94)
    readonly property color panelLine:   day ? Qt.rgba(0.16, 0.12, 0.08, 0.10) : Qt.rgba(1, 1, 1, 0.07)
    readonly property color card:        day ? "#FFFFFF" : "#14171E"
    readonly property color cardGlass:   day ? Qt.rgba(1, 1, 1, 0.96) : Qt.rgba(0.078, 0.09, 0.118, 0.96)
    readonly property color inset:       day ? "#F6F3EE" : "#1A1E26"
    readonly property color field:       day ? "#F6F3EE" : "#1B1F28"
    readonly property color raised:      day ? "#F1EDE6" : "#1D212A"
    readonly property color hover:       day ? "#EBE6DD" : "#1F242E"
    readonly property color active:      day ? "#E6E0D6" : "#262C37"
    readonly property color track:       day ? "#E6E1D9" : "#262B35"
    readonly property color track2:      day ? "#DDD7CD" : "#2F3642"
    readonly property color divider:     day ? "#E2DCD2" : "#2A303A"
    readonly property color backdrop:    day ? Qt.rgba(0.96, 0.94, 0.91, 0.55) : Qt.rgba(0.035, 0.043, 0.06, 0.55)

    // Dark "feature" tile (big clock) stays dark in both modes
    readonly property color deep:        day ? "#1B1F26" : "#101318"
    readonly property color deepRaised:  day ? "#2A303A" : "#1B1F28"
    readonly property color deepText:    "#F4F1EC"
    readonly property color deepSub:     "#B7BEC8"

    // ── Text ─────────────────────────────────────────────────
    readonly property color text:        day ? "#1B1F26" : "#E8EAED"
    readonly property color sub:         day ? "#5B6470" : "#A7AFBA"
    readonly property color sub2:        day ? "#3E4651" : "#C3C9D2"
    readonly property color faint:       day ? "#687180" : "#8E97A3"
    readonly property color muted:       day ? "#9AA2AC" : "#59616D"

    // ── Data colors ──────────────────────────────────────────
    readonly property color ram:         day ? "#4F7BC9" : "#7FA8E8"
    readonly property color disk:        day ? "#8A929C" : "#9AA3AE"

    // ── Wallpaper ────────────────────────────────────────────
    readonly property var orbits:        day ? ["#E6DDCD", "#EAE2D5", "#EDE7DC", "#F0EBE2"]
                                             : ["#171B23", "#151820", "#13161D", "#111419"]

    // ── Sizes & motion ───────────────────────────────────────
    readonly property string font:       "Inter"
    readonly property int railWidth:     64
    readonly property int gap:           12
    readonly property int radius:        22
    readonly property int anim:          180
    readonly property int themeAnim:     600
}
