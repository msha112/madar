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
    hyprland quickshell ptyxis
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    fonts-inter fonts-jetbrains-mono fonts-noto-core fonts-noto-color-emoji
    grim slurp wl-clipboard cliphist jq curl
    brightnessctl playerctl wlsunset
    loupe git
  )
  sudo apt install -y "${pkgs[@]}"
  ok "packages installed"

  # ── Office: OnlyOffice + fonts that match Windows ─────────
  say "Installing OnlyOffice and Office fonts"
  oo_key=/usr/share/keyrings/onlyoffice.gpg
  if [ ! -s "$oo_key" ]; then
    tmpkey="$(mktemp -d)"
    if gpg --no-default-keyring --keyring "gnupg-ring:$tmpkey/onlyoffice.gpg" \
           --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys CB2DE8E5 >/dev/null 2>&1; then
      sudo install -m 644 -o root -g root "$tmpkey/onlyoffice.gpg" "$oo_key"
    else
      curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE | sudo gpg --dearmor -o "$oo_key"
      sudo chmod 644 "$oo_key"
    fi
    rm -rf "$tmpkey"
  fi
  echo "deb [signed-by=$oo_key] https://download.onlyoffice.com/repo/debian squeeze main" \
    | sudo tee /etc/apt/sources.list.d/onlyoffice.list >/dev/null

  # Microsoft's free core fonts (Arial, Times New Roman, Courier New, Verdana…) — accept the licence up front
  echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" \
    | sudo debconf-set-selections
  sudo apt update
  office_pkgs=(
    onlyoffice-desktopeditors
    ttf-mscorefonts-installer
    fonts-crosextra-carlito fonts-crosextra-caladea fonts-liberation fonts-dejavu
    fonts-hosny-amiri fonts-sil-scheherazade
  )
  have=()
  for p in "${office_pkgs[@]}"; do
    if apt-cache policy "$p" 2>/dev/null | grep -q "Candidate: [0-9]"; then have+=("$p")
    else warn "package $p not found — skipped"; fi
  done
  sudo apt install -y "${have[@]}"
  ok "OnlyOffice and fonts installed"

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

# Office: font tool, "New Document" templates, OnlyOffice defaults
mkdir -p "$HOME/.local/bin"
cp -a "$here/bin/madar-fonts" "$HOME/.local/bin/madar-fonts"
chmod +x "$HOME/.local/bin/madar-fonts"

templates="$(xdg-user-dir TEMPLATES 2>/dev/null || true)"
{ [ -z "$templates" ] || [ "$templates" = "$HOME" ]; } && templates="$HOME/Templates"
mkdir -p "$templates"
for t in "$here/office/templates/"*; do
  [ -e "$templates/$(basename "$t")" ] || cp -a "$t" "$templates/"
done

# Only adds settings you haven't chosen yourself — never overwrites them.
#   UITheme=theme-system  → light/dark follows Madar's day/night
oo_conf="$HOME/.config/onlyoffice/DesktopEditors.conf"
mkdir -p "$(dirname "$oo_conf")"
touch "$oo_conf"
if ! grep -q '^\[General\]' "$oo_conf"; then
  { printf '[General]\n'; cat "$oo_conf"; } > "$oo_conf.new" && mv "$oo_conf.new" "$oo_conf"
fi
for kv in "UITheme=theme-system" "locale=en-US"; do
  grep -q "^${kv%%=*}=" "$oo_conf" || sed -i "/^\[General\]/a $kv" "$oo_conf"
done
ok "OnlyOffice settings, templates and madar-fonts in place"
[ -d "$backup" ] && ok "old configs saved in ~/${backup#"$HOME"/}"

# ── 3. Desktop settings ──────────────────────────────────────
say "Desktop settings"
fc-cache -f >/dev/null 2>&1 || true
gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close' || true
xdg-mime default org.gnome.Loupe.desktop image/png image/jpeg image/webp image/gif image/bmp image/svg+xml || true
if [ -f /usr/share/applications/onlyoffice-desktopeditors.desktop ]; then
  xdg-mime default onlyoffice-desktopeditors.desktop \
    application/vnd.openxmlformats-officedocument.wordprocessingml.document \
    application/msword application/rtf application/vnd.oasis.opendocument.text \
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet \
    application/vnd.ms-excel text/csv application/vnd.oasis.opendocument.spreadsheet \
    application/vnd.openxmlformats-officedocument.presentationml.presentation \
    application/vnd.ms-powerpoint application/vnd.oasis.opendocument.presentation || true
  ok "Word, Excel and PowerPoint files open in OnlyOffice"
fi
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
echo "  Have Windows? Run  madar-fonts  to copy its fonts, so Office files look identical."
