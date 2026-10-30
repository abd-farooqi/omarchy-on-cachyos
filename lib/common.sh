# Shared helpers: output, logging, sudo, dry-run, retries, state.
# Sourced by setup.sh and every step; never run directly.

APP=omarchy-on-cachyos
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/$APP"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/$APP"
ANSWERS_FILE="$CONFIG_DIR/answers.env"
DONE_DIR="$STATE_DIR/done"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/$APP"

OMARCHY_HOME="$HOME/.local/share/omarchy"
OMARCHY_BIN="$HOME/.local/bin"

DRY_RUN=${DRY_RUN:-0}
ASSUME_YES=${ASSUME_YES:-0}

if [[ -t 1 ]]; then
  C_RED=$'\e[31m' C_GRN=$'\e[32m' C_YLW=$'\e[33m' C_BLU=$'\e[34m' C_CYN=$'\e[36m' C_DIM=$'\e[2m' C_BLD=$'\e[1m' C_RST=$'\e[0m'
else
  C_RED='' C_GRN='' C_YLW='' C_BLU='' C_CYN='' C_DIM='' C_BLD='' C_RST=''
fi

info()  { printf '%s→%s %s\n' "$C_CYN" "$C_RST" "$*"; }
ok()    { printf '%s✓%s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn()  { printf '%s⚠%s %s\n' "$C_YLW" "$C_RST" "$*" >&2; record_warning "$*"; }
err()   { printf '%s✗%s %s\n' "$C_RED" "$C_RST" "$*" >&2; }
die()   { err "$*"; exit 1; }
title() { printf '\n%s━━ %s ━━%s\n' "$C_BLU$C_BLD" "$*" "$C_RST"; }

# Warnings are collected so the final summary can list everything that needs a look.
record_warning() {
  [[ -n ${RUN_DIR:-} ]] || return 0
  printf '[%s] %s\n' "${CURRENT_STEP:-setup}" "$*" >>"$RUN_DIR/warnings.txt"
}

# Run a command that changes the system. In dry-run mode it is only printed.
run() {
  printf '%s$ %s%s\n' "$C_DIM" "$*" "$C_RST"
  (( DRY_RUN )) && return 0
  "$@"
}

sudo_run() {
  printf '%s# %s%s\n' "$C_DIM" "$*" "$C_RST"
  (( DRY_RUN )) && return 0
  sudo "$@"
}

# Write stdin to a root-owned file (dry-run shows the content instead).
sudo_write() {
  local target=$1 mode=${2:-644}
  if (( DRY_RUN )); then
    printf '%s# write %s:%s\n' "$C_DIM" "$target" "$C_RST"
    sed 's/^/    /'
    return 0
  fi
  sudo install -D -m "$mode" /dev/stdin "$target"
}

# Append stdin to a root-owned file.
sudo_write_append() {
  local target=$1
  if (( DRY_RUN )); then
    printf '%s# append to %s:%s\n' "$C_DIM" "$target" "$C_RST"
    sed 's/^/    /'
    return 0
  fi
  sudo tee -a "$target" >/dev/null
}

# retry <attempts> <command...>: for network operations that fail transiently.
retry() {
  local attempts=$1 n=1 delay=3; shift
  until "$@"; do
    if (( n >= attempts )); then
      return 1
    fi
    warn "Attempt $n/$attempts failed: $*  (retrying in ${delay}s)"
    sleep "$delay"
    (( n++, delay *= 2 ))
  done
}

have() { command -v "$1" >/dev/null 2>&1; }

# ---------- sudo: ask once, keep the ticket alive ----------
# The password is never stored. sudo caches it for the session and the loop
# below refreshes that cache, so later sudo/pacman/yay calls don't ask again.
SUDO_KEEPALIVE_PID=

sudo_start() {
  (( DRY_RUN )) && return 0   # a dry run changes nothing, so it needs no password
  if ! sudo -n true 2>/dev/null; then
    printf '\n%sYour sudo password is needed once; it is reused for the whole run.%s\n' "$C_BLD" "$C_RST"
  fi
  sudo -v || die "sudo failed. Is $USER in the wheel group? (check: groups $USER)"
  ( while kill -0 "$$" 2>/dev/null; do sudo -n -v 2>/dev/null; sleep 45; done ) &
  SUDO_KEEPALIVE_PID=$!
  disown "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
}

sudo_stop() {
  [[ -n $SUDO_KEEPALIVE_PID ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
  SUDO_KEEPALIVE_PID=
}

# ---------- prompts (used only before the run starts) ----------
ask() { # ask VAR "Question" "default"
  local __var=$1 question=$2 default=${3:-} reply
  if (( ASSUME_YES )); then
    printf -v "$__var" '%s' "$default"; return
  fi
  read -r -p "$(printf '%s?%s %s %s[%s]%s ' "$C_CYN" "$C_RST" "$question" "$C_DIM" "$default" "$C_RST")" reply </dev/tty
  printf -v "$__var" '%s' "${reply:-$default}"
}

ask_yn() { # ask_yn VAR "Question" y|n
  local __var=$1 question=$2 default=${3:-y} reply
  if (( ASSUME_YES )); then
    printf -v "$__var" '%s' "$default"; return
  fi
  while true; do
    read -r -p "$(printf '%s?%s %s %s[%s]%s ' "$C_CYN" "$C_RST" "$question" "$C_DIM" "$([[ $default == y ]] && echo Y/n || echo y/N)" "$C_RST")" reply </dev/tty
    reply=${reply:-$default}
    case ${reply,,} in
      y|yes) printf -v "$__var" y; return ;;
      n|no)  printf -v "$__var" n; return ;;
    esac
  done
}

# ---------- answers ----------
load_answers() { [[ -f $ANSWERS_FILE ]] && source "$ANSWERS_FILE"; }

save_answers() {
  (( DRY_RUN )) && return 0
  mkdir -p "$CONFIG_DIR"
  local v
  {
    echo "# Saved by $APP on $(date -Is). Delete this file or run with --reconfigure to be asked again."
    for v in "${ANSWER_VARS[@]}"; do
      printf '%s=%q\n' "$v" "${!v}"
    done
  } >"$ANSWERS_FILE"
}

# ---------- step bookkeeping ----------
step_done()  { [[ -f $DONE_DIR/$1 ]]; }
mark_done()  { (( DRY_RUN )) && return 0; mkdir -p "$DONE_DIR"; date -Is >"$DONE_DIR/$1"; }
clear_done() { rm -f "$DONE_DIR/$1"; }

# ---------- files ----------
# Replace a file in $HOME, backing up whatever was there first.
backup_path() {
  local target=$1
  [[ -e $target || -L $target ]] || return 0
  local dest="$RUN_DIR/backup${target}"
  (( DRY_RUN )) && { printf '%s  backup %s%s\n' "$C_DIM" "$target" "$C_RST"; return 0; }
  mkdir -p "$(dirname "$dest")"
  cp -a "$target" "$dest"
}

# install_file <src> <dest>: copy if different, keep a backup of the old one.
install_file() {
  local src=$1 dest=$2
  if [[ -f $dest ]] && cmp -s "$src" "$dest"; then
    return 0
  fi
  backup_path "$dest"
  run mkdir -p "$(dirname "$dest")"
  run cp -f "$src" "$dest"
  [[ -x $src ]] && run chmod +x "$dest"
  printf '  %s%s%s\n' "$C_DIM" "${dest/#$HOME/\~}" "$C_RST"
}

# Fill @@VAR@@ placeholders from the environment.
render_template() {
  local src=$1 out
  out=$(<"$src")
  local var
  for var in $(grep -oE '@@[A-Z_]+@@' "$src" | sort -u | tr -d '@'); do
    out=${out//@@$var@@/${!var-}}
  done
  printf '%s\n' "$out"
}
