# desc: Take a snapper snapshot so the whole run can be rolled back
# always: yes

[[ ${SNAPSHOT:-y} == y ]] || { info "Snapshot skipped (you chose no)"; return 0; }

if have snapper && snapper list-configs 2>/dev/null | grep -q '^root\b'; then
  sudo_run snapper -c root create -t single -c number -d "before omarchy-on-cachyos ($(date '+%F %R'))"
  (( DRY_RUN )) || ok "Snapshot created. To roll back: pick it in the GRUB menu (CachyOS snapshots), or use btrfs-assistant."
else
  warn "snapper is not set up for / so no snapshot was taken. Backups of every replaced file are still kept in $RUN_DIR/backup."
fi
