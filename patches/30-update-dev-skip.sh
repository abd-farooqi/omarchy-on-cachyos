# `omarchy update` calls omarchy-update-dev, which errors out because this
# Omarchy tree is not a git checkout. Make it skip instead; the tree is
# updated with `./setup.sh update` from this repo.
PATCH_FILE="$OMARCHY_BIN/omarchy-update-dev"

patch_needed()     { ! git -C "$OMARCHY_HOME" rev-parse --is-inside-work-tree >/dev/null 2>&1; }
patch_applied()    { grep -q 'Skipping Omarchy tree update' "$PATCH_FILE"; }
patch_applicable() { grep -q 'Error: OMARCHY_PATH is not a git checkout' "$PATCH_FILE"; }
patch_apply() {
  perl -0pi -e 's/  echo "Error: OMARCHY_PATH is not a git checkout: \$OMARCHY_PATH" >&2\n  exit 1/  # Local patch (omarchy-on-cachyos): this tree is updated by `setup.sh update`.\n  echo "Skipping Omarchy tree update: \$OMARCHY_PATH is not a git checkout (use omarchy-on-cachyos: setup.sh update)." >&2\n  exit 0/' "$PATCH_FILE"
}
