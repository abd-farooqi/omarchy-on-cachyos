# desc: System setup: login screen, lock screen password, services, groups

# Lock screen password check (Omarchy's own helper writes the PAM file).
if [[ -x $OMARCHY_BIN/omarchy-apply-lock ]]; then
  sudo_run env OMARCHY_INSTALL_USER="$USER" OMARCHY_PATH="$OMARCHY_HOME" PATH="$OMARCHY_BIN:/usr/bin:/bin" "$OMARCHY_BIN/omarchy-apply-lock" ||
    warn "omarchy-apply-lock failed; the lock screen may not accept your password."
else
  warn "omarchy-apply-lock not found; the lock screen PAM file was not written."
fi

# Login screen: greetd + tuigreet, starting Hyprland through uwsm.
if [[ $LOGIN_SCREEN == y ]]; then
  if [[ -f /etc/greetd/config.toml ]] && ! grep -q 'uwsm start' /etc/greetd/config.toml; then
    sudo_run cp /etc/greetd/config.toml "/etc/greetd/config.toml.bak-$(date +%Y%m%d-%H%M%S)"
  fi
  sudo_write /etc/greetd/config.toml <<'TOML'
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --remember-user-session --asterisks --sessions /usr/share/wayland-sessions --cmd 'uwsm start -e -D Hyprland hyprland.desktop'"
user = "greeter"
TOML
  # Only one display manager can own the screen.
  for dm in sddm lightdm gdm lxdm plasmalogin ly ly@tty2 ly@tty1; do
    if systemctl is-enabled "$dm.service" >/dev/null 2>&1; then
      sudo_run systemctl disable "$dm.service"
      info "Disabled the previous login screen: $dm"
    fi
  done
  sudo_run systemctl enable -f greetd.service
  ok "Login screen: tuigreet (active after the next reboot)"
fi

enable_unit() { systemctl list-unit-files "$1" >/dev/null 2>&1 && sudo_run systemctl enable --now "$1"; }
add_group() { getent group "$1" >/dev/null && ! id -nG "$USER" | grep -qw "$1" && sudo_run usermod -aG "$1" "$USER"; return 0; }

enable_unit bluetooth.service || true
pacman -Q thermald >/dev/null 2>&1 && enable_unit thermald.service
pacman -Q cups >/dev/null 2>&1 && enable_unit cups.socket
if [[ $DOCKER == y ]] && pacman -Q docker >/dev/null 2>&1; then
  enable_unit docker.socket
  add_group docker
fi
if [[ $NORDVPN == y ]] && pacman -Q nordvpn-bin >/dev/null 2>&1; then
  enable_unit nordvpnd.service
  add_group nordvpn
fi

# User services. --global would affect every user; this is only yours.
user_enable() {
  local unit=$1 target=${2:-graphical-session.target}
  [[ -f $HOME/.config/systemd/user/$unit || -f /usr/lib/systemd/user/$unit ]] || return 0
  if systemctl --user daemon-reload 2>/dev/null; then
    run systemctl --user enable "$unit"
  else
    # No user session bus (e.g. run from a TTY over su): enable by hand.
    run mkdir -p "$HOME/.config/systemd/user/$target.wants"
    run ln -sfn "$HOME/.config/systemd/user/$unit" "$HOME/.config/systemd/user/$target.wants/$unit"
  fi
}
user_enable omarchy-sleep-lock.service
ok "System setup done"
