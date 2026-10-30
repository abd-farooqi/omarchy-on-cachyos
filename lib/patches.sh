# Runs patches/*.sh. Each patch file defines:
#   PATCH_FILE          the file it changes
#   patch_needed        true when this system still needs the fix
#   patch_applied       true when the fix is already in PATCH_FILE
#   patch_applicable    true when the code the patch edits is still there
#   patch_apply         makes the change
#
# Prints one line per patch; returns 1 only if a needed patch could not be applied.

# patch_status <patch file>: prints applied | not-needed | missing-file | outdated | pending
patch_status() (
  source "$1"
  [[ -f $PATCH_FILE ]] || { echo missing-file; exit; }
  patch_applied && { echo applied; exit; }
  patch_needed || { echo not-needed; exit; }
  patch_applicable || { echo outdated; exit; }
  echo pending
)

patch_title() { sed -n '1s/^# *//p' "$1"; }

apply_patches() {
  local p name status failed=0
  for p in "$REPO_DIR"/patches/*.sh; do
    name=$(basename "$p" .sh)
    status=$(patch_status "$p")
    case $status in
      applied)      ok "patch $name: in place" ;;
      not-needed)   ok "patch $name: not needed on this system any more" ;;
      missing-file) warn "patch $name: the file it fixes no longer exists (Omarchy renamed or removed it). Check if the fix is still needed." ;;
      outdated)
        warn "patch $name: Omarchy changed the code this patch edits, so it was NOT applied. $(patch_title "$p")"
        failed=1 ;;
      pending)
        if (( DRY_RUN )); then
          info "patch $name: would apply"
        elif ( source "$p"; backup_path "$PATCH_FILE"; patch_apply && patch_applied ); then
          ok "patch $name: applied"
        else
          warn "patch $name: applying failed; the file was put back as Omarchy shipped it."
          ( source "$p"; [[ -f $RUN_DIR/backup$PATCH_FILE ]] && cp -a "$RUN_DIR/backup$PATCH_FILE" "$PATCH_FILE" )
          failed=1
        fi ;;
    esac
  done
  return "$failed"
}
