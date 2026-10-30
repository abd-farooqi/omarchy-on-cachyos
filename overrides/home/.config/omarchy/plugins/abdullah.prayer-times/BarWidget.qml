import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "abdullah.prayer-times"
  property string city: ""
  property var location: null
  property var days: []
  property string loadedDay: ""
  property string errorText: ""
  property date now: new Date()
  readonly property var utcOffset: location && location.timezone ? location.timezone.offset : undefined
  readonly property var display: Model.display(days, now, city, errorText, utcOffset)
  property bool opened: false
  function open() { opened = true }
  function close() { opened = false }
  function togglePanel() { opened = !opened }

  function refresh() {
    if (locate.running || fetch.running) return
    locate.running = true
  }

  function loadTimes() {
    var calendarDate = Model.dateParts(now, utcOffset)
    fetch.command = ["curl", "--fail", "--silent", "--show-error", "--max-time", "20",
      "https://api.aladhan.com/v1/calendar/" + calendarDate.year + "/" + calendarDate.month
      + "?latitude=" + location.latitude + "&longitude=" + location.longitude
      + "&method=1&school=1"]
    fetch.running = true
  }

  Component.onCompleted: refresh()

  SystemClock {
    precision: SystemClock.Minutes
    onDateChanged: {
      root.now = date
      if (root.loadedDay !== Model.dayKey(date, root.utcOffset) && !root.errorText) root.refresh()
    }
  }

  Timer {
    interval: 900000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: locate
    command: ["curl", "--fail", "--silent", "--show-error", "--max-time", "15",
      "https://ipwho.is/?fields=success,city,country,latitude,longitude,timezone"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var result = JSON.parse(text)
          if (result.success !== true || !result.city || typeof result.latitude !== "number"
              || typeof result.longitude !== "number" || !result.timezone
              || typeof result.timezone.offset !== "number") throw new Error("Invalid location")
          var label = result.city + ", " + result.country
          if (label !== root.city) root.days = []
          root.city = label
          root.location = result
          root.errorText = ""
          root.loadTimes()
        } catch (error) {
          root.errorText = "Unable to detect city by IP. Click to retry."
        }
      }
    }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) root.errorText = "IP location unavailable. Click to retry."
    }
  }

  Process {
    id: fetch
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var response = JSON.parse(text)
          if (response.code !== 200 || !Array.isArray(response.data) || !response.data.length)
            throw new Error("Invalid prayer timetable")
          root.days = response.data
          root.loadedDay = Model.dayKey(root.now, root.utcOffset)
          root.errorText = ""
        } catch (error) {
          root.errorText = "Unable to update. Click to retry."
        }
      }
    }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) root.errorText = "Offline or service unavailable. Click to retry."
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.display.text
    tooltipText: ""
    fontSize: Style.font.caption
    horizontalMargin: 8
    onPressed: root.togglePanel()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)

        Text {
          text: "PRAYER TIMES"
          color: Commons.Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.5
          font.bold: true
        }
        Text {
          width: parent.width
          text: root.city || "Detecting your city..."
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          text: (root.display.date || Qt.formatDate(root.now, "d MMM yyyy")) + "  /  Hanafi"
          color: Commons.Color.foreground
          opacity: 0.65
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        PanelSeparator { width: parent.width }
        Column {
          width: parent.width
          spacing: Style.space(4)
          Repeater {
            model: root.display.rows
            Rectangle {
              required property var modelData
              readonly property bool upcoming: modelData.name === root.display.next
              width: content.width
              height: Style.space(42)
              radius: Style.cornerRadius
              color: upcoming ? Style.selectedAccentFill : "transparent"
              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.name + (parent.upcoming ? "  / NEXT" : "")
                color: parent.upcoming ? Commons.Color.accent : Commons.Color.foreground
                opacity: modelData.name === "Sunrise" ? 0.55 : 1
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: parent.upcoming
              }
              Text {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.time
                color: parent.upcoming ? Commons.Color.accent : Commons.Color.foreground
                opacity: modelData.name === "Sunrise" ? 0.55 : 1
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: parent.upcoming
              }
            }
          }
        }
        Text {
          width: parent.width
          visible: root.errorText !== "" || !root.display.rows.length
          text: root.errorText || "Loading prayer times..."
          wrapMode: Text.WordWrap
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        PanelSeparator { width: parent.width }
        Text {
          width: parent.width
          text: "Auto location by IP · Karachi method\nPrayer start times, not mosque jamaat times."
          color: Commons.Color.foreground
          opacity: 0.55
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
        PanelActionButton {
          width: parent.width
          implicitHeight: Style.space(34)
          iconText: locate.running || fetch.running ? "Updating..." : "Refresh location & times"
          fontSize: Style.font.caption
          focusable: true
          onClicked: root.refresh()
        }
      }
    }
  }
}
