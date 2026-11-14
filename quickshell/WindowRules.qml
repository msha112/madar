// Madar — window helpers
//   · an app's own maximize button → floating-style maximize (scripts/max.sh)
//   · apps that ask to open maximized (because they were closed that way) open
//     as a normal window instead
//   · dragging a maximized window away gives it back its normal size
// New windows get their size from the window rules in hyprland.conf, applied
// before they appear, so there's no jump. The lists below are only used to pick
// the size when undoing an "open maximized" request.
// Location: ~/.config/quickshell/WindowRules.qml
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

Scope {
    id: rules

    readonly property var maximized: [
        /chrome/i, /chromium/i, /firefox/i, /brave/i, /edge/i,
        /nautilus/i, /telegram/i, /^code/i, /cursor/i, /libreoffice/i,
        /thunderbird/i, /gimp/i, /inkscape/i, /obsidian/i, /discord/i,
        /slack/i, /whatsapp/i, /spotify/i, /vlc/i, /totem/i, /zoom/i, /teams/i
    ]
    readonly property var medium: [
        /kitty/i, /ptyxis/i, /terminal/i, /alacritty/i, /foot/i,
        /texteditor/i, /gedit/i, /settings/i, /control-center/i,
        /loupe/i, /evince/i, /papers/i, /software/i, /baobab/i, /disk/i
    ]
    readonly property var centerOnly: [
        /calculator/i, /pavucontrol/i, /characters/i, /clocks/i, /weather/i
    ]
    // titles that mean "this is a dialog, not the main window"
    readonly property var dialogTitle: /\b(open|save|properties|preferences|about|select|choose|rename|delete|confirm|print|export|import|upload|password|authenticate)\b/i

    function decide(cls, title) {
        if (dialogTitle.test(title)) return "";
        if (maximized.some(r => r.test(cls))) return "large";
        if (medium.some(r => r.test(cls))) return "medium";
        if (centerOnly.some(r => r.test(cls))) return "center";
        return "";
    }

    property var queue: []
    Process { id: runner; onExited: rules.next() }
    function next() {
        if (runner.running || queue.length === 0) return;
        const job = queue[0];
        queue = queue.slice(1);
        runner.command = [Quickshell.env("HOME") + "/.config/quickshell/scripts/snap.sh", job.mode, job.addr];
        runner.running = true;
    }

    // wait a moment so the app has set its title and size
    Timer {
        id: settle
        interval: 80
        onTriggered: rules.next()
    }

    // Windows opened in the last few seconds: some apps (Chrome, Telegram…) ask to be
    // maximized when they open because that's how they were last closed. We don't want
    // that — everything opens as a normal window — so those requests are undone.
    property var recent: ({})        // address → { mode, time }

    // An app's own maximize button: maximize the floating way (see scripts/max.sh)
    Process { id: maxProc }
    Timer {
        id: maxDelay
        interval: 40
        onTriggered: {
            const a = Windows.addr(Hyprland.activeToplevel ?? { address: "" });
            const r = rules.recent[a];
            if (r && Date.now() - r.time < 2500) {
                // asked to open maximized → open as a normal window instead
                rules.queue = rules.queue.concat([{ addr: a, mode: r.mode === "" ? "center" : r.mode }]);
                rules.next();
                return;
            }
            maxProc.command = [Quickshell.env("HOME") + "/.config/quickshell/scripts/max.sh", "fromapp"];
            maxProc.running = true;
        }
    }

    // ── Drag a maximized window away → it goes back to its normal size ──
    // Hyprland doesn't announce drags, so we watch window positions: quickly while a
    // maximized window is on screen, slowly otherwise. When a maximized window has
    // moved and then stays put (you let go), it's restored where you dropped it.
    property var dragState: ({})     // address → { x, y, moved }
    property bool anyMax: false
    Process { id: dropProc }
    Timer {
        interval: rules.anyMax ? 150 : 1000
        running: true
        repeat: true
        onTriggered: {
            rules.checkDrags();
            Hyprland.refreshToplevels();     // fresh positions for the next tick
        }
    }
    function checkDrags() {
        const rail = Theme.railWidth;
        const next = {};
        let anyFull = false;
        for (const t of Hyprland.toplevels.values) {
            const o = t.lastIpcObject;
            const m = t.monitor;
            if (!o || !o.at || !m || !o.floating || o.hidden) continue;
            if ((o.workspace?.name ?? "").startsWith("special")) continue;
            const mx = m.x, my = m.y, mw = Math.floor(m.width / m.scale), mh = Math.floor(m.height / m.scale);
            const full = o.size[0] >= mw - rail - 4 && o.size[1] >= mh - 4;
            if (!full) continue;
            anyFull = true;
            const a = Windows.addr(t);
            const atMax = Math.abs(o.at[0] - (mx + rail)) <= 4 && Math.abs(o.at[1] - my) <= 4;
            const prev = rules.dragState[a];
            if (atMax) { next[a] = { x: o.at[0], y: o.at[1], moved: false }; continue; }
            if (!prev) continue;                                  // full size but never was maximized here
            const same = prev.x === o.at[0] && prev.y === o.at[1];
            const stillFor = prev.moved && same ? (prev.still ?? 0) + 1 : 0;
            if (stillFor >= 2 && !dropProc.running) {           // ~0.3 s without moving = let go
                dropProc.command = [Quickshell.env("HOME") + "/.config/quickshell/scripts/max.sh", "drop", a];
                dropProc.running = true;
                continue;                                         // forget it
            }
            next[a] = { x: o.at[0], y: o.at[1], moved: true, still: stillFor };
        }
        rules.dragState = next;
        rules.anyMax = anyFull;
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "fullscreen" && event.data === "1") { maxDelay.restart(); return; }
            if (event.name !== "openwindow") return;
            // ADDRESS,WORKSPACE,CLASS,TITLE   (the title may itself contain commas)
            const d = event.data;
            const a = d.indexOf(","), b = d.indexOf(",", a + 1), c = d.indexOf(",", b + 1);
            if (a < 0 || b < 0 || c < 0) return;
            const ws = d.slice(a + 1, b);
            if (ws.startsWith("special")) return;
            const addr = "0x" + d.slice(0, a).replace(/^0x/, "");
            const mode = rules.decide(d.slice(b + 1, c), d.slice(c + 1));

            // remember it for a few seconds (and forget old entries)
            const now = Date.now();
            const r = {};
            for (const k in rules.recent) if (now - rules.recent[k].time < 5000) r[k] = rules.recent[k];
            r[addr] = { mode: mode, time: now };
            rules.recent = r;

            // New windows are sized by the window rules in hyprland.conf the moment
            // they open; here we only undo apps that ask to open maximized (above).
        }
    }
}
