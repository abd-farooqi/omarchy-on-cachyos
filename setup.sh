#!/usr/bin/env bash
# omarchy-on-cachyos: turn a fresh CachyOS + Hyprland install into the Omarchy
# desktop, with your own settings on top. Run ./setup.sh help for usage.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
source "$REPO_DIR/lib/common.sh"
source "$REPO_DIR/lib/diagnose.sh"
source "$REPO_DIR/lib/omarchy-repo.sh"
source "$REPO_DIR/lib/packages.sh"
source "$REPO_DIR/lib/patches.sh"
source "$REPO_DIR/lib/doctor.sh"

ANSWER_VARS=(OMARCHY_CHANNEL PKG_OMARCHY PKG_APPS PKG_DEV PKG_AUR DOCKER NORDVPN
  GIT_NAME GIT_EMAIL KB_LAYOUT KB_VARIANT KB_OPTIONS MONITOR_OUTPUT MONITOR_SCALE
  THEME BROWSER WEBAPP_BROWSER_NAME LOGIN_SCREEN DISCORD_AUTOSTART HIBERNATE HIBERNATE_SIZE_GB SNAPSHOT)

usage() {
  cat <<EOF
${C_BLD}omarchy-on-cachyos${C_RST} — Omarchy's desktop on CachyOS, with your settings.

${C_BLD}Usage:${C_RST} ./setup.sh [command] [options]

${C_BLD}Commands${C_RST}
  install            (default) ask the questions, then run every step
  update             get the newest Omarchy release, re-apply patches, check health
  doctor [--fix]     health check; --fix re-runs the steps that repair failures
  capture            copy your live configs back into this repo (after you tweak them)
  report             write a debug report file to paste into an issue or to Claude
  steps              list the steps
  rollback-omarchy   go back to the Omarchy release installed before the last update
  help               this text

${C_BLD}Options${C_RST}
  --only a,b         run only these steps (names from: ./setup.sh steps)
  --from <step>      start at this step and run the rest
  --force            re-run steps that already finished in an earlier run
  --reconfigure      ask the questions again instead of reusing saved answers
  --dry-run          show what would be done; change nothing
  --yes              accept saved/default answers, don't ask anything

Logs: $STATE_DIR/runs/<time>/  (setup.log, one log per step, warnings.txt)
EOF
}

# ---------- steps ----------
step_files() { ls -1 "$REPO_DIR"/steps/[0-9]*.sh; }
step_name()  { basename "$1" .sh | sed 's/^[0-9]*-//'; }
step_desc()  { sed -n 's/^# desc: //p' "$1"; }
step_always(){ grep -q '^# always: yes' "$1"; }

list_steps() {
  local f
  for f in $(step_files); do
    printf '  %-18s %s%s\n' "$(step_name "$f")" "$(step_desc "$f")" "$(step_done "$(step_name "$f")" && printf ' %s(done)%s' "$C_GRN" "$C_RST")"
  done
}

step_file_by_name() {
  local f
  for f in $(step_files); do [[ $(step_name "$f") == "$1" ]] && { echo "$f"; return 0; }; done
  die "No step called '$1'. Steps: $(for f in $(step_files); do printf '%s ' "$(step_name "$f")"; done)"
}

# Prints where an error happened; set as the ERR trap inside each step.
step_err_trap() {
  local rc=$? line=$1 cmd=$2 src=${3:-}
  printf '\n%s✗ Failed (exit %s) at %s line %s:%s\n    %s\n' "$C_RED" "$rc" "${src/#$REPO_DIR\//}" "$line" "$C_RST" "$cmd"
}

