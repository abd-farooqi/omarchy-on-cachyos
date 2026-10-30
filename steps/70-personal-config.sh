# desc: Apply your own configs on top of Omarchy's (hypr, bar, kitty, fish, ...)

# CachyOS's own Hyprland setup (hyprland.lua + config/) is replaced by
# Omarchy's; move its leftovers into the run backup so nothing stale loads.
for leftover in "$HOME/.config/hypr/config" "$HOME/.config/hypr/hyprland.conf"; do
  if [[ -e $leftover ]]; then
    backup_path "$leftover"
    run rm -rf "$leftover"
    info "Moved CachyOS's ${leftover/#$HOME/\~} into the backup"
  fi
done

# Every file under overrides/home replaces the one in $HOME (old one backed up).
src="$REPO_DIR/overrides/home"
while IFS= read -r -d '' f; do
  install_file "$f" "$HOME/${f#$src/}"
done < <(find "$src" -type f -print0)

# Templates are filled with your answers.
export KB_LAYOUT KB_VARIANT KB_OPTIONS MONITOR_OUTPUT MONITOR_SCALE BROWSER_CMD GIT_NAME GIT_EMAIL
tsrc="$REPO_DIR/templates"
while IFS= read -r -d '' t; do
  dest="$HOME/${t#$tsrc/}"; dest=${dest%.tmpl}
  tmp=$(mktemp)
  render_template "$t" >"$tmp"
  install_file "$tmp" "$dest"
  rm -f "$tmp"
done < <(find "$tsrc" -type f -name '*.tmpl' -print0)

if [[ $DISCORD_AUTOSTART == y ]]; then
  osrc="$REPO_DIR/optional/discord-autostart"
  while IFS= read -r -d '' f; do install_file "$f" "$HOME/${f#$osrc/}"; done < <(find "$osrc" -type f -print0)
fi

# Third-party bar plugin, kept up to date from its own repo.
slack_dir="$HOME/.config/omarchy/plugins/petrzpav.slack"
if grep -q '"petrzpav.slack"' "$HOME/.config/omarchy/shell.json" 2>/dev/null; then
  if [[ -d $slack_dir/.git ]]; then
    run git -C "$slack_dir" pull --ff-only -q || warn "Could not update the Slack bar plugin (local changes?)"
  else
    retry 3 run git clone -q https://github.com/petrzpav/omarchy-slack.git "$slack_dir" ||
      warn "Could not download the Slack bar plugin; the bar will show without it."
  fi
  [[ -x $slack_dir/install.sh ]] && { run "$slack_dir/install.sh" || warn "The Slack plugin's install.sh failed"; }
fi

# Git identity
gitconf="$HOME/.config/git/config"
run mkdir -p "$(dirname "$gitconf")"
[[ -n $GIT_NAME ]]  && run git config --file "$gitconf" user.name "$GIT_NAME"
[[ -n $GIT_EMAIL ]] && run git config --file "$gitconf" user.email "$GIT_EMAIL"

# Default browser
if [[ -n $BROWSER_DESKTOP ]]; then
  if [[ -f /usr/share/applications/$BROWSER_DESKTOP || -f $HOME/.local/share/applications/$BROWSER_DESKTOP ]]; then
    run xdg-settings set default-web-browser "$BROWSER_DESKTOP" 2>/dev/null ||
      run xdg-mime default "$BROWSER_DESKTOP" x-scheme-handler/http x-scheme-handler/https text/html
  else
    warn "$BROWSER_DESKTOP is not installed, so it was not made the default browser."
  fi
fi

# Hyprland must accept the result; otherwise say exactly where it breaks.
if have Hyprland; then
  if out=$(Hyprland --verify-config -c "$HOME/.config/hypr/hyprland.lua" 2>&1) && grep -q 'config ok' <<<"$out"; then
    ok "Hyprland accepts the config"
  else
    printf '%s\n' "$out" | tail -n 20
    warn "Hyprland reported config errors (above). Your previous files are in $RUN_DIR/backup/"
  fi
fi
ok "Personal configs applied"
