function dateParts(date, offset) {
  if (typeof offset === "number") {
    var local = new Date(date.getTime() + offset * 1000)
    return {year: local.getUTCFullYear(), month: local.getUTCMonth() + 1,
      day: local.getUTCDate(), hour: local.getUTCHours(), minute: local.getUTCMinutes()}
  }
  return {year: date.getFullYear(), month: date.getMonth() + 1,
    day: date.getDate(), hour: date.getHours(), minute: date.getMinutes()}
}

function dayKey(date, offset) {
  var parts = dateParts(date, offset)
  return parts.year + "-" + parts.month + "-" + parts.day
}

function timeLabel(value) {
  var parts = String(value).split(" ")[0].split(":")
  var hour = Number(parts[0])
  return (hour % 12 || 12) + ":" + parts[1] + (hour < 12 ? " AM" : " PM")
}

function display(days, now, city, error, offset) {
  var clock = dateParts(now, offset)
  var today = days.find(function(day) {
    return Number(day.date.gregorian.day) === clock.day
      && Number(day.date.gregorian.month.number) === clock.month
      && Number(day.date.gregorian.year) === clock.year
  })
  if (!today) return {text: "Prayer times", rows: [], next: "", date: "", tooltip: (city ? "Prayer times for " + city : "Detecting city by IP") + "\n" + (error || "Loading...")}
  var prayers = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
  var rows = [city + " | Hanafi", today.date.readable, ""]
  ;["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"].forEach(function(name) {
    rows.push(name + "   " + timeLabel(today.timings[name]))
  })
  var minutes = clock.hour * 60 + clock.minute
  var next = prayers.find(function(name) {
    var parts = today.timings[name].split(" ")[0].split(":")
    return Number(parts[0]) * 60 + Number(parts[1]) > minutes
  })
  var label = next ? next + " " + timeLabel(today.timings[next]) : "Fajr tomorrow"
  rows.push("", "Location: automatic by IP", "Karachi calculation method | AlAdhan", "Calculated start times; mosque jamaat times may differ.")
  if (error) rows.push(error)
  return {text: label, tooltip: rows.join("\n"), next: next || "", date: today.date.readable,
    rows: ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"].map(function(name) {
      return {name: name, time: timeLabel(today.timings[name])}
    })}
}
