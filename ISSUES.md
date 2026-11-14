# Madar — known issues

Open problems to come back to. Newest first.

## 1. Clicking the screenshot notification doesn't open the image
- **Seen:** 2026-11-06
- **What happens:** the screenshot is saved and copied, the notification shows, but clicking it (or "Open") shows nothing.
- **Found so far:**
  - The default image app is `org.gnome.Loupe.desktop` (set with `xdg-mime`).
  - Running `loupe <file>` opens a window (Hyprland lists `org.gnome.Loupe`, 1045×461 on workspace 1) but it stays invisible.
  - `GSK_RENDERER=gl loupe <file>` from a terminal **does** show the image.
  - Adding `env = GSK_RENDERER, gl` to `hyprland.conf` and logging in again did **not** fix it when opened from the notification.
- **Ideas to try next:**
  - Check the variable reaches apps: `hyprctl getoption env` / `cat /proc/$(pgrep -n loupe)/environ | tr '\0' '\n' | grep GSK`.
  - Loupe may be started by D-Bus activation (not by Hyprland), so it misses Hyprland's `env`. Put `GSK_RENDERER=gl` in `~/.config/environment.d/gsk.conf` and run `systemctl --user import-environment GSK_RENDERER`.
  - Or open screenshots with a different viewer (e.g. `eog` or `imv`) in `screenshot.sh`.

## 2. Apps freeze when their own minimize button is pressed
- **Solved 2026-11-14:** `plugin/` (madar-csd) handles the minimize request and hides the window in
  `special:minimized`. Confirmed working on the laptop.
- **Seen:** 2026-11-05
- **What happens:** pressing the minimize button inside an app (Chrome, Files…) freezes that app.
- **Why:** Hyprland ignores the app's minimize request and sends no event (checked on socket2: maximize sends `fullscreen>>1/0`, minimize sends nothing). The app thinks it's minimized and stops drawing.
- **Works today:** minimize from the side rail (click the app's icon), right-click → Minimize, or `Super + M`.
- **Ideas:** a small Hyprland plugin that catches the xdg-toplevel minimize request (the old `hych` plugin did this but was archived in 2024); or switch the compositor to labwc, which supports it natively.

---

# Solved — remember these for the install script

## Apps took ~25 s to open after a reboot (terminal, Telegram…)
- **Seen / fixed:** 2026-11-06
- **Cause:** apps wait for xdg-desktop-portal; outside GNOME the GNOME portal fails and they time out.
- **Fix:** `sudo apt install xdg-desktop-portal-hyprland xdg-desktop-portal-gtk` and
  `~/.config/xdg-desktop-portal/hyprland-portals.conf`:
  ```
  [preferred]
  default=hyprland;gtk
  org.freedesktop.impl.portal.FileChooser=gtk
  org.freedesktop.impl.portal.Settings=gtk
  ```

## Screen brightness keys / slider did nothing
- **Fix:** `sudo usermod -aG video $USER`, then reboot.

## Windows on top of a maximized window looked frozen; maximized windows couldn't be dragged
- **Cause:** Hyprland's own maximize (fullscreen 1) keeps floating windows above it.
- **Fix:** maximize the floating way — `scripts/max.sh`; app maximize buttons are caught in `WindowRules.qml`.

## Settings (gnome-control-center) didn't open
- **Fix:** it only starts when it thinks it's on GNOME → launched with `env XDG_CURRENT_DESKTOP=GNOME`;
  `install.sh` writes a copy of its launcher to `~/.local/share/applications/` with that prefix.

## New windows jumped (opened at one size, then resized)
- **Fix:** sizes moved from the shell (resizing after the window appeared) to static
  `windowrule … size … center on` rules in `hyprland.conf`, applied before the window is shown.

## Dragging a window by its own title bar did nothing
- **Cause (checked in the Hyprland 0.53 source):** `protocols/XDGShell.cpp` registers no handler for
  `xdg_toplevel.move` / `resize`, so apps' title-bar drags and edge resizes are ignored.
- **Fix:** `plugin/` (madar-csd) adds those handlers and starts Hyprland's own drag/resize; built by
  `install.sh` against `hyprland-dev`. Must be rebuilt after every Hyprland update (re-run `./install.sh`).
