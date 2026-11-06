// Madar — Alt + Tab window switcher (most recently used first)
//   hold Alt, tap Tab to move (Shift + Tab goes back), let go of Alt to switch
//   Esc cancels · click a window to switch to it
// Location: ~/.config/quickshell/Switcher.qml
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: sw

    property bool shown: false
    property int selected: 0
    property var list: []

    // ── Most-recently-used order, kept up to date from Hyprland ──
    property var mru: []            // addresses, newest first
    function norm(a) { a = String(a); return a.startsWith("0x") ? a : "0x" + a }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "activewindowv2" || event.data === "") return;
            const a = sw.norm(event.data);
            sw.mru = [a].concat(sw.mru.filter(x => x !== a)).slice(0, 64);
        }
    }

    function build() {
        const wins = Hyprland.toplevels.values.filter(t => Windows.appId(t) !== "");
        const rank = t => { const i = mru.indexOf(Windows.addr(t)); return i < 0 ? 999 : i };
        return wins.slice().sort((a, b) => {
            const ma = Windows.isMinimized(a), mb = Windows.isMinimized(b);
            if (ma !== mb) return ma ? 1 : -1;          // minimized ones last
            return rank(a) - rank(b);
        });
    }

    function step(dir) {
        if (!shown) {
            list = build();
            if (list.length === 0) return;
            selected = list.length > 1 ? (dir > 0 ? 1 : list.length - 1) : 0;
            shown = true;
            return;
        }
        if (list.length === 0) return;
        selected = (selected + dir + list.length) % list.length;
    }
    function commit() {
        if (!shown) return;
        const t = list[selected];
        shown = false;
        if (t) Windows.focus(t);
    }
    function cancel() { shown = false }

    // Alt + Tab / Alt + Shift + Tab arrive from Hyprland as global shortcuts (no lag)
    GlobalShortcut { name: "switcherNext"; description: "Alt+Tab: next window"; onPressed: sw.step(1) }
    GlobalShortcut { name: "switcherPrev"; description: "Alt+Shift+Tab: previous window"; onPressed: sw.step(-1) }

    visible: shown
    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "madar-switcher"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"

    // ── Keys: letting go of Alt switches ─────────────────────
    Item {
        anchors.fill: parent
        focus: true
        onVisibleChanged: if (visible) forceActiveFocus()

        Keys.onReleased: event => {
            if (event.key === Qt.Key_Alt || event.key === Qt.Key_AltGr
                || !(event.modifiers & Qt.AltModifier)) {
                sw.commit();
                event.accepted = true;
            }
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) sw.cancel();
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) sw.commit();
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) sw.step(1);
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) sw.step(-1);
            else return;
            event.accepted = true;
        }
    }

    // click outside cancels
    MouseArea { anchors.fill: parent; onClicked: sw.cancel() }

    // ── The strip ────────────────────────────────────────────
    Rectangle {
        id: strip
        anchors.centerIn: parent
        width: Math.min(parent.width - 120, row.implicitWidth + 32)
        height: row.implicitHeight + 32
        radius: 28
        color: Theme.cardGlass
        border.color: Theme.panelLine
        border.width: 1
        clip: true

        opacity: sw.shown ? 1 : 0
        scale: sw.shown ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }   // don't cancel when clicking the strip itself

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: 16
            contentWidth: row.implicitWidth
            interactive: false
            // keep the selected card in view
            contentX: {
                const card = 236;           // card width + spacing
                const target = sw.selected * card - (width - card) / 2;
                return Math.max(0, Math.min(target, contentWidth - width));
            }
            Behavior on contentX { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            Row {
                id: row
                spacing: 16

                Repeater {
                    model: sw.shown ? sw.list : []

                    delegate: Item {
                        id: card
                        required property var modelData
                        required property int index
                        readonly property var win: modelData
                        readonly property bool sel: index === sw.selected
                        readonly property bool minimized: Windows.isMinimized(win)
                        readonly property var entry: Windows.entryFor(Windows.appId(win))

                        width: 220
                        height: 196

                        Rectangle {
                            id: frame
                            width: parent.width
                            height: 140
                            radius: 16
                            color: Theme.card
                            border.width: card.sel ? 3 : 1
                            border.color: card.sel ? Theme.accent : Theme.panelLine
                            clip: true
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            ScreencopyView {
                                id: preview
                                anchors.centerIn: parent
                                captureSource: sw.shown && !card.minimized ? (card.win.wayland ?? null) : null
                                live: false
                                constraintSize: Qt.size(frame.width - 12, frame.height - 12)
                            }
                            IconImage {
                                anchors.centerIn: parent
                                visible: !preview.hasContent
                                implicitSize: 56
                                opacity: card.minimized ? 0.6 : 1
                                source: Quickshell.iconPath(card.entry?.icon ?? Windows.appId(card.win), "application-x-executable")
                            }
                        }

                        // app icon badge
                        Rectangle {
                            anchors.horizontalCenter: frame.horizontalCenter
                            y: frame.height - 22
                            width: 44; height: 44; radius: 14
                            color: card.sel ? Theme.accent : Theme.raised
                            border.color: Theme.panelLine
                            Behavior on color { ColorAnimation { duration: 120 } }
                            IconImage {
                                anchors.centerIn: parent
                                implicitSize: 28
                                source: Quickshell.iconPath(card.entry?.icon ?? Windows.appId(card.win), "application-x-executable")
                            }
                        }

                        Text {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: (card.minimized ? "· " : "") + (Windows.title(card.win) || (card.entry?.name ?? Windows.appId(card.win)))
                            font.family: Theme.font
                            font.pixelSize: 12
                            font.weight: card.sel ? Font.DemiBold : Font.Normal
                            color: card.sel ? Theme.text : Theme.sub
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: sw.selected = card.index
                            onClicked: { sw.selected = card.index; sw.commit() }
                        }
                    }
                }
            }
        }
    }
}
