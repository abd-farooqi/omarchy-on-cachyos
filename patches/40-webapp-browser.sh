# Omarchy opens web apps in Chromium unless the default browser is a Chromium
# fork it knows. Use the browser chosen during setup instead.
PATCH_FILE="$OMARCHY_BIN/omarchy-launch-webapp"

patch_needed()     { [[ -n ${WEBAPP_BROWSER:-} && $WEBAPP_BROWSER != chromium.desktop ]]; }
patch_applied()    { grep -qF "*) browser=\"$WEBAPP_BROWSER\" ;;" "$PATCH_FILE"; }
patch_applicable() { grep -qE '^\*\) browser="[^"]+\.desktop" ;;' "$PATCH_FILE"; }
patch_apply() {
  WEBAPP_BROWSER=$WEBAPP_BROWSER perl -pi -e 's/^\*\) browser="[^"]+\.desktop" ;;.*$/*) browser="$ENV{WEBAPP_BROWSER}" ;; # local patch (omarchy-on-cachyos)/' "$PATCH_FILE"
}
