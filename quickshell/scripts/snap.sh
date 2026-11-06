#!/usr/bin/env bash
# Madar — window placement
#   snap.sh left | right          half of the screen (window in front)
#   snap.sh restore               back to its size before maximizing (or a centred size)
#   snap.sh medium  [address]     centred, medium size
#   snap.sh large   [address]     centred, large size
#   snap.sh center  [address]     centred, keeps its size
#   snap.sh max     [address]     maximized (fills the space next to the rail)
# Respects the side rail and the 12px gaps.

mode="${1:-left}"
addr="$2"
gap=12

if [ -n "$addr" ]; then
  win="$(hyprctl -j clients | jq --arg a "$addr" '.[] | select(.address == $a)')"
else
  win="$(hyprctl -j activewindow)"
fi
addr="$(jq -r '.address // empty' <<<"$win")"
[ -n "$addr" ] || exit 0
target="address:$addr"

here="$(dirname "$0")"
case "$mode" in
  max)     exec "$here/max.sh" on "$addr" ;;       # floating-style maximize
  restore) exec "$here/max.sh" off "$addr" ;;      # back to the size it had before
  left|right) "$here/max.sh" forget "$addr" ;;
esac

# leave fullscreen / maximized first
fs="$(jq -r '.fullscreen' <<<"$win")"
if [ "$fs" != "0" ] && [ "$fs" != "false" ]; then
  hyprctl --batch "dispatch focuswindow $target ; dispatch fullscreen 1" >/dev/null
  [ "$mode" = "restore" ] && exit 0
  win="$(hyprctl -j clients | jq --arg a "$addr" '.[] | select(.address == $a)')"
fi

read -r mx my mw mh rl rt rr rb < <(hyprctl -j monitors | jq -r '
  .[] | select(.focused)
  | [ .x, .y,
      ((.width / .scale) | floor), ((.height / .scale) | floor),
      .reserved[0], .reserved[1], .reserved[2], .reserved[3] ]
  | @tsv')

ax=$(( mx + rl + gap ))
ay=$(( my + rt + gap ))
aw=$(( mw - rl - rr - 2 * gap ))
ah=$(( mh - rt - rb - 2 * gap ))

case "$mode" in
  left)    w=$(( (aw - gap) / 2 )); h=$ah; x=$ax;                 y=$ay ;;
  right)   w=$(( (aw - gap) / 2 )); h=$ah; x=$(( ax + w + gap )); y=$ay ;;
  restore) w=$(( aw * 62 / 100 ));  h=$(( ah * 72 / 100 )) ;;
  medium)  w=$(( aw * 55 / 100 ));  h=$(( ah * 62 / 100 )) ;;
  large)   w=$(( aw * 70 / 100 ));  h=$(( ah * 80 / 100 )) ;;
  center)  w=$(jq -r '.size[0]' <<<"$win"); h=$(jq -r '.size[1]' <<<"$win") ;;
  *) echo "usage: $0 left|right|restore|medium|large|center|max [address]" >&2; exit 2 ;;
esac
case "$mode" in
  restore|medium|large|center) x=$(( ax + (aw - w) / 2 )); y=$(( ay + (ah - h) / 2 )) ;;
esac

hyprctl --batch "dispatch setfloating $target ; dispatch resizewindowpixel exact $w $h,$target ; dispatch movewindowpixel exact $x $y,$target" >/dev/null