run_step() {
  local file=$1 index=$2 total=$3 name rc attempt=1 choice
  name=$(step_name "$file")
  CURRENT_STEP=$name
  local slog="$RUN_DIR/steps/$name.log"
  mkdir -p "$RUN_DIR/steps"

  title "[$index/$total] $(step_desc "$file")"
  while true; do
    (
      set -Eeuo pipefail
      trap 'step_err_trap "$LINENO" "$BASH_COMMAND" "${BASH_SOURCE[0]}"' ERR
      source "$file"
    ) 2>&1 | tee -a "$slog"
    rc=${PIPESTATUS[0]}

    if (( rc == 0 )); then
      step_always "$file" || mark_done "$name"
      return 0
    fi

    diagnose_log "$slog"
    printf '\n%s┌─ Step "%s" failed%s\n' "$C_RED$C_BLD" "$name" "$C_RST"
    printf '%s│%s What it means: %s\n' "$C_RED" "$C_RST" "$DIAG_HINT"
    printf '%s│%s Full log:      %s\n' "$C_RED" "$C_RST" "$slog"
    printf '%s└─%s\n' "$C_RED" "$C_RST"

    if [[ -n $DIAG_FIX && $attempt -eq 1 ]]; then
      info "Trying the automatic fix ($DIAG_FIX), then retrying the step…"
      (( attempt++ ))
      if ( set -uo pipefail; $DIAG_FIX ) 2>&1 | tee -a "$slog"; then
        DIAG_FIX=
        continue
      fi
      warn "The automatic fix didn't work."
    fi

    if (( ASSUME_YES )) || [[ ! -t 0 ]]; then
      err "Stopping. After fixing the cause, continue with: ./setup.sh --from $name"
      return 1
    fi
    while true; do
      read -r -p "$(printf '%s[r]%setry  %s[s]%skip this step  %s[l]%sast 40 log lines  %s[a]%sbort: ' "$C_BLD" "$C_RST" "$C_BLD" "$C_RST" "$C_BLD" "$C_RST" "$C_BLD" "$C_RST")" choice </dev/tty
      case ${choice,,} in
        r) (( attempt++ )); continue 2 ;;
        s) warn "Step $name skipped after failing; run later: ./setup.sh --only $name"; return 0 ;;
        l) tail -n 40 "$slog" | sed 's/^/    /' ;;
        a) err "Aborted. Continue later with: ./setup.sh --from $name"; return 1 ;;
      esac
    done
  done
}

# ---------- questions ----------
derive_answers() {
  case $BROWSER in
    firefox) BROWSER_DESKTOP=firefox.desktop       BROWSER_CMD=firefox ;;
    chrome)  BROWSER_DESKTOP=google-chrome.desktop BROWSER_CMD=google-chrome-stable ;;
    brave)   BROWSER_DESKTOP=brave-browser.desktop BROWSER_CMD=brave ;;
    chromium)BROWSER_DESKTOP=chromium.desktop      BROWSER_CMD=chromium ;;
    *)       BROWSER_DESKTOP="$BROWSER.desktop"    BROWSER_CMD=$BROWSER ;;
  esac
  case $WEBAPP_BROWSER_NAME in
    chrome)   WEBAPP_BROWSER=google-chrome.desktop ;;
    brave)    WEBAPP_BROWSER=brave-browser.desktop ;;
    chromium) WEBAPP_BROWSER=chromium.desktop ;;
    *)        WEBAPP_BROWSER="$WEBAPP_BROWSER_NAME.desktop" ;;
  esac
  export BROWSER_DESKTOP BROWSER_CMD WEBAPP_BROWSER
}

default_answers() {
  : "${OMARCHY_CHANNEL:=stable}" "${PKG_OMARCHY:=y}" "${PKG_APPS:=y}" "${PKG_DEV:=y}" "${PKG_AUR:=y}"
  : "${DOCKER:=y}" "${NORDVPN:=y}" "${LOGIN_SCREEN:=y}" "${DISCORD_AUTOSTART:=y}" "${SNAPSHOT:=y}"
  : "${GIT_NAME:=$(git config --global user.name 2>/dev/null || true)}"
  : "${GIT_EMAIL:=$(git config --global user.email 2>/dev/null || true)}"
  : "${KB_LAYOUT:=us,pk,af}" "${KB_VARIANT:=,urd-phonetic,ps}" "${KB_OPTIONS:=compose:caps,shift:both_capslock_cancel}"
  : "${MONITOR_OUTPUT:=$(ls /sys/class/drm 2>/dev/null | sed -n 's/^card[0-9]*-\(eDP-[0-9]*\)$/\1/p' | head -1)}"
  local ram_gb has_battery=n
  ram_gb=$(awk '/MemTotal/ {print int($2/1048576 + 0.5)}' /proc/meminfo)
  ls -d /sys/class/power_supply/BAT* >/dev/null 2>&1 && has_battery=y
  : "${HIBERNATE:=$has_battery}"
  # 60% of RAM covers the kernel's default image size (40% of RAM) with room to spare.
  : "${HIBERNATE_SIZE_GB:=$(( ram_gb * 6 / 10 > 8 ? (ram_gb * 6 + 9) / 10 : 8 ))}"
  : "${MONITOR_SCALE:=1.25}" "${THEME:=hackerman}" "${BROWSER:=firefox}" "${WEBAPP_BROWSER_NAME:=chrome}"
}

