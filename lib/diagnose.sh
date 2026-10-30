# Reads a failed step's log, explains the error in plain words and, where a
# safe fix is known, applies it so the step can be retried automatically.
#
# To teach it a new error: add a case to diagnose_log (pattern → hint, and
# optionally a fix function that returns 0 when it changed something).

DIAG_HINT=
DIAG_FIX=

fix_pacman_lock() {
  if pgrep -x pacman >/dev/null || pgrep -x yay >/dev/null || pgrep -x paru >/dev/null; then
    DIAG_HINT+=" Another package manager is still running; wait for it to finish."
    return 1
  fi
  sudo_run rm -f /var/lib/pacman/db.lck
}

fix_keyrings() {
  local rings=(archlinux-keyring)
  pacman -Qq cachyos-keyring >/dev/null 2>&1 && rings+=(cachyos-keyring)
  sudo_run pacman -Sy --noconfirm --needed "${rings[@]}" &&
    sudo_run pacman-key --populate "${rings[@]%-keyring}"
}

fix_mirrors() {
  if ! curl -sfI --max-time 10 https://archlinux.org >/dev/null; then
    DIAG_HINT+=" There is no internet connection right now; connect (nmtui or the network menu) and retry."
    return 1
  fi
  if have cachyos-rate-mirrors; then
    sudo_run cachyos-rate-mirrors
  elif have reflector; then
    sudo_run reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
  else
    return 1
  fi
  sudo_run pacman -Syy
}

fix_sync_db() { sudo_run pacman -Syy; }

fix_stale_yay_cache() { run rm -rf "$HOME/.cache/yay"; }

# diagnose_log <logfile>: sets DIAG_HINT (explanation) and DIAG_FIX (function name or empty).
diagnose_log() {
  local log=$1 tail
  DIAG_HINT= DIAG_FIX=
  tail=$(tail -n 200 "$log" 2>/dev/null)

  case $tail in
    *"unable to lock database"*|*"db.lck"*)
      DIAG_HINT="pacman's lock file is left over from an earlier run that was interrupted."
      DIAG_FIX=fix_pacman_lock ;;
    *"invalid or corrupted package (PGP signature)"*|*"unknown trust"*|*"could not be looked up remotely"*|*"key "*" is unknown"*|*"signature is invalid"*)
      DIAG_HINT="Package signatures don't match the installed keyrings (common on an older install ISO)."
      DIAG_FIX=fix_keyrings ;;
    *"failed retrieving file"*"404"*)
      DIAG_HINT="The package database is older than the mirror (the file was replaced by a newer version); a refresh usually fixes it."
      DIAG_FIX=fix_sync_db ;;
    *"failed retrieving file"*|*"Could not resolve host"*|*"failed to synchronize all databases"*|*"Operation too slow"*|*"Connection timed out"*)
      DIAG_HINT="Downloads failed: either the network is down or a mirror is slow/broken."
      DIAG_FIX=fix_mirrors ;;
    *"exists in filesystem"*)
      local file owner
      file=$(grep -m1 -oE '[^ ]+ exists in filesystem' <<<"$tail" | awk '{print $1}' | sed 's/^[^:]*: //')
      owner=$(pacman -Qo "$file" 2>/dev/null)
      DIAG_HINT="A package wants to install a file that already exists: $file. ${owner:-No package owns it, so it was created by hand or by another installer.} Move it aside and retry."
      ;;
    *"are in conflict"*)
      DIAG_HINT="Two packages conflict: $(grep -m1 'are in conflict' <<<"$tail"). Remove the line for one of them from packages/*.txt, or uninstall the old one."
      ;;
    *"No space left on device"*)
      DIAG_HINT="The disk is full. Free space (sudo pacman -Sc, or delete old snapper snapshots) and retry."
      ;;
    *"==> ERROR: A failure occurred in build()"*|*"==> ERROR: A failure occurred in package()"*|*"Failed to install the following packages"*)
      DIAG_HINT="An AUR package failed to build. This is usually an upstream problem; the step continues without it and lists it at the end."
      DIAG_FIX=fix_stale_yay_cache ;;
    *"sha256"*"mismatch"*|*"checksum"*"FAILED"*)
      DIAG_HINT="A downloaded file didn't match its checksum (partial download or a release published mid-run)."
      DIAG_FIX=fix_sync_db ;;
    *"Permission denied"*)
      DIAG_HINT="Something tried to write where it isn't allowed. If a file in your home is owned by root, fix it with: sudo chown -R $USER: <path>"
      ;;
    *"Hyprland"*"config"*"error"*)
      DIAG_HINT="Hyprland rejected the config. Run: Hyprland --verify-config -c ~/.config/hypr/hyprland.lua  — the first error shows the file and line."
      ;;
    *)
      DIAG_HINT="No known cause matched. The last lines of the log above show the real error."
      ;;
  esac
}
