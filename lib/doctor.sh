# Health checks for the finished setup. `./setup.sh doctor` runs them;
# `./setup.sh doctor --fix` re-runs the step that repairs each failed check.
#
# To add a check: write a check_* function that calls pass/fail/warn_check,
# passing the step that fixes it as the last argument of fail/warn_check.

DOCTOR_FAILS=0
DOCTOR_WARNS=0
DOCTOR_FIX_STEPS=()

pass()       { printf '  %s✓%s %s\n' "$C_GRN" "$C_RST" "$1"; }
fail()       { printf '  %s✗ %s%s\n      %s\n' "$C_RED" "$1" "$C_RST" "$2"; (( ++DOCTOR_FAILS )); [[ -n ${3:-} ]] && DOCTOR_FIX_STEPS+=("$3"); return 0; }
warn_check() { printf '  %s⚠ %s%s\n      %s\n' "$C_YLW" "$1" "$C_RST" "$2"; (( ++DOCTOR_WARNS )); [[ -n ${3:-} ]] && DOCTOR_FIX_STEPS+=("$3"); return 0; }

in_session() { [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && have hyprctl; }

check_tree() {
  if [[ -f $OMARCHY_HOME/default/hypr/bootstrap.lua && -d $OMARCHY_HOME/shell ]]; then
    pass "Omarchy is installed ($(sed -n 's/^omarchy=//p' "$STATE_DIR/omarchy-version" 2>/dev/null || cat "$OMARCHY_HOME/version"))"
  else
    fail "Omarchy is missing from $OMARCHY_HOME" "Reinstall it: ./setup.sh --only omarchy-core" omarchy-core
  fi
}

check_links() {
  [[ $(readlink /usr/share/omarchy 2>/dev/null) == "$OMARCHY_HOME" ]] &&
    pass "/usr/share/omarchy points to your Omarchy folder" ||
    fail "/usr/share/omarchy does not point to $OMARCHY_HOME" "Some Omarchy code uses that path. Fix: sudo ln -sfn $OMARCHY_HOME /usr/share/omarchy" omarchy-core

  local broken
  broken=$(find "$OMARCHY_HOME/bin" -xtype l 2>/dev/null | wc -l)
  (( broken == 0 )) && pass "All Omarchy commands are linked" ||
    fail "$broken Omarchy commands point to files that don't exist" "e.g. $(find "$OMARCHY_HOME/bin" -xtype l | head -3 | xargs -n1 basename | tr '\n' ' ')— reinstall: ./setup.sh --only omarchy-core" omarchy-core
}

check_commands() {
  local missing=() c
  for c in Hyprland hyprctl uwsm quickshell omarchy omarchy-shell gum jq kitty omasnap wtype; do
    have "$c" || [[ -x $OMARCHY_BIN/$c ]] || missing+=("$c")
  done
  (( ${#missing[@]} == 0 )) && pass "Required programs are installed" ||
    fail "Missing programs: ${missing[*]}" "Install them: ./setup.sh --only packages" packages
}

check_env() {
  grep -q 'OMARCHY_PATH=' "$HOME/.config/uwsm/env" 2>/dev/null &&
    pass "Session environment sets OMARCHY_PATH" ||
    fail "~/.config/uwsm/env doesn't set OMARCHY_PATH" "Without it the bar and menus can't find Omarchy. Fix: ./setup.sh --only personal-config" personal-config
}

check_hypr_config() {
  have Hyprland || return 0
  local out
  out=$(Hyprland --verify-config -c "$HOME/.config/hypr/hyprland.lua" 2>&1)
  if grep -q 'config ok' <<<"$out"; then
    pass "Hyprland config is valid"
  else
    fail "Hyprland config has errors" "$(grep -iE 'error|line' <<<"$out" | head -3 | tr '\n' ' ')" personal-config
  fi
  if in_session; then
    local errs; errs=$(hyprctl configerrors 2>/dev/null | grep -v '^\s*$')
    [[ -z $errs ]] && pass "Running Hyprland reports no config errors" ||
      fail "Running Hyprland reports config errors" "$(head -2 <<<"$errs" | tr '\n' ' ')"
  fi
}

check_login() {
  [[ ${LOGIN_SCREEN:-y} == y ]] || return 0
  if systemctl is-enabled greetd.service >/dev/null 2>&1 && grep -q 'uwsm start' /etc/greetd/config.toml 2>/dev/null; then
    pass "Login screen (greetd + tuigreet) starts Hyprland through uwsm"
  else
    fail "The login screen is not set up" "Fix: ./setup.sh --only system" system
  fi
  local dm others=()
  for dm in sddm lightdm gdm plasmalogin ly ly@tty2; do
    systemctl is-enabled "$dm.service" >/dev/null 2>&1 && others+=("$dm")
  done
  (( ${#others[@]} == 0 )) || warn_check "Another login screen is also enabled: ${others[*]}" "Two login screens fight over the display. Fix: ./setup.sh --only system" system
}

check_lock() {
  [[ -f /etc/pam.d/omarchy-lock-password ]] && pass "Lock screen can check your password" ||
    fail "Lock screen PAM file is missing" "You could be locked out after locking. Fix: ./setup.sh --only system" system
  [[ -f $HOME/.config/systemd/user/graphical-session.target.wants/omarchy-sleep-lock.service ]] ||
    systemctl --user is-enabled omarchy-sleep-lock.service >/dev/null 2>&1 &&
    pass "Screen locks before suspend" ||
    warn_check "Lock-before-suspend service is not enabled" "Fix: ./setup.sh --only system" system
}

logind_prop() { busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager "$1" 2>/dev/null | awk '{print $2}' | tr -d '"'; }

check_power() {
  [[ $(logind_prop HandlePowerKey) == ignore ]] &&
    pass "Power button opens Omarchy's power menu (doesn't power off instantly)" ||
    fail "Power button powers the laptop off instantly" "A stray press after waking from sleep shuts down and loses open apps. Fix: ./setup.sh --only system-tweaks" system-tweaks
  local delay; delay=$(logind_prop InhibitDelayMaxUSec)
  (( ${delay:-0} >= 15000000 )) && pass "Lock screen gets 15 s to lock before sleep" ||
    warn_check "Only $(( ${delay:-0} / 1000000 )) s allowed to lock before sleep" "The screen can suspend unlocked when closing the lid also changes displays. Fix: ./setup.sh --only system-tweaks" system-tweaks
  if [[ -d /sys/class/power_supply/BAT0 || -d /sys/class/power_supply/BAT1 ]] &&
    [[ $(busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanHibernate 2>/dev/null) != *yes* ]]; then
    warn_check "Hibernate is not available" "At critical battery the laptop can only suspend, and may run flat while asleep. Fix: ./setup.sh --only hibernate (then reboot)" hibernate
  elif [[ -f /etc/systemd/logind.conf.d/30-lid-suspend-then-hibernate.conf ]]; then
    pass "Hibernate works; lid on battery suspends, then hibernates after 3 h"
  fi
  if grep -q GenuineIntel /proc/cpuinfo && ls -d /sys/class/power_supply/BAT* >/dev/null 2>&1; then
    systemctl is-active thermald.service >/dev/null 2>&1 && pass "thermald is managing CPU temperature" ||
      warn_check "thermald is not running" "Omarchy runs it on Intel laptops to avoid overheating/throttling. Fix: ./setup.sh --only packages,system" packages
  fi
}

check_first_run() {
  [[ -f $HOME/.local/state/omarchy/done/first-run-user ]] && pass "Omarchy first-run provisioning is skipped (as intended)" ||
    warn_check "Omarchy's first-run setup would run at next login" "It would set Chromium as default browser and run full-install hooks. Fix: ./setup.sh --only omarchy-defaults" omarchy-defaults
}

check_patches() {
  local p status name bad=()
  for p in "$REPO_DIR"/patches/*.sh; do
    name=$(basename "$p" .sh)
    status=$(patch_status "$p")
    case $status in
      pending)  bad+=("$name (not applied)") ;;
      outdated) bad+=("$name (Omarchy changed; patch needs updating)") ;;
    esac
  done
  (( ${#bad[@]} == 0 )) && pass "Local patches are in place" ||
    warn_check "Patches: ${bad[*]}" "Fix: ./setup.sh --only patches  (an 'outdated' patch needs editing in patches/)" patches
}

check_plugins() {
  local json="$HOME/.config/omarchy/shell.json" id missing=()
  [[ -f $json ]] || { fail "Bar layout ~/.config/omarchy/shell.json is missing" "Fix: ./setup.sh --only personal-config" personal-config; return; }
  for id in $(jq -r '[.bar.layout[][]?.id, .plugins[]?.id] | .[]' "$json" 2>/dev/null | grep -v '^omarchy\.' | sort -u); do
    [[ -d $HOME/.config/omarchy/plugins/$id ]] || missing+=("$id")
  done
  (( ${#missing[@]} == 0 )) && pass "All bar plugins in shell.json are installed" ||
    fail "Bar plugins missing: ${missing[*]}" "Fix: ./setup.sh --only personal-config" personal-config
}

check_shell_running() {
  in_session || { info "  (not inside Hyprland: live bar checks skipped)"; return 0; }
  if timeout 5 omarchy-shell shell ping 2>/dev/null | grep -q ok; then
    pass "The Omarchy bar is running and answering"
  else
    fail "The Omarchy bar is not responding" "Restart it: omarchy restart shell   (logs: journalctl --user -t omarchy-shell -b)"
  fi
  local errs
  errs=$(journalctl --user -t omarchy-shell -b --no-pager 2>/dev/null | grep -iE ' ERROR|Unable to assign|ReferenceError|TypeError|is not a type|module .* is not installed' | grep -viE 'portal|quickshell\.dbus' | tail -3)
  [[ -z $errs ]] && pass "No errors in the bar's log this boot" ||
    warn_check "The bar logged errors this boot" "$(cut -c1-160 <<<"$errs" | tr '\n' ' ')"
}

check_packages() {
  local last
  last=$(ls -1dt "$STATE_DIR"/runs/*/ 2>/dev/null | head -1)
  if [[ -n $last && -s $last/package-failures.tsv ]]; then
    warn_check "$(wc -l <"$last/package-failures.tsv") packages failed in the last run" "$(cut -f1 "$last/package-failures.tsv" | tr '\n' ' ')— retry: ./setup.sh --only packages" packages
  else
    pass "No package failures recorded"
  fi
}

check_updates() {
  local installed latest
  installed=$(sed -n 's/^omarchy=//p' "$STATE_DIR/omarchy-version" 2>/dev/null)
  [[ -n $installed ]] || return 0
  latest=$(omarchy_repo_version omarchy 2>/dev/null)
  if [[ -n $latest && $latest != "$installed" ]]; then
    warn_check "Omarchy $latest is available (you have $installed)" "Update: ./setup.sh update"
  elif [[ -n $latest ]]; then
    pass "Omarchy is the newest ${OMARCHY_CHANNEL:-stable} release"
  fi
}

run_doctor() {
  DOCTOR_FAILS=0 DOCTOR_WARNS=0 DOCTOR_FIX_STEPS=()
  title "Health check"
  check_tree; check_links; check_commands; check_env; check_hypr_config
  check_login; check_lock; check_power; check_first_run; check_patches; check_plugins
  check_shell_running; check_packages; check_updates
  echo
  if (( DOCTOR_FAILS == 0 && DOCTOR_WARNS == 0 )); then
    ok "Everything looks healthy"
  else
    printf '%s%d problem(s), %d warning(s)%s\n' "$C_BLD" "$DOCTOR_FAILS" "$DOCTOR_WARNS" "$C_RST"
  fi
  (( DOCTOR_FAILS == 0 ))
}
