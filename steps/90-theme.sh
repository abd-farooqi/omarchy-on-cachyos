# desc: Apply the Omarchy theme

export OMARCHY_PATH="$OMARCHY_HOME" PATH="$OMARCHY_BIN:$OMARCHY_HOME/bin:$PATH"
current=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true)

if [[ -n $current && $current == "$THEME" ]]; then
  ok "Theme already set to $THEME"
  return 0
fi

[[ -d $OMARCHY_HOME/themes/$THEME || -d $HOME/.config/omarchy/themes/$THEME ]] || {
  warn "Theme '$THEME' does not exist in this Omarchy release. Available: $(ls "$OMARCHY_HOME/themes" | tr '\n' ' ')"
  THEME=$(ls "$OMARCHY_HOME/themes" | head -1)
  info "Using $THEME instead"
}

if run omarchy-theme-set "$THEME"; then
  ok "Theme: $THEME"
else
  # Outside a Hyprland session some parts can't apply; finish at next login.
  hook="$HOME/.config/omarchy/hooks/post-boot.d/zz-omarchy-on-cachyos-theme"
  run mkdir -p "$(dirname "$hook")"
  (( DRY_RUN )) || printf 'omarchy-theme-set %q && rm -f %q\n' "$THEME" "$hook" >"$hook"
  warn "The theme could not be fully applied outside the desktop; it will be applied at your next login."
fi
