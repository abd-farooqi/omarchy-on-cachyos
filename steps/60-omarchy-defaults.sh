# desc: Put Omarchy's default user files in place (configs, fonts, icons, services)

EXTRACT="$CACHE_DIR/extract"
[[ -d $EXTRACT/omarchy-settings ]] || die "Omarchy's package files are missing from $EXTRACT. Run the omarchy-core step first: ./setup.sh --only omarchy-core"

# Default configs (what /etc/skel gives a new Omarchy user). Existing files are
# never overwritten here; your own versions are applied in the next step.
for pkg in omarchy omarchy-settings; do
  skel="$EXTRACT/$pkg/etc/skel"
  [[ -d $skel ]] || continue
  run cp -a --update=none "$skel/." "$HOME/"
done
ok "Omarchy default configs added (existing files left alone)"

share="$EXTRACT/omarchy-settings/usr/share"
if [[ -d $share/fonts ]]; then
  run mkdir -p "$HOME/.local/share/fonts"
  run cp -a "$share/fonts/." "$HOME/.local/share/fonts/"
fi
if [[ -d $share/icons ]]; then
  run mkdir -p "$HOME/.local/share/icons"
  run cp -a "$share/icons/." "$HOME/.local/share/icons/"
fi
for conf in "$share"/fontconfig/conf.avail/*.conf; do
  [[ -f $conf ]] && install_file "$conf" "$HOME/.config/fontconfig/conf.d/$(basename "$conf")"
done
have fc-cache && run fc-cache -f >/dev/null

# Omarchy's user services call /usr/bin/omarchy-*; here they live in ~/.local/bin.
unit_dir="$HOME/.config/systemd/user"
run mkdir -p "$unit_dir"
# They are only installed here; 80-system enables the ones this setup uses.
declare -A seen=()
for unit in "$EXTRACT"/omarchy-settings/usr/lib/systemd/user/*.service "$OMARCHY_HOME"/default/systemd/user/*.service; do
  [[ -f $unit && -z ${seen[$(basename "$unit")]:-} ]] || continue
  seen[$(basename "$unit")]=1
  dest="$unit_dir/$(basename "$unit")"
  if (( DRY_RUN )); then
    echo "  unit $(basename "$unit")"
  else
    sed "s|/usr/bin/omarchy|%h/.local/bin/omarchy|g" "$unit" >"$dest.new"
    if cmp -s "$dest.new" "$dest"; then rm "$dest.new"; else backup_path "$dest"; mv "$dest.new" "$dest"; fi
  fi
done

# Skip Omarchy's first-run provisioning: it would set Chromium as the default
# browser and run installer hooks meant for a full Omarchy install.
run mkdir -p "$HOME/.local/state/omarchy/done"
for marker in first-run-user finalize-user; do
  [[ -f $HOME/.local/state/omarchy/done/$marker ]] || run touch "$HOME/.local/state/omarchy/done/$marker"
done
ok "Omarchy defaults in place"
