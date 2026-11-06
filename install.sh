#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  Madar — installer for Ubuntu 26.04 (Hyprland + Quickshell)
#
#    ./install.sh            install / update everything
#    ./install.sh --files    only copy the config files (no apt, no sudo)
#
#  Safe to run again: existing configs are backed up to
#  ~/.config/madar-backup/<date>/ before anything is replaced.
#  Your saved choices (~/.local/state/madar.json) are never touched.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
only_files=0
[ "${1:-}" = "--files" ] && only_files=1

say()  { printf '\n\033[1;33m▸ %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[31m!\033[0m %s\n' "$*"; }

if [ "$(id -u)" = 0 ]; then
  echo "Run this as your normal user (not with sudo). It asks for your password when needed."
  exit 1
fi

# ── 1. Packages ──────────────────────────────────────────────
if [ "$only_files" = 0 ]; then
  say "Installing packages (asks for your password)"

  if ! apt-cache policy quickshell 2>/dev/null | grep -q "Candidate: [0-9]"; then
    sudo add-apt-repository -y ppa:avengemedia/danklinux
  fi
  sudo apt update

  pkgs=(
    hyprland quickshell kitty
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    fonts-inter fonts-jetbrains-mono fonts-noto-core fonts-noto-color-emoji
    grim slurp wl-clipboard cliphist jq curl
    brightnessctl playerctl wlsunset
    loupe git
  )
  sudo apt install -y "${pkgs[@]}"
  ok "packages installed"

  # Screen brightness needs the video group
  if ! id -nG "$USER" | grep -qw video; then
    sudo usermod -aG video "$USER"
    ok "added you to the 'video' group (brightness) — takes effect after a reboot"
  fi

  # WhiteSur icons (blue, yellow, green, orange — light & dark)
  if [ ! -d "$HOME/.local/share/icons/WhiteSur" ]; then
    say "Installing WhiteSur icons"
    tmp="$(mktemp -d)"
    git clone --depth=1 https://github.com/vinceliuice/WhiteSur-icon-theme.git "$tmp/WhiteSur-icon-theme"
    (cd "$tmp/WhiteSur-icon-theme" && ./install.sh -t default yellow green orange -a)
    rm -rf "$tmp"
    ok "icons installed"
  else
    ok "WhiteSur icons already installed"
  fi
fi

# ── 2. Config files (with backup) ────────────────────────────
say "Copying config files"
backup="$HOME/.config/madar-backup/$(date +%Y-%m-%d_%H-%M-%S)"

put() {   # put <source> <destination>
  local src="$1" dst="$2"
  if [ -e "$dst" ]; then
    mkdir -p "$backup/$(dirname "${dst#$HOME/}")"
    cp -a "$dst" "$backup/${dst#$HOME/}"
  fi
  mkdir -p "$(dirname "$dst")"
  cp -a "$src" "$dst"
}

put "$here/hypr/hyprland.conf"                              "$HOME/.config/hypr/hyprland.conf"
put "$here/config/fontconfig/fonts.conf"                    "$HOME/.config/fontconfig/fonts.conf"
put "$here/config/xdg-desktop-portal/hyprland-portals.conf" "$HOME/.config/xdg-desktop-portal/hyprland-portals.conf"

if [ -d "$HOME/.config/quickshell" ]; then
  mkdir -p "$backup/.config"
  cp -a "$HOME/.config/quickshell" "$backup/.config/quickshell"
fi
mkdir -p "$HOME/.config/quickshell"
cp -a "$here/quickshell/." "$HOME/.config/quickshell/"
chmod +x "$HOME/.config/quickshell/scripts/"*.sh
ok "configs in place"
[ -d "$backup" ] && ok "old configs saved in ~/${backup#"$HOME"/}"

# ── 3. Desktop settings ──────────────────────────────────────
say "Desktop settings"
fc-cache -f >/dev/null 2>&1 || true
gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close' || true
xdg-mime default org.gnome.Loupe.desktop image/png image/jpeg image/webp image/gif image/bmp image/svg+xml || true
ok "fonts, window buttons, image viewer"

# ── 4. Reload if we're inside Hyprland ───────────────────────
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  hyprctl reload >/dev/null 2>&1 || true
  pkill -x quickshell 2>/dev/null || true
  sleep 1
  hyprctl dispatch exec quickshell >/dev/null 2>&1 || true
  ok "Hyprland reloaded and the shell restarted"
fi

say "Done"
echo "  Log out, pick \"Hyprland\" from the gear on the login screen, and log in."
echo "  First time? Reboot once so the brightness permission takes effect."
