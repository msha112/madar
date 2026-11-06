#!/usr/bin/env bash
# Madar — screenshots
#   screenshot.sh region   pick an area (Print, Super+Shift+S)
#   screenshot.sh window   the window in front (Ctrl+Print)
#   screenshot.sh full     the whole screen (Shift+Print)
# Saves to ~/Pictures/Screenshots, copies to the clipboard, shows a notification.

mode="${1:-region}"
pics="$(xdg-user-dir PICTURES 2>/dev/null)"; [ -d "$pics" ] || pics="$HOME/Pictures"
dir="$pics/Screenshots"
mkdir -p "$dir"
file="$dir/Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"

case "$mode" in
  region)
    geom="$(slurp -d -b 0b0d1288 -c e8a33dff -s 00000000 -w 2)" || exit 0
    sleep 0.25   # let the selection overlay fade out first
    grim -g "$geom" "$file" ;;
  window)
    geom="$(hyprctl -j activewindow | jq -r 'if .at then "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])" else empty end')"
    [ -n "$geom" ] || exit 0
    grim -g "$geom" "$file" ;;
  full)
    mon="$(hyprctl -j monitors | jq -r '.[] | select(.focused) | .name')"
    grim -o "$mon" "$file" ;;
  *) echo "usage: $0 region|window|full" >&2; exit 2 ;;
esac || exit 1

wl-copy --type image/png < "$file"

# Notification with the picture: click it (or "Open") to view, or "Show in folder"
(
  act="$(timeout 300 notify-send -a "Screenshot" -i "$file" -h "string:image-path:$file" \
          --action=default="Open" --action=open="Open" --action=folder="Show in folder" \
          "Screenshot saved" "Copied to clipboard")"
  case "$act" in
    default|open) xdg-open "$file" ;;
    folder) xdg-open "$dir" ;;
  esac
) >/dev/null 2>&1 &
