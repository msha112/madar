#!/usr/bin/env bash
# Madar on GNOME — step 1: built-in settings only (no extensions)
# Every line is a normal GNOME setting; undo any of them with "gsettings reset <schema> <key>".

# ── Look ─────────────────────────────────────────────────────
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface accent-color 'blue'
gsettings set org.gnome.desktop.interface icon-theme 'WhiteSur-dark'
gsettings set org.gnome.desktop.interface font-name 'Inter 11'
gsettings set org.gnome.desktop.interface document-font-name 'Inter 11'
gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrains Mono 11'
gsettings set org.gnome.desktop.wm.preferences titlebar-font 'Inter Bold 11'
gsettings set org.gnome.desktop.interface clock-show-weekday true
gsettings set org.gnome.desktop.interface show-battery-percentage true

# ── Windows: like Windows ────────────────────────────────────
gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'
gsettings set org.gnome.mutter center-new-windows true
gsettings set org.gnome.mutter edge-tiling true
gsettings set org.gnome.desktop.wm.keybindings switch-windows "['<Alt>Tab']"
gsettings set org.gnome.desktop.wm.keybindings switch-windows-backward "['<Shift><Alt>Tab']"
gsettings set org.gnome.desktop.wm.keybindings switch-applications "[]"
gsettings set org.gnome.desktop.wm.keybindings switch-applications-backward "[]"

# ── Dock on the left, floating, Windows-style clicks ─────────
D=org.gnome.shell.extensions.dash-to-dock
gsettings set $D dock-position 'LEFT'
gsettings set $D extend-height false
gsettings set $D dock-fixed true
gsettings set $D dash-max-icon-size 40
gsettings set $D transparency-mode 'FIXED'
gsettings set $D background-opacity 0.85
gsettings set $D custom-theme-shrink true
gsettings set $D running-indicator-style 'DOTS'
gsettings set $D click-action 'minimize-or-previews'   # click: open / minimize / pick a window
gsettings set $D scroll-action 'cycle-windows'
gsettings set $D show-trash false
gsettings set $D show-mounts false
gsettings set $D show-apps-at-top true

# ── Keyboard: English + Arabic, Alt+Shift switches ───────────
gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'us'), ('xkb', 'ara')]"
gsettings set org.gnome.desktop.input-sources xkb-options "['grp:alt_shift_toggle']"

# ── Touchpad ─────────────────────────────────────────────────
gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true
gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll true

echo "Done. Some changes (fonts, dock) show fully after logging out and in."
