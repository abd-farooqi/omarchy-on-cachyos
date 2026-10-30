#!/bin/bash
# Apply the current Omarchy theme to Qt (qt6ct), KDE apps (kdeglobals) and GTK.
# Inputs come from ~/.config/omarchy/themed/{qt6ct.conf,kdeglobals,gtk.css}.tpl.

THEME_DIR="$HOME/.local/state/omarchy/current/theme"

# Qt: colour scheme + icon theme.
QT6CT="$HOME/.config/qt6ct/qt6ct.conf"
if [[ -f $THEME_DIR/qt6ct.conf && -f $QT6CT ]]; then
  sed -i "s|^color_scheme_path=.*|color_scheme_path=$THEME_DIR/qt6ct.conf|" "$QT6CT"
  sed -i "s|^custom_palette=.*|custom_palette=true|" "$QT6CT"
fi

# Icons: use the theme's icon set when it's installed, otherwise breeze-dark.
icons=$(cat "$THEME_DIR/icons.theme" 2>/dev/null)
if [[ -z $icons ]] || ! [[ -d /usr/share/icons/$icons || -d $HOME/.local/share/icons/$icons ]]; then
  icons=breeze-dark
fi
gsettings set org.gnome.desktop.interface icon-theme "$icons"
[[ -f $QT6CT ]] && sed -i "s|^icon_theme=.*|icon_theme=$icons|" "$QT6CT"
kwriteconfig6 --file kdeglobals --group Icons --key Theme "$icons"

# KDE apps (Dolphin etc.): replace colour sections in kdeglobals, keep everything else.
if [[ -f $THEME_DIR/kdeglobals ]]; then
  python3 -I - "$THEME_DIR/kdeglobals" "$HOME/.config/kdeglobals" <<'PY'
import sys, os

def parse(path):
    sections, order, cur = {}, [], None
    if os.path.exists(path):
        for line in open(path):
            line = line.rstrip("\n")
            if line.startswith("[") and line.endswith("]"):
                cur = line
                if cur not in sections:
                    sections[cur] = []
                    order.append(cur)
            elif cur is not None and line.strip():
                sections[cur].append(line)
    return sections, order

new, new_order = parse(sys.argv[1])
old, old_order = parse(sys.argv[2])

for sec in new_order:
    if sec == "[General]" and sec in old:
        keys = {l.split("=", 1)[0] for l in new[sec]}
        old[sec] = [l for l in old[sec] if l.split("=", 1)[0] not in keys] + new[sec]
    else:
        if sec not in old:
            old_order.append(sec)
        old[sec] = new[sec]

with open(sys.argv[2], "w") as f:
    f.write("\n\n".join(s + "\n" + "\n".join(old[s]) for s in old_order) + "\n")
PY
fi
