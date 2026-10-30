#!/bin/bash

omarchy-battery-status --shell

for battery in /sys/class/power_supply/*; do
  [[ -r $battery/type && $(<"$battery/type") == Battery ]] || continue
  status=$(<"$battery/status")
  [[ $status == Charging || $status == Discharging ]] || break

  if [[ -r $battery/energy_now && -r $battery/energy_full && -r $battery/power_now ]]; then
    remaining=$(<"$battery/energy_now")
    full=$(<"$battery/energy_full")
    rate=$(<"$battery/power_now")
  elif [[ -r $battery/charge_now && -r $battery/charge_full && -r $battery/current_now ]]; then
    remaining=$(<"$battery/charge_now")
    full=$(<"$battery/charge_full")
    rate=$(<"$battery/current_now")
  else
    break
  fi

  awk -v remaining="$remaining" -v full="$full" -v rate="$rate" -v status="$status" 'BEGIN {
    if (rate < 0) rate = -rate
    if (rate <= 0) exit
    amount = status == "Charging" ? full - remaining : remaining
    if (amount <= 0) exit
    minutes = int(amount / rate * 60 + 0.5)
    if (minutes < 1) minutes = 1
    hours = int(minutes / 60)
    minutes %= 60
    if (hours > 0 && minutes > 0) printf "time\t%dh %dm\n", hours, minutes
    else if (hours > 0) printf "time\t%dh\n", hours
    else printf "time\t%dm\n", minutes
  }'
  break
done
