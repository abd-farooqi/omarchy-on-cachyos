# desc: Omarchy's system settings that suit CachyOS (power button, sleep, shutdown)

list="$REPO_DIR/system/omarchy-settings-include.txt"
pkgroot="$CACHE_DIR/extract/omarchy-settings"

# Needs the omarchy-settings package unpacked; fetch it when run on its own.
if [[ ! -d $pkgroot/etc ]]; then
  file=$(omarchy_repo_fetch omarchy-settings)
  mkdir -p "$pkgroot"
  bsdtar -xf "$file" -C "$pkgroot"
fi

changed=0
install_root_file() { # <source> <dest> <mode>
  local src=$1 dest=$2 mode=$3
  if [[ -f $dest ]] && cmp -s "$src" "$dest" 2>/dev/null; then return 0; fi
  if [[ -e $dest ]]; then
    sudo_run mkdir -p "$RUN_DIR/backup$(dirname "$dest")"
    sudo_run cp -a "$dest" "$RUN_DIR/backup$dest"
  fi
  sudo_run install -D -m "$mode" "$src" "$dest"
  printf '  %s\n' "$dest"
  (( ++changed ))
}

while read -r rel; do
  src="$pkgroot/$rel"
  if [[ ! -f $src ]]; then
    warn "Omarchy no longer ships $rel; skipped (remove it from system/omarchy-settings-include.txt)"
    continue
  fi
  mode=644; [[ -x $src ]] && mode=755
  install_root_file "$src" "/$rel" "$mode"
done < <(sed 's/#.*//' "$list" | awk NF)

# Docker log rotation, only when there's no daemon.json yet (never overwrite one).
if pacman -Q docker >/dev/null 2>&1 && [[ ! -e /etc/docker/daemon.json ]]; then
  install_root_file "$REPO_DIR/system/files/etc/docker/daemon.json" /etc/docker/daemon.json 644
fi

if (( changed )); then
  sudo_run systemctl daemon-reload
  # Both reload in place: no logout, running apps untouched.
  sudo_run systemctl reload systemd-logind
  sudo_run systemctl reload-or-restart systemd-resolved
  ok "$changed system setting file(s) installed and loaded"
else
  ok "System settings already in place"
fi
