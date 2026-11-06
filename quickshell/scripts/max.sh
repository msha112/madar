#!/usr/bin/env bash
# Madar — maximize / restore a window the "floating" way.
# Hyprland's own maximize puts the window in a special layer, so other windows
# stay stuck on top of it and it can't be dragged. Instead we keep every window
# floating and just size it to fill the space next to the rail.
#   max.sh toggle [address]   maximize, or restore the size it had before
#   max.sh on     [address]
#   max.sh off    [address]
#   max.sh forget [address]   drop the saved size (after snapping it elsewhere)
#   max.sh fromapp            an app pressed its own maximize button

mode="${1:-toggle}"
addr="$2"
rail=64
state="${XDG_RUNTIME_DIR:-/tmp}/madar-max"
mkdir -p "$state"

if [ -n "$addr" ]; then
  win="$(hyprctl -j clients | jq --arg a "$addr" '.[] | select(.address == $a)')"
else
  win="$(hyprctl -j activewindow)"
fi
addr="$(jq -r '.address // empty' <<<"$win")"
[ -n "$addr" ] || exit 0
t="address:$addr"
file="$state/$addr"

if [ "$mode" = "forget" ]; then rm -f "$file"; exit 0; fi

fs="$(jq -r '.fullscreen' <<<"$win")"

# "fromapp": the app's own maximize button (Hyprland marks it as maximized = 1).
# Real fullscreen (videos, F11) is left alone.
if [ "$mode" = "fromapp" ]; then
  [ "$fs" = "1" ] || exit 0
  mode=toggle
fi

# Real (Hyprland) maximize → leave it first
if [ "$fs" = "1" ]; then
  hyprctl --batch "dispatch focuswindow $t ; dispatch fullscreen 1" >/dev/null
  win="$(hyprctl -j clients | jq --arg a "$addr" '.[] | select(.address == $a)')"
fi

read -r mx my mw mh < <(hyprctl -j monitors | jq -r --argjson m "$(jq '.monitor' <<<"$win")" '
  .[] | select(.id == $m) | [ .x, .y, ((.width / .scale) | floor), ((.height / .scale) | floor) ] | @tsv')
[ -n "$mw" ] || exit 0

fx=$(( mx + rail )); fy=$my; fw=$(( mw - rail )); fh=$mh
read -r cx cy cw ch < <(jq -r '[.at[0], .at[1], .size[0], .size[1]] | @tsv' <<<"$win")

is_max=0
if [ $(( cx - fx )) -ge -4 ] && [ $(( cx - fx )) -le 4 ] && [ "$cw" -ge $(( fw - 4 )) ] && [ "$ch" -ge $(( fh - 4 )) ]; then
  is_max=1
fi

case "$mode" in
  toggle) [ "$is_max" = 1 ] && mode=off || mode=on ;;
esac

if [ "$mode" = "on" ]; then
  [ "$is_max" = 1 ] && exit 0
  printf '%s %s %s %s\n' "$cx" "$cy" "$cw" "$ch" > "$file"
  hyprctl --batch "dispatch setfloating $t ; dispatch resizewindowpixel exact $fw $fh,$t ; dispatch movewindowpixel exact $fx $fy,$t ; dispatch focuswindow $t ; dispatch alterzorder top,$t" >/dev/null
else
  if [ -s "$file" ]; then
    read -r x y w h < "$file"
  else
    w=$(( fw * 62 / 100 )); h=$(( fh * 72 / 100 ))
    x=$(( fx + (fw - w) / 2 )); y=$(( fy + (fh - h) / 2 ))
  fi
  rm -f "$file"
  hyprctl --batch "dispatch resizewindowpixel exact $w $h,$t ; dispatch movewindowpixel exact $x $y,$t" >/dev/null
fi
