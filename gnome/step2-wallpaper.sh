#!/usr/bin/env bash
# Madar on GNOME — step 2: Madar wallpaper (night/day follow the dark/light style)
# and the Extension Manager app for the next steps.
set -e
here="$(cd "$(dirname "$0")" && pwd)"
dest="$HOME/.local/share/backgrounds/madar"
mkdir -p "$dest"
cp "$here/wallpapers/madar-night.png" "$here/wallpapers/madar-day.png" "$dest/"

gsettings set org.gnome.desktop.background picture-uri      "file://$dest/madar-day.png"
gsettings set org.gnome.desktop.background picture-uri-dark "file://$dest/madar-night.png"
gsettings set org.gnome.desktop.background picture-options  'zoom'
gsettings set org.gnome.desktop.screensaver picture-uri     "file://$dest/madar-night.png"

if ! command -v extension-manager >/dev/null 2>&1; then
  sudo apt install -y gnome-shell-extension-manager
fi
echo "Done: wallpaper set, Extension Manager installed."
