import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "ScrollModel.js" as ScrollModel

BarWidget {
  id: root
  moduleName: "abdullah.desktop-status"
  property bool dnd: false
  property bool opened: false
  property var entries: []
  property string historyError: ""

  function refreshStatus() {
    if (!dndProc.running) dndProc.running = true
  }
  function refreshHistory() {
    if (!historyProc.running) historyProc.running = true
  }
  function open() { opened = true; refreshHistory(); refreshStatus() }
  function close() { opened = false }
  function togglePanel() { opened ? close() : open() }

  Component.onCompleted: refreshStatus()
  Timer {
    interval: 15000
    running: true
    repeat: true
    onTriggered: { root.refreshStatus(); if (root.opened) root.refreshHistory() }
  }
  Process {
    id: dndProc
    command: ["omarchy-shell", "notifications", "dndState"]
    stdout: StdioCollector { onStreamFinished: root.dnd = text.trim() === "on" }
  }
  Process {
    id: toggleDndProc
    command: ["omarchy-shell", "notifications", "toggleDnd"]
    stdout: StdioCollector { onStreamFinished: root.dnd = text.trim() === "on" }
  }
  Process {
    id: historyProc
    command: ["bash", "-c", "for f in \"$1\"/history/*.json \"$1\"/*.json; do [ ! -f \"$f\" ] || awk 1 \"$f\"; done", "--",
      Quickshell.env("HOME") + "/.local/state/omarchy/notifications"]
    stdout: StdioCollector {
      onStreamFinished: {
        var rows = []
        var seen = {}
        var malformed = false
        text.split("\n").forEach(function(line) {
          if (!line.trim()) return
          try {
            var entry = JSON.parse(line)
            var key = String(entry.timestamp) + ":" + String(entry.originalId || entry.id)
            if (seen[key]) return
            seen[key] = true
            rows.push({app: String(entry.app || "Notification"), summary: String(entry.summary || ""),
              body: String(entry.body || "").replace(/<[^>]*>/g, ""), timestamp: Number(entry.timestamp) || 0})
          } catch (error) { malformed = true }
        })
        rows.sort(function(a, b) { return b.timestamp - a.timestamp })
        root.entries = rows.slice(0, 30)
        root.historyError = malformed ? "Some older notifications could not be read." : ""
      }
    }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) root.historyError = "Notification history could not be read."
    }
  }

  implicitWidth: bell.implicitWidth
  implicitHeight: bell.implicitHeight
  BarIconButton {
      id: bell
      bar: root.bar
      text: root.dnd ? "󰂛" : "󰂚"
      tooltipText: root.dnd ? "Notifications paused · click for history" : "Notification history"
      onPressed: root.togglePanel()
  }

  KeyboardPanel {
    id: panel
    anchorItem: bell
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(Style.space(480))

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function(text) { if (text === "r") root.refreshHistory() }
      onTabRequested: function(direction) {
        if (dndButton.activeFocus) refreshButton.forceActiveFocus()
        else if (refreshButton.activeFocus) dndButton.forceActiveFocus()
        else if (direction < 0) refreshButton.forceActiveFocus()
        else dndButton.forceActiveFocus()
      }
      onMoveRequested: function(dx, dy) {
        historyScroll.contentY = Math.max(0, Math.min(
          Math.max(0, historyScroll.contentHeight - historyScroll.height),
          historyScroll.contentY + dy * Style.space(60)))
      }

      Column {
        id: heading
        width: parent.width
        spacing: Style.space(12)
        Text {
          text: "Notifications"
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }
        Row {
          width: parent.width
          PanelActionButton {
            id: dndButton
            width: parent.width * 0.65
            implicitHeight: Style.space(34)
            iconText: root.dnd ? "Do not disturb: on" : "Do not disturb: off"
            fontSize: Style.font.caption
            focusable: true
            onClicked: if (!toggleDndProc.running) toggleDndProc.running = true
          }
          PanelActionButton {
            id: refreshButton
            width: parent.width * 0.35
            implicitHeight: Style.space(34)
            iconText: "Refresh"
            fontSize: Style.font.caption
            focusable: true
            onClicked: root.refreshHistory()
          }
        }
        PanelSeparator { width: parent.width }
      }
      Flickable {
        id: historyScroll
        anchors.top: heading.bottom
        anchors.topMargin: Style.space(12)
        anchors.bottom: footer.top
        anchors.bottomMargin: Style.space(12)
        width: parent.width
        contentWidth: width
        contentHeight: historyColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        maximumFlickVelocity: Style.space(3500)
        flickDeceleration: 1500
        WheelHandler {
          target: null
          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
          onWheel: function(event) {
            historyScroll.cancelFlick()
            historyScroll.contentY = ScrollModel.scrollPosition(historyScroll.contentY,
              historyScroll.contentHeight, historyScroll.height, event.pixelDelta.y,
              event.angleDelta.y, Style.space(90))
            event.accepted = true
          }
        }
        Column {
          id: historyColumn
          width: parent.width
          spacing: Style.space(8)
          Text {
            visible: root.entries.length === 0
            width: parent.width
            text: root.historyError || "You're all caught up.\nNotifications will appear here."
            color: Commons.Color.foreground
            opacity: 0.65
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }
          Repeater {
            model: root.entries
            Rectangle {
              required property var modelData
              width: historyColumn.width
              implicitHeight: labels.implicitHeight + Style.space(24)
              color: Style.normalFill
              radius: Style.cornerRadius
              Column {
                id: labels
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(12)
                spacing: Style.space(5)
                Text {
                  width: parent.width
                  text: modelData.app + " · " + Qt.formatDateTime(new Date(modelData.timestamp), "ddd h:mm AP")
                  color: Commons.Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                }
                Text {
                  width: parent.width
                  text: modelData.summary
                  color: Commons.Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  wrapMode: Text.WordWrap
                  textFormat: Text.PlainText
                }
                Text {
                  width: parent.width
                  visible: text !== ""
                  text: modelData.body
                  color: Commons.Color.foreground
                  opacity: 0.7
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                  maximumLineCount: 4
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                }
              }
            }
          }
        }
      }
      Text {
        id: footer
        anchors.bottom: parent.bottom
        width: parent.width
        text: "Recent 30 notifications · Esc to close"
        color: Commons.Color.foreground
        opacity: 0.55
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }
}
