# Package installation that survives renamed/removed packages.
#
# Each name is resolved in order: CachyOS/Arch repos → Omarchy repo → AUR.
# Anything that can't be found or fails to install becomes a warning instead
# of stopping the run, and is listed in the final summary.

AUR_HELPER=

# Lines from package list files, without comments or blanks.
read_pkg_list() {
  local f
  for f; do
    [[ -f $f ]] || { warn "Package list not found: $f"; continue; }
    sed -e 's/#.*//' "$f" | awk 'NF { print $1 }'
  done
}

detect_aur_helper() {
  if have yay; then AUR_HELPER=yay
  elif have paru; then AUR_HELPER=paru
  else AUR_HELPER=
  fi
}

ensure_aur_helper() {
  detect_aur_helper
  [[ -n $AUR_HELPER ]] && return 0
  info "No AUR helper found; installing yay from the CachyOS repos"
  sudo_run pacman -S --needed --noconfirm yay || sudo_run pacman -S --needed --noconfirm paru ||
    { warn "Could not install yay or paru; AUR packages will be skipped."; return 1; }
  (( DRY_RUN )) && AUR_HELPER=yay || detect_aur_helper
}

aur_install() {
  case $AUR_HELPER in
    yay)  run yay -S --needed --noconfirm --answerdiff None --answerclean None --removemake --sudoloop "$@" ;;
    paru) run paru -S --needed --noconfirm --skipreview --removemake --sudoloop "$@" ;;
    *)    return 1 ;;
  esac
}

# Prints the names (from the arguments) that exist in the AUR, in one request.
aur_filter_existing() {
  (( $# )) || return 0
  local query p
  for p; do query+="&arg[]=$(jq -rn --arg v "$p" '$v|@uri')"; done
  curl -fsS --max-time 30 "https://aur.archlinux.org/rpc/v5/info?${query#&}" 2>/dev/null |
    jq -r '.results[].Name' 2>/dev/null
}

record_pkg_failure() {
  local pkg=$1 why=$2
  [[ -n ${RUN_DIR:-} ]] && printf '%s\t%s\n' "$pkg" "$why" >>"$RUN_DIR/package-failures.tsv"
  warn "Package $pkg: $why"
}

# install_packages <label> <pkg...>
install_packages() {
  local label=$1; shift
  local repo=() omarchy=() unresolved=() aur=() p

  info "Resolving ${#@} packages for: $label"
  for p; do
    pacman -T "$p" >/dev/null 2>&1 && continue                 # already installed (or provided by something installed)
    if pacman -Sp --print-format %n "$p" >/dev/null 2>&1; then  # repo package, group or provider
      repo+=("$p")
    elif omarchy_repo_has "$p"; then
      omarchy+=("$p")
    else
      unresolved+=("$p")
    fi
  done

  if (( ${#unresolved[@]} )); then
    local found=" $(aur_filter_existing "${unresolved[@]}" | tr '\n' ' ') "
    for p in "${unresolved[@]}"; do
      if [[ $found == *" $p "* ]]; then
        aur+=("$p")
      else
        record_pkg_failure "$p" "not found in the repos, the Omarchy repo or the AUR (renamed or removed upstream?)"
      fi
    done
  fi

  if (( ${#repo[@]} + ${#omarchy[@]} + ${#aur[@]} == 0 )); then
    ok "$label: everything already installed"
    return 0
  fi

  if (( ${#repo[@]} )); then
    info "Repo packages (${#repo[@]}): ${repo[*]}"
    if ! sudo_run pacman -S --needed --noconfirm "${repo[@]}"; then
      warn "Batch install failed; retrying one by one to find the package that breaks it"
      local failed=0
      for p in "${repo[@]}"; do
        sudo_run pacman -S --needed --noconfirm "$p" || { record_pkg_failure "$p" "pacman failed (see the log above this line)"; (( ++failed )); }
      done
      # Everything failing points at the system (network, keyring, lock), not
      # at one package: fail the step so it gets diagnosed and retried.
      if (( failed == ${#repo[@]} )); then
        err "Every repo package failed to install; this is a system problem, not a package problem."
        return 1
      fi
    fi
  fi

  for p in "${omarchy[@]}"; do
    info "Omarchy repo package: $p $(omarchy_repo_version "$p")"
    local file
    if file=$(omarchy_repo_fetch "$p"); then
      sudo_run pacman -U --needed --noconfirm "$file" || record_pkg_failure "$p" "pacman -U failed (a dependency may be missing)"
    else
      record_pkg_failure "$p" "download from the Omarchy repo failed"
    fi
  done

  if (( ${#aur[@]} )); then
    if ensure_aur_helper; then
      for p in "${aur[@]}"; do
        info "AUR package: $p"
        aur_install "$p" || record_pkg_failure "$p" "AUR build failed (often an upstream issue; try again later)"
      done
    else
      for p in "${aur[@]}"; do record_pkg_failure "$p" "no AUR helper"; done
    fi
  fi
  return 0
}
