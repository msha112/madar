#!/usr/bin/env bash
# Madar on GNOME — step 3: a small shell theme on top of Ubuntu's own (Yaru)
#   · floating, rounded, see-through top bar
#   · rounder menus and quick settings
# Needs the "User Themes" extension. The script prints the undo command at the end.
set -e

theme="$HOME/.local/share/themes/Madar/gnome-shell"
mkdir -p "$theme"

# Start from the theme Ubuntu uses now, so everything else stays exactly as it is
base=""
for f in /usr/share/themes/Yaru-dark/gnome-shell/gnome-shell.css \
         /usr/share/themes/Yaru/gnome-shell/gnome-shell.css; do
  [ -f "$f" ] && { base="file://$f"; break; }
done
if [ -z "$base" ]; then
  res=/usr/share/gnome-shell/gnome-shell-theme.gresource
  css="$(gresource list "$res" 2>/dev/null | grep -E '/gnome-shell(-dark)?\.css$' | sort -r | head -1)"
  [ -n "$css" ] && base="resource://$css"
fi
if [ -z "$base" ]; then
  echo "Couldn't find Ubuntu's shell theme — nothing changed."; exit 1
fi
echo "Base theme: $base"

cat > "$theme/gnome-shell.css" <<CSS
/* Madar — GNOME Shell theme (only the differences from the base theme) */
@import url("$base");

/* Floating, rounded, see-through top bar */
#panel {
  margin: 8px 10px 0 10px;
  border-radius: 14px;
  background-color: rgba(18, 22, 29, 0.72);
  height: 34px;
}
#panel .panel-button {
  border-radius: 10px;
}
#panel.unlock-screen,
#panel.login-screen,
#panel:overview {
  background-color: transparent;
}

/* Rounder menus and quick settings */
.popup-menu-content,
.candidate-popup-content {
  border-radius: 16px;
}
.quick-settings {
  border-radius: 22px;
}
.quick-toggle {
  border-radius: 14px;
}
.message-list,
.datemenu-popover {
  border-radius: 16px;
}
CSS

# User Themes installed from Extension Manager keeps its settings schema inside the extension
gs=(gsettings)
if ! gsettings list-schemas | grep -qx org.gnome.shell.extensions.user-theme; then
  dir="$(ls -d "$HOME"/.local/share/gnome-shell/extensions/user-theme@*/schemas 2>/dev/null | head -1)"
  if [ -z "$dir" ]; then
    echo "User Themes isn't installed — install it from Extension Manager, then run this again."; exit 1
  fi
  gs=(gsettings --schemadir "$dir")
fi
"${gs[@]}" set org.gnome.shell.extensions.user-theme name 'Madar'
echo "Done: Madar shell theme on. Undo with:"
echo "  ${gs[*]} reset org.gnome.shell.extensions.user-theme name"
