# desc: Install packages: Omarchy's own list plus the groups you picked

lists="$REPO_DIR/packages"
exclude=$(read_pkg_list "$lists/omarchy-exclude.txt" | sort -u)
not_excluded() { comm -23 <(sort -u) <(printf '%s\n' "$exclude"); }

mapfile -t pkgs < <(read_pkg_list "$lists/core.txt")
install_packages "core (needed for the desktop)" "${pkgs[@]}"

if [[ $PKG_OMARCHY == y ]]; then
  # Read from the Omarchy release just installed, so the list follows Omarchy.
  mapfile -t pkgs < <(
    { read_pkg_list "$OMARCHY_HOME/install/omarchy-base.packages"
      omarchy_repo_depends omarchy
      omarchy_repo_depends omarchy-settings; } | not_excluded
  )
  install_packages "Omarchy's default apps and tools" "${pkgs[@]}"
fi

[[ $PKG_APPS == y ]] && { mapfile -t pkgs < <(read_pkg_list "$lists/apps.txt"); install_packages "apps" "${pkgs[@]}"; }
[[ $PKG_DEV == y ]]  && { mapfile -t pkgs < <(read_pkg_list "$lists/dev.txt");  install_packages "dev tools" "${pkgs[@]}"; }
[[ $PKG_AUR == y ]]  && { mapfile -t pkgs < <(read_pkg_list "$lists/aur.txt");  install_packages "AUR apps" "${pkgs[@]}"; }
[[ $NORDVPN == y ]]  && install_packages "NordVPN" nordvpn-bin

if lspci 2>/dev/null | grep -iE 'vga|3d|display' | grep -qi intel; then
  mapfile -t pkgs < <(read_pkg_list "$lists/hardware-intel.txt")
  install_packages "Intel graphics" "${pkgs[@]}"
fi

# Same rule as Omarchy's installer: thermald on Intel laptops from Sandy Bridge on.
cpu_model=$(awk -F: '/^model[[:space:]]*:/ {gsub(/ /, "", $2); print $2; exit}' /proc/cpuinfo)
if grep -q GenuineIntel /proc/cpuinfo && (( ${cpu_model:-0} >= 42 )) && ls -d /sys/class/power_supply/BAT* >/dev/null 2>&1; then
  mapfile -t pkgs < <(read_pkg_list "$lists/hardware-intel-laptop.txt")
  install_packages "Intel laptop" "${pkgs[@]}"
fi

if [[ -s $RUN_DIR/package-failures.tsv ]]; then
  warn "$(wc -l <"$RUN_DIR/package-failures.tsv") package(s) could not be installed; they are listed at the end."
else
  ok "All packages installed"
fi
