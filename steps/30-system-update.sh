# desc: Update the system and install the tools the rest of the setup needs

# Arch doesn't support partial upgrades: sync and upgrade before installing anything.
sudo_run pacman -Syu --noconfirm
sudo_run pacman -S --needed --noconfirm jq curl git base-devel libarchive zstd perl
ensure_aur_helper || true
ok "System is up to date"
