import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property var shell: null
  property string layout: "English (US)"
  property bool shiftHeld: false
  property bool activityVisible: false
  property bool showing: layout !== "English (US)" && activityVisible
  property var urduRows: [
    [{p:"Q",b:"ق",s:"ْ"},{p:"W",b:"و",s:"ؤ"},{p:"E",b:"ع",s:"ٰ"},{p:"R",b:"ر",s:"ڑ"},{p:"T",b:"ت",s:"ٹ"},{p:"Y",b:"ے",s:"َ"},{p:"U",b:"ء",s:"ئ"},{p:"I",b:"ی",s:"ِ"},{p:"O",b:"ہ",s:"ۃ"},{p:"P",b:"پ",s:"ُ"}],
    [{p:"A",b:"ا",s:"آ"},{p:"S",b:"س",s:"ص"},{p:"D",b:"د",s:"ڈ"},{p:"F",b:"ف",s:"ّ"},{p:"G",b:"گ",s:"غ"},{p:"H",b:"ح",s:"ھ"},{p:"J",b:"ج",s:"ض"},{p:"K",b:"ک",s:"خ"},{p:"L",b:"ل",s:"ٔ"}],
    [{p:"Z",b:"ز",s:"ذ"},{p:"X",b:"ش",s:"ژ"},{p:"C",b:"چ",s:"ث"},{p:"V",b:"ط",s:"ظ"},{p:"B",b:"ب",s:"."},{p:"N",b:"ن",s:"ں"},{p:"M",b:"م",s:"ؕ"},{p:",",b:"،",s:"<"},{p:".",b:"۔",s:">"},{p:"/",b:"/",s:"؟"}]
  ]
  property var pashtoRows: [
    [{p:"Q",b:"ض",s:"ْ"},{p:"W",b:"ص",s:"ً"},{p:"E",b:"ث",s:"ٍ"},{p:"R",b:"ق",s:"ٌ"},{p:"T",b:"ف",s:"ٍ"},{p:"Y",b:"غ",s:"َ"},{p:"U",b:"ع",s:"ِ"},{p:"I",b:"ه",s:"ّ"},{p:"O",b:"خ",s:"ځ"},{p:"P",b:"ح",s:"څ"}],
    [{p:"A",b:"ش",s:"ښ"},{p:"S",b:"س",s:"ۍ"},{p:"D",b:"ی",s:"ي"},{p:"F",b:"ب",s:"پ"},{p:"G",b:"ل",s:"أ"},{p:"H",b:"ا",s:"آ"},{p:"J",b:"ت",s:"ټ"},{p:"K",b:"ن",s:"ڼ"},{p:"L",b:"م",s:"ة"}],
    [{p:"Z",b:"ۍ",s:"ظ"},{p:"X",b:"ې",s:"ط"},{p:"C",b:"ز",s:"ژ"},{p:"V",b:"ر",s:"ء"},{p:"B",b:"ذ",s:"‌"},{p:"N",b:"د",s:"ډ"},{p:"M",b:"ږ",s:"ړ"},{p:",",b:"و",s:"،"},{p:".",b:"ژ",s:"."},{p:"/",b:"/",s:"؟"}]
  ]
  readonly property var rows: layout.indexOf("Pashto") >= 0 ? pashtoRows : urduRows
  property string title: layout.indexOf("Pashto") >= 0 ? "PASHTO" : "URDU"

  function refreshLayout() { layoutProcess.running = true }
  function handleActivity(line) {
    const event = String(line).trim()
    if (event.indexOf("shift ") === 0) {
      root.shiftHeld = event === "shift 1"
      if (root.layout !== "English (US)") {
        root.activityVisible = true
        hideTimer.restart()
      }
      return
    }
    if (event === "activity" && root.layout !== "English (US)") {
      root.activityVisible = true
      hideTimer.restart()
    }
  }

  Timer {
    id: layoutTimer
    interval: 500
    repeat: true
    running: true
    onTriggered: root.refreshLayout()
  }

  Timer {
    id: hideTimer
    interval: 2800
    repeat: false
    onTriggered: root.activityVisible = false
  }

  Process {
    id: layoutProcess
    command: ["bash", "-c", "hyprctl -j devices"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          const devices = JSON.parse(text || "{}").keyboards || []
          const active = devices.find(k => k.active_keymap && !String(k.name).startsWith("hl-virtual-keyboard"))
          if (active) root.layout = String(active.active_keymap)
        } catch (error) {
        }
      }
    }
  }

  Process {
    id: activityProcess
    command: [Quickshell.env("HOME") + "/.config/omarchy/plugins/abdullah.keyboard-overlay/KeyboardActivity.py"]
    running: true
    stdout: SplitParser { onRead: function(line) { root.handleActivity(line) } }
  }

  PanelWindow {
    visible: root.showing
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "abdullah-keyboard-overlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(54)
      width: Math.min(parent.width - Style.space(24), 780)
      height: 228
      radius: Style.space(14)
      color: Qt.rgba(0.025, 0.03, 0.045, 0.96)
      border.width: 2
      border.color: root.shiftHeld ? "#e9b44c" : "#5d8cff"

      Column {
        anchors.fill: parent
        anchors.margins: Style.space(12)
        spacing: Style.space(7)

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.title + "  ·  " + (root.shiftHeld ? "SHIFT LAYER" : "BASE LAYER")
          color: root.shiftHeld ? "#e9b44c" : "#8fb3ff"
          font.family: "sans-serif"
          font.pixelSize: 12
          font.bold: true
        }

        Repeater {
          model: root.rows
          delegate: Row {
            anchors.horizontalCenter: parent.horizontalCenter
              spacing: 5
            Repeater {
              model: modelData
              delegate: Rectangle {
                width: 68
                height: 50
                radius: 7
                color: root.shiftHeld ? Qt.rgba(0.91, 0.70, 0.30, 0.18) : Qt.rgba(0.36, 0.55, 1, 0.14)
                border.width: 1
                border.color: root.shiftHeld ? Qt.rgba(0.91, 0.70, 0.30, 0.65) : Qt.rgba(0.56, 0.70, 1, 0.45)
                Column {
                  anchors.centerIn: parent
                  spacing: 1
                  Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.p; color: "#9aa0aa"; font.pixelSize: 10; font.bold: true }
                  Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.shiftHeld ? modelData.s : modelData.b; color: "white"; font.pixelSize: 24; font.bold: true }
                }
              }
            }
          }
        }
      }
    }
  }
}