ask_questions() {
  title "A few questions first (Enter keeps the value in brackets)"
  echo "Everything is asked now; after this the setup runs on its own."
  echo
  ask OMARCHY_CHANNEL "Omarchy release channel (stable / rc / edge)" "$OMARCHY_CHANNEL"
  ask_yn PKG_OMARCHY "Install Omarchy's default apps and tools (its own package list)?" "$PKG_OMARCHY"
  ask_yn PKG_APPS "Install your desktop apps (packages/apps.txt)?" "$PKG_APPS"
  ask_yn PKG_DEV "Install your dev tools (packages/dev.txt)?" "$PKG_DEV"
  ask_yn PKG_AUR "Install your AUR apps — Chrome, 1Password, Slack, VS Code… (packages/aur.txt)?" "$PKG_AUR"
  ask_yn DOCKER "Enable Docker and add you to the docker group?" "$DOCKER"
  ask_yn NORDVPN "Install and enable NordVPN?" "$NORDVPN"
  ask GIT_NAME "Git name" "$GIT_NAME"
  ask GIT_EMAIL "Git email" "$GIT_EMAIL"
  ask KB_LAYOUT "Keyboard layouts (comma separated)" "$KB_LAYOUT"
  ask KB_VARIANT "Keyboard variants (same order, blank = default)" "$KB_VARIANT"
  ask MONITOR_OUTPUT "Built-in screen name (blank = all screens)" "$MONITOR_OUTPUT"
  ask MONITOR_SCALE "Screen scale" "$MONITOR_SCALE"
  ask THEME "Omarchy theme" "$THEME"
  ask BROWSER "Default browser (firefox / chrome / brave / chromium)" "$BROWSER"
  ask WEBAPP_BROWSER_NAME "Browser for Omarchy web apps (chrome / brave / chromium)" "$WEBAPP_BROWSER_NAME"
  ask_yn LOGIN_SCREEN "Use tuigreet as the login screen (replaces the current one)?" "$LOGIN_SCREEN"
  ask_yn DISCORD_AUTOSTART "Start Discord minimized at login?" "$DISCORD_AUTOSTART"
  ask_yn HIBERNATE "Set up hibernate (swap file on disk; lid on battery suspends then hibernates after 3 h)?" "$HIBERNATE"
  [[ $HIBERNATE == y ]] && ask HIBERNATE_SIZE_GB "Hibernate swap file size in GB" "$HIBERNATE_SIZE_GB"
  ask_yn SNAPSHOT "Take a snapper snapshot before changing anything?" "$SNAPSHOT"
}

show_answers() {
  local v
  title "Your answers"
  for v in "${ANSWER_VARS[@]}"; do printf '  %-20s %s\n' "$v" "${!v}"; done
}

# ---------- commands ----------
start_run() {
  RUN_DIR="$STATE_DIR/runs/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$RUN_DIR" "$DONE_DIR"
  ln -sfn "$RUN_DIR" "$STATE_DIR/runs/latest"
  exec > >(tee -a "$RUN_DIR/setup.log") 2>&1
  printf 'omarchy-on-cachyos %s  repo=%s  dry-run=%s\n' "$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')" "$REPO_DIR" "$DRY_RUN" >>"$RUN_DIR/setup.log"
  trap 'sudo_stop' EXIT
}

finish_run() {
  local rc=$1
  title "Summary"
  if [[ -s $RUN_DIR/package-failures.tsv ]]; then
    printf '%sPackages that were not installed:%s\n' "$C_YLW" "$C_RST"
    sed 's/^/  /; s/\t/  — /' "$RUN_DIR/package-failures.tsv"
  fi
  if [[ -s $RUN_DIR/warnings.txt ]]; then
    printf '%sWarnings (%d):%s\n' "$C_YLW" "$(wc -l <"$RUN_DIR/warnings.txt")" "$C_RST"
    sed 's/^/  /' "$RUN_DIR/warnings.txt" | head -40
  fi
  echo "Logs: $RUN_DIR"
  (( rc == 0 )) || return "$rc"
  (( DRY_RUN )) && { ok "Dry run finished; nothing was changed."; return 0; }
  ok "Done."
  cat <<EOF

${C_BLD}Still to do by hand:${C_RST}
  • Reboot, then log in on the tuigreet screen.
  • Sign in: 1Password, browser profiles, Slack, Discord, VS Code, gh (gh auth login && gh auth setup-git).
  • Slack bar widget: put your tokens in ~/.config/petrzpav-slack/secrets.
  • After you tweak a config, save it into this repo: ./setup.sh capture
  • If anything looks wrong: ./setup.sh doctor   (or ./setup.sh report for a full debug file)
EOF
}

