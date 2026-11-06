// Madar shell — entry point
// Location: ~/.config/quickshell/shell.qml
import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    // One launcher, opened on whichever screen is focused
    Launcher { id: launcher }

    // Lets Hyprland key bindings talk to the shell:
    //   quickshell ipc call launcher toggle
    IpcHandler {
        target: "launcher"
        function toggle(): void { launcher.toggle() }
        function open(): void { launcher.open() }
        function close(): void { launcher.close() }
    }

    // Notifications (daemon + popups) and the control center
    Notifications { id: notifs }
    ControlCenter { id: controlCenter; notifs: notifs }

    IpcHandler {
        target: "controlcenter"
        function toggle(): void { controlCenter.toggle() }
    }

    // Overview of all open windows (tap Super)
    Overview { id: overview }

    IpcHandler {
        target: "overview"
        function toggle(): void { overview.toggle() }
    }

    // Size and place new windows (big apps maximized, small ones centred)
    WindowRules {}

    // Alt + Tab switcher (driven by Hyprland global shortcuts)
    Switcher {}

    // Clipboard history (Super + V)
    Clipboard { id: clipboard }

    IpcHandler {
        target: "clipboard"
        function toggle(): void { clipboard.toggle() }
    }

    // Volume / brightness pop-up
    Osd {}

    // Lock screen
    LockScreen { id: lockScreen }

    IpcHandler {
        target: "lock"
        function lock(): void { lockScreen.lock(false) }
        function test(): void { lockScreen.lock(true) }
    }

    // Wallpaper + side rail on every connected screen
    Variants {
        model: Quickshell.screens

        Scope {
            id: perScreen
            required property var modelData

            Wallpaper { screen: perScreen.modelData }

            Home {
                screen: perScreen.modelData
                onLauncherRequested: launcher.toggle()
            }

            Sidebar {
                screen: perScreen.modelData
                onLauncherRequested: launcher.toggle()
                notifCount: notifs.count
                onControlCenterRequested: controlCenter.toggle()
            }
        }
    }
}
