# Quickshell finds its running instance by the literal config path. Omarchy's
# config falls back to /usr/share/omarchy, which is a symlink here, so the bar
# and the omarchy-shell CLI could disagree on the path and stop talking.
# Fix: resolve OMARCHY_PATH to the real path before launching.
PATCH_FILE="$OMARCHY_BIN/omarchy-launch-shell"

patch_needed()     { [[ $(realpath -m /usr/share/omarchy) != /usr/share/omarchy ]]; }
patch_applied()    { grep -q 'realpath -m "${OMARCHY_PATH' "$PATCH_FILE"; }
patch_applicable() { grep -q '^run_shell() {' "$PATCH_FILE"; }
patch_apply() {
  perl -0pi -e 's/^run_shell\(\) \{/# Local patch (omarchy-on-cachyos): canonicalize the install path so every\n# launcher and the omarchy-shell CLI agree on the Quickshell config path.\nOMARCHY_PATH="\$(realpath -m "\$\{OMARCHY_PATH:-\$HOME\/.local\/share\/omarchy\}")"\nexport OMARCHY_PATH\n\nrun_shell() {/m' "$PATCH_FILE"
}
