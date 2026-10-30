# desc: Hibernate: swap file on disk, resume from GRUB, lid and low-battery behaviour

[[ ${HIBERNATE:-y} == y ]] || { info "Hibernate skipped (you chose no)"; return 0; }
[[ -f /sys/power/image_size ]] || { warn "This kernel/firmware doesn't support hibernation; skipped."; return 0; }
[[ $(findmnt -no FSTYPE /) == btrfs ]] || { warn "Hibernate setup only handles a Btrfs root (CachyOS default); skipped."; return 0; }

SWAP_SUBVOL=/swap
SWAP_FILE=/swap/swapfile
GRUB_DROPIN=/etc/default/grub.d/90-omarchy-on-cachyos-resume.cfg
size_gb=${HIBERNATE_SIZE_GB:-20}
# Read-only root checks; a dry run without a cached password just treats them as "not there yet".
as_root_check() { if (( DRY_RUN )); then sudo -n "$@" 2>/dev/null; else sudo "$@"; fi; }

# 1. Swap file in its own subvolume: snapper can't snapshot a subvolume that
#    holds an active swap file, and nested subvolumes stay out of snapshots.
if ! as_root_check btrfs subvolume show "$SWAP_SUBVOL" >/dev/null 2>&1; then
  [[ -e $SWAP_SUBVOL ]] && die "$SWAP_SUBVOL exists but isn't a Btrfs subvolume; move it aside and retry."
  free_gb=$(df -BG --output=avail / | tail -1 | tr -dc 0-9)
  (( free_gb - size_gb >= 10 )) ||
    die "A ${size_gb} GB swap file would leave only $(( free_gb - size_gb )) GB free on /. Free space or answer a smaller size (./setup.sh --reconfigure)."
  sudo_run btrfs subvolume create "$SWAP_SUBVOL"
fi
if ! as_root_check swaplabel "$SWAP_FILE" >/dev/null 2>&1; then
  sudo_run btrfs filesystem mkswapfile --size "${size_gb}g" "$SWAP_FILE"
fi
if ! grep -q "^$SWAP_FILE[[:space:]]" /etc/fstab; then
  sudo_run cp -a /etc/fstab "$RUN_DIR/fstab.before"
  printf '\n# Swap file for hibernation (omarchy-on-cachyos). zram (priority 100) is used first.\n%s none swap defaults,pri=0 0 0\n' "$SWAP_FILE" |
    sudo_write_append /etc/fstab
fi
swapon --show=NAME --noheadings | grep -qx "$SWAP_FILE" || sudo_run swapon -p 0 "$SWAP_FILE"
ok "Swap file: $SWAP_FILE (${size_gb} GB, used only after zram)"

# 2. Tell the kernel where the image is. The initramfs uses the systemd hook,
#    which resumes on its own once resume= is on the command line.
uuid=$(findmnt -no UUID /)
offset=$( (( DRY_RUN )) && echo '<offset>' || sudo btrfs inspect-internal map-swapfile -r "$SWAP_FILE")
[[ -n $offset ]] || die "Could not read the swap file's offset (btrfs inspect-internal map-swapfile)."
grep -q '\bsystemd\b' <(grep '^HOOKS=' /etc/mkinitcpio.conf) ||
  warn "mkinitcpio HOOKS don't include 'systemd'; add the 'resume' hook after 'filesystems' and rebuild (sudo mkinitcpio -P)."
want="GRUB_CMDLINE_LINUX_DEFAULT=\"\${GRUB_CMDLINE_LINUX_DEFAULT} resume=UUID=$uuid resume_offset=$offset\""
if ! grep -qxF "$want" "$GRUB_DROPIN" 2>/dev/null; then
  printf '# Written by omarchy-on-cachyos: resume from the hibernation swap file.\n%s\n' "$want" |
    sudo_write "$GRUB_DROPIN"
  sudo_run grub-mkconfig -o /boot/grub/grub.cfg
  ok "GRUB: resume=UUID=$uuid resume_offset=$offset"
fi

# 3. Omarchy's sleep hooks, and the marker its menu checks before offering Hibernate.
for hook in keyboard-backlight unmount-fuse; do
  src="$OMARCHY_HOME/default/systemd/system-sleep/$hook"
  [[ -f $src ]] && ! cmp -s "$src" "/usr/lib/systemd/system-sleep/$hook" &&
    sudo_run install -D -m 755 "$src" "/usr/lib/systemd/system-sleep/$hook"
done
if [[ ! -f /etc/mkinitcpio.conf.d/omarchy_resume.conf ]]; then
  # Omarchy's menu shows Hibernate when this file exists. Its own setup puts
  # HOOKS+=(resume) here; with CachyOS's systemd initramfs that hook isn't needed,
  # so this copy only carries a comment.
  echo '# Hibernation is set up by omarchy-on-cachyos (systemd initramfs resumes on its own).' |
    sudo_write /etc/mkinitcpio.conf.d/omarchy_resume.conf
fi

# 4. Lid / low battery behaviour, only once hibernation really works:
#    suspend-then-hibernate with no working hibernate would make the lid do nothing.
can=$(busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanSuspendThenHibernate 2>/dev/null)
if [[ $can == *yes* ]] || (( DRY_RUN )); then
  while IFS= read -r -d '' f; do
    dest=/${f#$REPO_DIR/system/files/hibernate/}
    cmp -s "$f" "$dest" 2>/dev/null || sudo_run install -D -m 644 "$f" "$dest"
  done < <(find "$REPO_DIR/system/files/hibernate" -type f -print0)
  sudo_run systemctl reload systemd-logind
  sudo_run systemctl try-restart upower.service
  ok "Lid on battery: suspend, then hibernate after 3 h. Critical battery: hibernate."
else
  warn "Hibernate isn't usable until after a reboot, so the lid/battery settings weren't switched yet. Reboot, then run: ./setup.sh --only hibernate"
fi
