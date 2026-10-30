import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "abdullah.system-usage"
  property var previousSamples: ({})
  property var cpu: null
  property var coreRows: []
  property var ram: null
  property var processor: ({model: "Processor", frequency: "Unavailable"})
  property string load: "Unavailable"
  property string uptimeText: "Unavailable"
  property string governor: "Unavailable"
  property string powerProfile: ""
  property string scalingDriver: ""
  property string preference: "Unavailable"
  property var throttleValues: null
  property string throttling: "Measuring..."
  property var processSnapshot: null
  property var consumers: null
  property var pressure: null
  readonly property var consumerRows: consumers ? (cpuPanel ? (consumers.ready ? consumers.cpu : []) : consumers.memory) : []
  readonly property var profileInfo: Model.powerState(powerProfile, governor, scalingDriver)
  property string temperaturePath: ""
  property string temperature: "Unavailable"
  property bool opened: false
  property string panelKind: "cpu"
  readonly property bool cpuPanel: panelKind === "cpu"
  readonly property var detailRows: cpuPanel ? [
    {label: "Average clock", value: processor.frequency},
    {label: "Temperature", value: temperature},
    {label: "Load (1 / 5 / 15 min)", value: load},
    {label: "Logical CPUs", value: String(coreRows.length)},
    {label: "Power profile", value: profileInfo.profile},
    {label: "Power preference", value: preference},
    {label: "Thermal throttling", value: throttling},
    {label: "Uptime", value: uptimeText}
  ] : [
    {label: "Used", value: ram ? ram.used + " GiB" : "--"},
    {label: "Available", value: ram ? ram.available + " GiB" : "--"},
    {label: "Free", value: ram ? ram.free + " GiB" : "--"},
    {label: "File cache", value: ram ? ram.cache + " GiB" : "--"},
    {label: "Shared memory", value: ram ? ram.shared + " GiB" : "--"},
    {label: "Swap", value: ram ? ram.swap + " / " + ram.swapTotal + " GiB" : "--"},
    {label: "Memory stalls (10s)", value: pressure ? pressure.some : "Unavailable"},
    {label: "Full stalls (10s)", value: pressure ? pressure.full : "Unavailable"}
  ]

  function refreshDetails() {
    if (!processProc.running) processProc.running = true
    if (cpuPanel) {
      processorFile.reload()
      loadFile.reload()
      uptimeFile.reload()
      governorFile.reload()
      driverFile.reload()
      preferenceFile.reload()
      if (!throttleProc.running) throttleProc.running = true
      if (!powerProfileProc.running) powerProfileProc.running = true
      if (temperaturePath) temperatureFile.reload()
    } else { memoryFile.reload(); pressureFile.reload() }
  }
  function open(kind) {
    if (!opened) { processSnapshot = null; consumers = null }
    scroll.contentY = 0
    if (!opened || panelKind !== kind) {
      throttleValues = null
      throttling = "Measuring..."
    }
    panelKind = kind === "memory" ? "memory" : "cpu"
    opened = true
    refreshDetails()
  }
  function close() { opened = false }
  function togglePanel(kind) {
    if (opened && panelKind === kind) close()
    else open(kind)
  }

  Component.onCompleted: sensorDiscovery.running = true

  QtObject {
    id: popupOwner
    function close() { root.close() }
  }

  FileView {
    id: cpuFile
    path: "/proc/stat"
    onLoaded: {
      var samples = Model.cpuSamples(text())
      root.cpu = Model.cpuPercent(root.previousSamples.cpu, samples.cpu)
      root.coreRows = Object.keys(samples).filter(function(name) { return name !== "cpu" }).map(function(name) {
        return {name: name, percent: Model.cpuPercent(root.previousSamples[name], samples[name])}
      })
      root.previousSamples = samples
    }
  }
  FileView {
    id: memoryFile
    path: "/proc/meminfo"
    onLoaded: root.ram = Model.memory(text())
  }
  FileView {
    id: processorFile
    path: "/proc/cpuinfo"
    onLoaded: root.processor = Model.cpuInfo(text())
  }
  FileView {
    id: loadFile
    path: "/proc/loadavg"
    onLoaded: root.load = Model.loadAverage(text())
  }
  FileView {
    id: uptimeFile
    path: "/proc/uptime"
    onLoaded: root.uptimeText = Model.uptime(text())
  }
  FileView {
    id: driverFile
    path: "/sys/devices/system/cpu/cpu0/cpufreq/scaling_driver"
    printErrors: false
    onLoaded: root.scalingDriver = text().trim()
    onLoadFailed: root.scalingDriver = ""
  }
  Process {
    id: powerProfileProc
    command: ["timeout", "2s", "powerprofilesctl", "get"]
    stdout: StdioCollector { onStreamFinished: root.powerProfile = text.trim() }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) root.powerProfile = ""
    }
  }
  FileView {
    id: governorFile
    path: "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
    printErrors: false
    onLoaded: root.governor = text().trim() || "Unavailable"
    onLoadFailed: root.governor = "Unavailable"
  }
  FileView {
    id: preferenceFile
    path: "/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference"
    printErrors: false
    onLoaded: root.preference = Model.powerPreference(text())
    onLoadFailed: root.preference = "Unavailable"
  }
  Process {
    id: throttleProc
    command: ["bash", "-c", "for f in /sys/devices/system/cpu/cpu[0-9]*/thermal_throttle/*_throttle_count /sys/devices/system/cpu/cpu[0-9]*/thermal_throttle/*_throttle_total_time_ms; do if [ -r \"$f\" ]; then read -r value < \"$f\"; printf '%s %s\\n' \"$f\" \"$value\"; fi; done"]
    stdout: StdioCollector {
      onStreamFinished: {
        var sample = Model.throttleSample(text, root.throttleValues)
        root.throttleValues = sample.values
        root.throttling = sample.status
      }
    }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) { root.throttleValues = null; root.throttling = "Unavailable" }
    }
  }
  Process {
    id: sensorDiscovery
    command: ["bash", "-c", "for d in /sys/class/hwmon/hwmon*; do case $(cat \"$d/name\" 2>/dev/null) in coretemp|k10temp|zenpower|cpu_thermal) if [ -r \"$d/temp1_input\" ]; then printf '%s' \"$d/temp1_input\"; break; fi;; esac; done"]
    stdout: StdioCollector { onStreamFinished: root.temperaturePath = text.trim() }
  }
  Process {
    id: processProc
    command: ["bash", decodeURIComponent(Qt.resolvedUrl("processes.sh").toString().replace(/^file:\/\//, ""))]
    stdout: StdioCollector {
      onStreamFinished: {
        root.consumers = Model.processUsage(text, root.processSnapshot)
        root.processSnapshot = root.consumers ? root.consumers.snapshot : null
      }
    }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) { root.consumers = null; root.processSnapshot = null }
    }
  }
  FileView {
    id: pressureFile
    path: "/proc/pressure/memory"
    printErrors: false
    onLoaded: root.pressure = Model.memoryPressure(text())
    onLoadFailed: root.pressure = null
  }
  FileView {
    id: temperatureFile
    path: root.temperaturePath
    printErrors: false
    onLoaded: {
      var value = Number(text().trim())
      root.temperature = isFinite(value) && value > 0 ? Math.round(value / 1000) + "°C" : "Unavailable"
    }
    onLoadFailed: root.temperature = "Unavailable"
  }
  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: {
      cpuFile.reload()
      memoryFile.reload()
      if (root.opened) root.refreshDetails()
    }
  }
  IpcHandler {
    target: "abdullah.system-usage"
    function openCpu(): void { root.open("cpu") }
    function openMemory(): void { root.open("memory") }
    function close(): void { root.close() }
  }

  implicitWidth: content.implicitWidth
  implicitHeight: content.implicitHeight
  Row {
    id: content
    WidgetButton {
      id: cpuButton
      bar: root.bar
      text: " " + (root.cpu === null ? "--" : root.cpu) + "%"
      fontSize: Style.font.caption
      horizontalMargin: 7
      tooltipText: ""
      onPressed: root.togglePanel("cpu")
    }
    WidgetButton {
      id: ramButton
      bar: root.bar
      text: "󰍛 " + (root.ram ? root.ram.percent : "--") + "%"
      fontSize: Style.font.caption
      horizontalMargin: 7
      tooltipText: ""
      onPressed: root.togglePanel("memory")
    }
  }

  Rectangle {
    parent: root.cpuPanel ? cpuButton : ramButton
    visible: root.opened
    width: parent.labelWidth
    height: Style.space(2)
    x: Math.round((parent.width - width) / 2)
    y: root.bar && root.bar.position === "bottom" ? Style.space(2)
      : parent.height - height - Style.space(2)
    radius: height / 2
    color: Commons.Color.accent
    opacity: 0.9
    z: 50
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.cpuPanel ? cpuButton : ramButton
    owner: popupOwner
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(370))
    contentHeight: panel.fittedContentHeight(Math.min(info.implicitHeight, Style.space(680)))

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()
      onMoveRequested: function(dx, dy) {
        if (dx) root.open(root.cpuPanel ? "memory" : "cpu")
        scroll.contentY = Math.max(0, Math.min(Math.max(0, scroll.contentHeight - scroll.height),
          scroll.contentY + dy * Style.space(50)))
      }
      onTabRequested: root.open(root.cpuPanel ? "memory" : "cpu")
      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: info.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        WheelHandler {
          target: null
          onWheel: function(event) {
            var delta = event.pixelDelta.y || event.angleDelta.y / 120 * Style.space(60)
            scroll.contentY = Math.max(0, Math.min(Math.max(0, scroll.contentHeight - scroll.height), scroll.contentY - delta))
            event.accepted = true
          }
        }
        Column {
          id: info
          width: parent.width
          spacing: Style.space(12)
          Text {
            text: root.cpuPanel ? "CPU" : "Memory"
            color: Commons.Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Text {
            width: parent.width
            text: root.cpuPanel ? root.processor.model : root.ram ? root.ram.total + " GiB total RAM" : "Reading memory..."
            color: Commons.Color.foreground
            opacity: 0.65
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
          Text {
            text: root.cpuPanel ? (root.cpu === null ? "Measuring..." : root.cpu + "% usage")
              : root.ram ? root.ram.percent + "% used" : "Measuring..."
            color: Commons.Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Rectangle {
            width: parent.width
            height: Style.space(5)
            radius: height / 2
            color: Style.normalFill
            Rectangle {
              width: parent.width * Math.max(0, Math.min(100, root.cpuPanel ? (root.cpu || 0) : root.ram ? root.ram.percent : 0)) / 100
              height: parent.height
              radius: parent.radius
              color: Commons.Color.accent
            }
          }
          Repeater {
            model: root.detailRows
            Item {
              required property var modelData
              width: info.width
              height: Style.space(27)
              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                color: Commons.Color.foreground
                opacity: 0.65
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.value
                color: Commons.Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }
          PanelSeparator { width: parent.width }
          Text {
            text: root.cpuPanel ? "TOP CPU CONSUMERS" : "TOP RAM CONSUMERS"
            color: Commons.Color.foreground
            opacity: 0.65
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }
          Text {
            visible: !root.consumerRows.length
            text: root.consumers && root.cpuPanel && !root.consumers.ready ? "Measuring..." : "Reading processes..."
            color: Commons.Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Repeater {
            model: root.consumerRows
            Item {
              required property var modelData
              width: info.width
              height: Style.space(22)
              Text {
                width: parent.width - consumerValue.width - Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.name + (modelData.count > 1 ? " (" + modelData.count + ")" : "")
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Commons.Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
              Text {
                id: consumerValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.value
                color: Commons.Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }
          Text {
            width: parent.width
            text: root.cpuPanel ? "Grouped by process name · 100% = one CPU core"
              : "Grouped by process name · RSS includes shared pages\nStalls: time waiting for memory; full = all active tasks."
            wrapMode: Text.WordWrap
            color: Commons.Color.foreground
            opacity: 0.55
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          PanelSeparator { width: parent.width; visible: root.cpuPanel }
          Text {
            visible: root.cpuPanel
            text: "PER-CORE USAGE"
            color: Commons.Color.foreground
            opacity: 0.65
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }
          Grid {
            id: cores
            visible: root.cpuPanel
            width: parent.width
            columns: 4
            spacing: Style.space(10)
            Repeater {
              model: root.coreRows
              Column {
                required property var modelData
                width: (cores.width - cores.spacing * 3) / 4
                spacing: Style.space(6)
                Text {
                  text: modelData.name.replace("cpu", "CPU ") + "  " + (modelData.percent === null ? "--" : modelData.percent) + "%"
                  color: Commons.Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
                Rectangle {
                  width: parent.width
                  height: Style.space(3)
                  color: Style.normalFill
                  Rectangle {
                    width: parent.width * (modelData.percent || 0) / 100
                    height: parent.height
                    color: Commons.Color.accent
                  }
                }
              }
            }
          }
          Text {
            width: parent.width
            text: root.cpuPanel ? "Kernel governor: " + root.profileInfo.governor + "\nThrottling: new events/time since last sample.\nLive every second · Tab for memory · Esc to close"
              : "Available includes reclaimable cache. Figures overlap; don't add the rows.\nLive every second · Tab for CPU · Esc to close"
            color: Commons.Color.foreground
            opacity: 0.55
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
