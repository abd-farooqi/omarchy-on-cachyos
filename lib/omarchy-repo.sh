# Reads Omarchy's own package repository (the one the Omarchy ISO installs
# from) without adding it to pacman.conf. That keeps CachyOS's repos in
# charge of the system while still letting us pick up any Omarchy release.

OMARCHY_REPO_INDEX=

omarchy_repo_url() { echo "https://pkgs.omarchy.org/${OMARCHY_CHANNEL:-stable}/x86_64"; }

# Downloads omarchy.db and writes a name<TAB>version<TAB>filename<TAB>sha256<TAB>depends index.
omarchy_repo_refresh() {
  local dir="$CACHE_DIR/repo/${OMARCHY_CHANNEL:-stable}"
  mkdir -p "$dir"
  retry 3 curl -fsSL --connect-timeout 15 -o "$dir/omarchy.db.new" "$(omarchy_repo_url)/omarchy.db" ||
    { err "Could not download the Omarchy package index from $(omarchy_repo_url)"; return 1; }
  mv "$dir/omarchy.db.new" "$dir/omarchy.db"
  rm -rf "$dir/db" && mkdir -p "$dir/db"
  bsdtar -xf "$dir/omarchy.db" -C "$dir/db" 2>/dev/null || tar -xzf "$dir/omarchy.db" -C "$dir/db" ||
    { err "The Omarchy package index is not a readable archive (the server format may have changed)."; return 1; }

  OMARCHY_REPO_INDEX="$dir/index.tsv"
  local desc
  for desc in "$dir"/db/*/desc; do
    awk '
      /^%NAME%$/      { getline; name=$0 }
      /^%VERSION%$/   { getline; ver=$0 }
      /^%FILENAME%$/  { getline; file=$0 }
      /^%SHA256SUM%$/ { getline; sum=$0 }
      /^%DEPENDS%$/   { while ((getline line) > 0 && line != "") { sub(/[<>=].*/, "", line); deps = deps " " line } }
      END { if (name && file) print name "\t" ver "\t" file "\t" sum "\t" deps }
    ' "$desc"
  done >"$OMARCHY_REPO_INDEX"

  [[ -s $OMARCHY_REPO_INDEX ]] || { err "The Omarchy package index is empty."; return 1; }
}

# Reuse an index fetched in the last hour (each step runs in its own subshell).
omarchy_repo_ensure() {
  [[ -n $OMARCHY_REPO_INDEX ]] && return 0
  local index="$CACHE_DIR/repo/${OMARCHY_CHANNEL:-stable}/index.tsv"
  if [[ -s $index && -n $(find "$index" -mmin -60 2>/dev/null) ]]; then
    OMARCHY_REPO_INDEX=$index
  else
    omarchy_repo_refresh
  fi
}

omarchy_repo_has() {
  omarchy_repo_ensure || return 1
  awk -F'\t' -v n="$1" '$1 == n { found=1 } END { exit !found }' "$OMARCHY_REPO_INDEX"
}

omarchy_repo_version() {
  omarchy_repo_ensure || return 1
  awk -F'\t' -v n="$1" '$1 == n { print $2 }' "$OMARCHY_REPO_INDEX"
}

# Dependencies Omarchy declares for a package, one per line.
omarchy_repo_depends() {
  omarchy_repo_ensure || return 1
  awk -F'\t' -v n="$1" '$1 == n { print $5 }' "$OMARCHY_REPO_INDEX" | tr ' ' '\n' | awk NF
}

# omarchy_repo_fetch <name>: downloads the package, checks its sha256, prints the local path.
omarchy_repo_fetch() {
  local name=$1 line file sum dest
  omarchy_repo_ensure || return 1
  line=$(awk -F'\t' -v n="$name" '$1 == n' "$OMARCHY_REPO_INDEX")
  [[ -n $line ]] || { err "$name is not in the Omarchy ${OMARCHY_CHANNEL:-stable} repository."; return 1; }
  IFS=$'\t' read -r _ _ file sum _ <<<"$line"
  dest="$CACHE_DIR/pkgs/$file"
  mkdir -p "$CACHE_DIR/pkgs"

  if [[ ! -f $dest ]] || ! echo "$sum  $dest" | sha256sum -c --status; then
    retry 3 curl -fL --connect-timeout 15 --progress-bar -o "$dest.part" "$(omarchy_repo_url)/$file" >&2 ||
      { err "Download failed: $(omarchy_repo_url)/$file"; return 1; }
    if [[ -n $sum ]] && ! echo "$sum  $dest.part" | sha256sum -c --status; then
      rm -f "$dest.part"
      err "sha256 mismatch for $file — the download is corrupt or the release changed mid-run."
      return 1
    fi
    mv "$dest.part" "$dest"
  fi
  echo "$dest"
}
