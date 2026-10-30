# Some Quickshell versions don't support `quickshell kill -p <dir> --any-display`,
# so `omarchy restart shell` would leave the old bar running. Kill by instance
# id instead. Skipped automatically once Quickshell supports --any-display.
PATCH_FILE="$OMARCHY_BIN/omarchy-restart-shell"

patch_needed()     { ! quickshell kill --help 2>&1 | grep -q -- '--any-display'; }
patch_applied()    { grep -q 'quickshell kill -i "$instance_id"' "$PATCH_FILE"; }
patch_applicable() { grep -qF 'quickshell kill -p "$CONFIG_DIR" --any-display' "$PATCH_FILE"; }
patch_apply() {
  perl -0pi -e 's/^while timeout 30 quickshell kill -p "\$CONFIG_DIR" --any-display >\/dev\/null 2>&1; do :; done$/# Local patch (omarchy-on-cachyos): kill by instance id.\nwhile read -r instance_id; do\n  [[ -n \$instance_id ]] && timeout 30 quickshell kill -i "\$instance_id" >\/dev\/null 2>&1\ndone < <(quickshell list -a -j 2>\/dev\/null | jq -r --arg dir "\$CONFIG_DIR\/" \x27.[] | select(.config_path | startswith(\$dir)) | .id\x27 2>\/dev\/null)/m' "$PATCH_FILE"
  # Make sure the relaunched shell gets the home-directory OMARCHY_PATH.
  if grep -q "^hyprctl dispatch 'hl.dsp.exec_cmd(\"omarchy-launch-shell\")'" "$PATCH_FILE" &&
    ! grep -q 'hyprctl setenv OMARCHY_PATH' "$PATCH_FILE"; then
    perl -pi -e 's/^(hyprctl dispatch \x27hl\.dsp\.exec_cmd\("omarchy-launch-shell"\)\x27)/hyprctl setenv OMARCHY_PATH "\$session_omarchy_path" >\/dev\/null 2>&1 || true\n$1/' "$PATCH_FILE"
  fi
}
