# desc: Download the newest Omarchy release and install it into your home folder

# Omarchy is installed the way the previous setup was: the files from the
# omarchy and omarchy-settings packages, unpacked under ~/.local/share/omarchy,
# without installing the packages themselves. The packages would replace
# CachyOS's bootloader, login screen, Plymouth and several /etc files.

omarchy_repo_refresh
EXTRACT="$CACHE_DIR/extract"
run rm -rf "$EXTRACT"
mkdir -p "$EXTRACT"

for pkg in omarchy omarchy-settings; do
  info "Fetching $pkg $(omarchy_repo_version "$pkg") (${OMARCHY_CHANNEL} channel)"
  file=$(omarchy_repo_fetch "$pkg")
  mkdir -p "$EXTRACT/$pkg"
  bsdtar -xf "$file" -C "$EXTRACT/$pkg"
done

stage="$CACHE_DIR/stage"
rm -rf "$stage" && mkdir -p "$stage/tree" "$stage/bin"
for pkg in omarchy omarchy-settings; do
  [[ -d $EXTRACT/$pkg/usr/share/omarchy ]] && cp -a "$EXTRACT/$pkg/usr/share/omarchy/." "$stage/tree/"
  [[ -d $EXTRACT/$pkg/usr/bin ]] && cp -a "$EXTRACT/$pkg/usr/bin/." "$stage/bin/"
done

# If Omarchy reorganises its package, stop here instead of installing half a desktop.
for required in default/hypr/bootstrap.lua shell bin themes install/omarchy-base.packages; do
  [[ -e $stage/tree/$required ]] ||
    die "The new Omarchy release no longer has '$required'. Its layout changed; this repo needs updating before it can install it. Nothing was changed."
done
[[ -x $stage/bin/omarchy ]] || die "The new Omarchy release has no 'omarchy' command in usr/bin. Nothing was changed."

# Keep the previous tree for one-command rollback (setup.sh rollback-omarchy).
if [[ -d $OMARCHY_HOME ]]; then
  run rm -rf "$STATE_DIR/previous/omarchy"
  run mkdir -p "$STATE_DIR/previous"
  run mv "$OMARCHY_HOME" "$STATE_DIR/previous/omarchy"
  run rm -rf "$STATE_DIR/previous/bin"
  run mkdir -p "$STATE_DIR/previous/bin"
  if [[ -f $STATE_DIR/bin-manifest.txt ]]; then
    run cp "$STATE_DIR/bin-manifest.txt" "$STATE_DIR/previous/bin-manifest.txt"
    (( DRY_RUN )) || while read -r b; do
      if [[ -f $OMARCHY_BIN/$b ]]; then cp -a "$OMARCHY_BIN/$b" "$STATE_DIR/previous/bin/"; fi
    done <"$STATE_DIR/bin-manifest.txt"
  fi
fi
run mkdir -p "$(dirname "$OMARCHY_HOME")" "$OMARCHY_BIN"
run mv "$stage/tree" "$OMARCHY_HOME"

# Commands go to ~/.local/bin; the tree's bin/ links point there.
new_manifest=$(cd "$stage/bin" && ls -1)
if [[ -f $STATE_DIR/bin-manifest.txt ]]; then
  # Remove commands that this Omarchy release dropped.
  comm -23 <(sort "$STATE_DIR/bin-manifest.txt") <(sort <<<"$new_manifest") | while read -r gone; do
    if [[ -n $gone && -f $OMARCHY_BIN/$gone ]]; then run rm -f "$OMARCHY_BIN/$gone"; fi
  done
fi
run cp -a "$stage/bin/." "$OMARCHY_BIN/"
(( DRY_RUN )) || printf '%s\n' "$new_manifest" >"$STATE_DIR/bin-manifest.txt"

relinked=0
for link in "$OMARCHY_HOME"/bin/*; do
  [[ -L $link ]] || continue
  target=$(readlink "$link")
  if [[ $target == /usr/bin/* ]]; then
    run ln -sfn "$OMARCHY_BIN/${target#/usr/bin/}" "$link"
    (( ++relinked ))
  fi
done
info "Pointed $relinked commands in the Omarchy tree at ~/.local/bin"

# Some Omarchy code still hardcodes /usr/share/omarchy; give it a root-owned link.
if [[ $(readlink /usr/share/omarchy 2>/dev/null) != "$OMARCHY_HOME" ]]; then
  sudo_run ln -sfn "$OMARCHY_HOME" /usr/share/omarchy
fi

(( DRY_RUN )) || {
  printf 'channel=%s\nomarchy=%s\nomarchy-settings=%s\ninstalled=%s\n' "$OMARCHY_CHANNEL" \
    "$(omarchy_repo_version omarchy)" "$(omarchy_repo_version omarchy-settings)" "$(date -Is)" >"$STATE_DIR/omarchy-version"
}
run rm -rf "$stage"
ok "Omarchy $(omarchy_repo_version omarchy) installed in ${OMARCHY_HOME/#$HOME/\~}"
