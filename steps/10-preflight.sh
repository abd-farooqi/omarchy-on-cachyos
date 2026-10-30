# desc: Check this is a CachyOS/Arch system that is ready to be set up
# always: yes

(( EUID != 0 )) || die "Run setup.sh as your normal user, not with sudo. It asks for the password itself."

. /etc/os-release
case "$ID ${ID_LIKE:-}" in
  *cachyos*) ok "CachyOS detected" ;;
  *arch*)    warn "This is $PRETTY_NAME, not CachyOS. It should work on any Arch system, but it is only tested on CachyOS." ;;
  *)         die "This only works on CachyOS / Arch Linux (found: $PRETTY_NAME)." ;;
esac

[[ $(uname -m) == x86_64 ]] || die "Only x86_64 is supported (Omarchy packages are x86_64)."

if pacman -Q omarchy >/dev/null 2>&1 || [[ -d /usr/share/omarchy && ! -L /usr/share/omarchy ]]; then
  die "The full Omarchy package is installed. This repo is for CachyOS; on a real Omarchy install use Omarchy's own updater."
fi

info "Checking the internet connection"
curl -fsS --max-time 15 -o /dev/null https://pkgs.omarchy.org/stable/x86_64/omarchy.db 2>/dev/null ||
  curl -fsS --max-time 15 -o /dev/null https://archlinux.org 2>/dev/null ||
  die "No internet connection. Connect first (run: nmtui), then start again."
ok "Online"

free_gb() { df -BG --output=avail "$1" | tail -1 | tr -dc 0-9; }
(( $(free_gb /) >= 8 )) || warn "Only $(free_gb /) GB free on /. Installing everything needs about 8 GB."
(( $(free_gb "$HOME") >= 2 )) || warn "Only $(free_gb "$HOME") GB free in your home folder."

if [[ -f /var/lib/pacman/db.lck ]] && ! pgrep -x pacman >/dev/null; then
  warn "A stale pacman lock exists; removing it"
  sudo_run rm -f /var/lib/pacman/db.lck
fi

pacman -Q hyprland >/dev/null 2>&1 && ok "Hyprland is installed" ||
  info "Hyprland is not installed yet; it will be installed"
