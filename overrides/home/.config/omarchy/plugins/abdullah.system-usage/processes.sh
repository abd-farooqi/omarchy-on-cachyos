#!/usr/bin/env bash
set -u
read -r uptime _ < /proc/uptime
printf '%s\t%s\t%s\n' "$uptime" "$(getconf CLK_TCK)" "$(getconf PAGESIZE)"
for entry in /proc/[0-9]*; do
  stat=''
  { read -r stat < "$entry/stat"; } 2>/dev/null || continue
  name="${stat#*(}"
  name="${name%)*}"
  name="${name//$'\t'/ }"
  read -r -a fields <<< "${stat##*) }"
  [[ ${#fields[@]} -ge 22 ]] || continue
  [[ ${fields[11]} =~ ^[0-9]+$ && ${fields[12]} =~ ^[0-9]+$ && ${fields[19]} =~ ^[0-9]+$ && ${fields[21]} =~ ^[0-9]+$ ]] || continue
  printf '%s\t%s\t%s\t%s\t%s\n' "${entry##*/}" "${fields[19]}" \
    "$((fields[11] + fields[12]))" "${fields[21]}" "$name"
done