cmd_install() {
  local only=$1 from=$2 force=$3 reconfigure=$4
  load_answers
  default_answers
  if [[ ! -f $ANSWERS_FILE || $reconfigure == 1 ]]; then
    ask_questions
  else
    show_answers
    local reuse=y
    (( ASSUME_YES )) || ask_yn reuse "Use these saved answers?" y
    [[ $reuse == y ]] || ask_questions
  fi
  derive_answers
  export "${ANSWER_VARS[@]}"

  local files=() f n
  if [[ -n $only ]]; then
    for n in ${only//,/ }; do files+=("$(step_file_by_name "$n")"); done
  else
    local started=0
    [[ -z $from ]] && started=1
    for f in $(step_files); do
      [[ $started == 0 && $(step_name "$f") == "$from" ]] && started=1
      (( started )) || continue
      if [[ $force == 0 && -z $from ]] && step_done "$(step_name "$f")" && ! step_always "$f"; then
        info "Skipping $(step_name "$f") (finished in an earlier run; --force to redo)"
        continue
      fi
      files+=("$f")
    done
    [[ -n $from && ${#files[@]} -eq 0 ]] && step_file_by_name "$from" >/dev/null
  fi

  if ! (( ASSUME_YES )); then
    echo; echo "Steps to run:"; for f in "${files[@]}"; do printf '  • %s\n' "$(step_desc "$f")"; done
    local go; ask_yn go "Start now?" y
    [[ $go == y ]] || exit 0
  fi
  save_answers
  start_run
  sudo_start

  local i=0 rc=0
  for f in "${files[@]}"; do
    (( ++i ))
    # Not `run_step ... || ...`: bash disables set -e and the ERR trap for
    # everything called on the left of || — the steps would run past errors.
    run_step "$f" "$i" "${#files[@]}"
    if (( $? != 0 )); then rc=1; break; fi
  done
  finish_run "$rc"
}

cmd_update() {
  ASSUME_YES=1
  cmd_install "system-update,omarchy-core,packages,omarchy-defaults,patches,system-tweaks,hibernate,verify" "" 1 0
}

cmd_doctor() {
  load_answers; default_answers; derive_answers
  RUN_DIR=${RUN_DIR:-$STATE_DIR/runs/latest}
  run_doctor; local rc=$?
  if [[ ${1:-} == --fix ]] && (( ${#DOCTOR_FIX_STEPS[@]} )); then
    local steps; steps=$(printf '%s\n' "${DOCTOR_FIX_STEPS[@]}" | awk '!seen[$0]++' | paste -sd,)
    info "Re-running: $steps"
    ASSUME_YES=1
    cmd_install "$steps" "" 1 0
  elif (( rc != 0 && ${#DOCTOR_FIX_STEPS[@]} )); then
    echo "Fix automatically with: ./setup.sh doctor --fix"
  fi
  return "$rc"
}

cmd_capture() {
  local src="$REPO_DIR/overrides/home" f live changed=0
  while IFS= read -r -d '' f; do
    live="$HOME/${f#$src/}"
    [[ -f $live ]] || continue
    if ! cmp -s "$f" "$live"; then
      printf '%s~ %s%s\n' "$C_YLW" "${f#$REPO_DIR/}" "$C_RST"
      diff -u "$f" "$live" | sed -n '3,40p' | sed 's/^/    /'
      cp -f "$live" "$f"
      (( ++changed ))
    fi
  done < <(find "$src" -type f -print0)
  # New files in your custom bar plugins
  for f in "$HOME"/.config/omarchy/plugins/abdullah.*; do
    [[ -d $f ]] || continue
    rsync -a --exclude __pycache__ "$f/" "$src/.config/omarchy/plugins/$(basename "$f")/" && :
  done
  if grep -rlF "$HOME" "$src" >/dev/null 2>&1; then
    warn "These repo files contain your home path; use \$HOME or ~ so they work for any username: $(grep -rlF "$HOME" "$src" | sed "s|$REPO_DIR/||" | tr '\n' ' ')"
  fi
  (( changed )) && ok "$changed file(s) copied into the repo. Review with: git -C $REPO_DIR diff" || ok "The repo already matches your live configs."
  info "Generated files (input.lua, monitors.lua, uwsm/env, .XCompose) come from templates/ and your answers; edit those directly."
}

cmd_report() {
  local out="$HOME/omarchy-on-cachyos-report-$(date +%Y%m%d-%H%M%S).txt"
  load_answers; default_answers; derive_answers
  local last; last=$(readlink -f "$STATE_DIR/runs/latest" 2>/dev/null)
  {
    echo "# omarchy-on-cachyos debug report — $(date -Is)"
    echo "## System"
    grep -E '^(PRETTY_NAME|VERSION_ID|BUILD_ID)=' /etc/os-release
    echo "kernel: $(uname -r)"
    echo "hyprland: $(pacman -Q hyprland 2>/dev/null)   quickshell: $(pacman -Q quickshell 2>/dev/null)   uwsm: $(pacman -Q uwsm 2>/dev/null)"
    echo "gpu: $(lspci 2>/dev/null | grep -iE 'vga|3d' | cut -d: -f3 | paste -sd';')"
    echo "repo: $(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null) $(git -C "$REPO_DIR" status --porcelain 2>/dev/null | wc -l) uncommitted change(s)"
    echo; echo "## Omarchy"; cat "$STATE_DIR/omarchy-version" 2>/dev/null
    echo; echo "## Answers (email hidden)"; sed 's/^GIT_EMAIL=.*/GIT_EMAIL=<hidden>/' "$ANSWERS_FILE" 2>/dev/null
    echo; echo "## Steps"; list_steps
    echo; echo "## Doctor"; C_RED='' C_GRN='' C_YLW='' C_RST='' C_BLD='' C_BLU='' run_doctor 2>&1
    if [[ -n $last ]]; then
      echo; echo "## Last run: $last"
      echo "### warnings"; cat "$last/warnings.txt" 2>/dev/null
      echo "### package failures"; cat "$last/package-failures.tsv" 2>/dev/null
      echo "### end of setup.log"; tail -n 150 "$last/setup.log" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'
    fi
    echo; echo "## Bar log (this boot, errors)"
    journalctl --user -t omarchy-shell -b --no-pager 2>/dev/null | grep -iE 'error|warn|fail|unable' | tail -n 40
    echo; echo "## Hyprland"
    have Hyprland && Hyprland --verify-config -c "$HOME/.config/hypr/hyprland.lua" 2>&1 | tail -n 20
    [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && hyprctl configerrors 2>&1
    echo; echo "## Login screen"; systemctl is-enabled greetd.service 2>&1; cat /etc/greetd/config.toml 2>/dev/null
  } | sed -E "s|$HOME|~|g; s/[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}/<email>/g" >"$out"
  ok "Report written: $out"
  echo "It contains no passwords or tokens; email addresses are hidden and paths under your home are shortened to ~."
}

cmd_rollback_omarchy() {
  local prev="$STATE_DIR/previous"
  [[ -d $prev/omarchy ]] || die "No previous Omarchy release is saved (one is kept after each update)."
  info "Restoring the previous Omarchy release ($(cat "$prev/omarchy/version" 2>/dev/null))"
  local tmp="$OMARCHY_HOME.rollback-$$"
  mv "$OMARCHY_HOME" "$tmp"
  mv "$prev/omarchy" "$OMARCHY_HOME"
  mv "$tmp" "$prev/omarchy"
  if [[ -d $prev/bin ]]; then
    cp -a "$prev/bin/." "$OMARCHY_BIN/"
    [[ -f $prev/bin-manifest.txt ]] && cp "$prev/bin-manifest.txt" "$STATE_DIR/bin-manifest.txt"
  fi
  ok "Rolled back. Restart the bar with: omarchy restart shell (running this again undoes the rollback)."
}

# ---------- main ----------
main() {
  local cmd=install only='' from='' force=0 reconfigure=0 fix=''
  while (( $# )); do
    case $1 in
      install|update|doctor|capture|report|steps|rollback-omarchy|help) cmd=$1 ;;
      -h|--help) cmd=help ;;
      --only) only=${2:?--only needs step names}; shift ;;
      --from) from=${2:?--from needs a step name}; shift ;;
      --force) force=1 ;;
      --reconfigure) reconfigure=1 ;;
      --dry-run) DRY_RUN=1 ;;
      --yes|-y) ASSUME_YES=1 ;;
      --fix) fix=--fix ;;
      *) err "Unknown argument: $1"; usage; exit 2 ;;
    esac
    shift
  done
  export DRY_RUN ASSUME_YES REPO_DIR

  case $cmd in
    install)          cmd_install "$only" "$from" "$force" "$reconfigure" ;;
    update)           cmd_update ;;
    doctor)           cmd_doctor "$fix" ;;
    capture)          cmd_capture ;;
    report)           cmd_report ;;
    steps)            list_steps ;;
    rollback-omarchy) cmd_rollback_omarchy ;;
    help)             usage ;;
  esac
}

main "$@"
