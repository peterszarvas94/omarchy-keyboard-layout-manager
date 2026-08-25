import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "LayoutModel.js" as Model

Panel {
  id: root
  moduleName: "io.github.peterszarvas94.keyboard-layout-manager"
  ipcTarget: ""
  manageIpc: false

  property Item anchorItem: null
  property Item hostWidget: null
  property string keyboardName: ""
  property var configured: []
  property int activeIndex: 0
  readonly property string currentLayout: activeIndex >= 0 && activeIndex < configured.length
    ? Model.layoutLabel(configured[activeIndex]) : ""
  property var catalog: []
  property string searchQuery: ""
  property int selectedRow: 0
  property int selectedButton: 0
  property bool cursorActive: false
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/keyboard-layout-manager"
  property string persistedLayout: ""
  property bool stateLoaded: false
  property bool devicesLoaded: false
  property bool restoreAttempted: false
  property bool sessionLocked: false

  readonly property color foreground: Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: Style.font.family

  function open() {
    searchQuery = ""
    selectedRow = 0
    selectedButton = 0
    cursorActive = false
    searchField.text = ""
    refresh()
    root.controller.show()
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }
  function closeForPopoutSwitch() { root.close() }
  function requestClose() { root.close() }

  function refresh() {
    devices.running = true
    if (!catalogProcess.running) catalogProcess.running = true
  }

  function filteredCatalog(query) {
    query = query === undefined ? searchQuery.toLowerCase() : query
    return catalog.filter(function(item) {
      return configured.indexOf(item.code) === -1
        && (!query || item.code.toLowerCase().indexOf(query) !== -1 || item.description.toLowerCase().indexOf(query) !== -1)
    })
  }

  function updateDisplayedCatalog(query) {
    displayedCatalogModel.clear()
    var rows = filteredCatalog(query)
    for (var i = 0; i < rows.length; i++) {
      displayedCatalogModel.append({
        layoutCode: rows[i].code,
        layoutDescription: rows[i].description
      })
    }
  }

  function switchLayout(index) {
    if (index < 0 || index >= configured.length) return
    root.bar.run("hyprctl switchxkblayout all " + index)
    persistLayout(index)
    refreshTimer.restart()
    cursorActive = false
  }

  function persistLayout(index) {
    var layout = String(configured[index] || "").toLowerCase()
    if (!layout) return
    Quickshell.execDetached([
      "bash", "-c",
      "set -e; mkdir -p \"$1\"; printf '%s\\n' \"$2\" > \"$1/layout\"",
      "keyboard-layout-manager", stateDir, layout
    ])
  }

  function restoreLayout() {
    if (restoreAttempted || !stateLoaded || !devicesLoaded || !root.bar) return
    restoreAttempted = true
    var index = configured.indexOf(persistedLayout)
    if (index >= 0 && index !== activeIndex) {
      root.bar.run("hyprctl switchxkblayout all " + index)
      refreshTimer.restart()
    }
  }

  function updateInputFile(operation, value) {
    var script = [
      "set -e",
      "file=$(readlink -f \"$HOME/.config/hypr/input.lua\")",
      "value=\"$1\"",
      operation === "add" ?
        "sed -i -E 's/(kb_layout[[:space:]]*=[[:space:]]*\"[^\"]*)(\".*)/\\1,'\"$value\"'\\2/' \"$file\"" :
        "layouts=$(sed -nE 's/^[[:space:]]*kb_layout[[:space:]]*=[[:space:]]*\"([^\"]*)\".*$/\\1/p' \"$file\")\nremove_index() { local result=(); local i=0; local part; IFS=',' read -r -a parts <<< \"$1\"; for part in \"${parts[@]}\"; do [[ $i -ne $value ]] && result+=(\"$part\"); i=$((i + 1)); done; local IFS=','; printf '%s' \"${result[*]}\"; }\nnext_layouts=$(remove_index \"$layouts\")\nsed -i -E 's/(kb_layout[[:space:]]*=[[:space:]]*\")[^\"]*(\".*)/\\1'\"$next_layouts\"'\\2/' \"$file\"",
      "hyprctl reload"
    ].join("\n")
    root.close()
    Quickshell.execDetached(["bash", "-c", script, "keyboard-layout-manager", String(value)])
  }

  function addLayout(item) {
    if (!item || configured.indexOf(item.code) !== -1) return
    updateInputFile("add", item.code)
  }

  function removeLayout(index) {
    if (configured.length <= 1 || index < 0 || index >= configured.length) return
    updateInputFile("remove", index)
  }

  function moveCursor(dx, dy) {
    var rows = configured.length + displayedCatalogModel.count
    if (!rows) return
    if (!cursorActive) {
      setCursor(0, 0)
      return
    }
    if (dy !== 0) {
      if (dy < 0 && selectedRow === 0) {
        cursorActive = false
        searchField.forceActiveFocus()
        return
      }
      if (dy > 0 && selectedRow === rows - 1) {
        cursorActive = false
        searchField.forceActiveFocus()
        return
      }
      selectedRow += dy
      selectedButton = 0
    } else if (dx !== 0) {
      selectedButton = Math.max(0, Math.min(actionCount(selectedRow), selectedButton + dx))
    }
  }

  function actionCount(row) {
    if (row < configured.length) return configured.length > 1 ? 1 : 0
    return 0
  }

  function setCursor(row, button) {
    cursorActive = true
    selectedRow = row
    selectedButton = button
    clampCursor()
  }

  function clampCursor() {
    var rows = configured.length + displayedCatalogModel.count
    if (!rows) {
      selectedRow = 0
      selectedButton = 0
      return
    }
    selectedRow = Math.max(0, Math.min(selectedRow, rows - 1))
    selectedButton = Math.max(0, Math.min(selectedButton, actionCount(selectedRow)))
  }

  function moveTabCursor(direction) {
    var rows = configured.length + displayedCatalogModel.count
    if (!rows) return

    if (!cursorActive) {
      if (direction > 0) setCursor(0, 0)
      else searchField.forceActiveFocus()
      return
    }

    var lastButton = actionCount(selectedRow)
    if (direction > 0) {
      if (selectedButton < lastButton) selectedButton++
      else if (selectedRow < rows - 1) {
        selectedRow++
        selectedButton = 0
      } else {
        cursorActive = false
        searchField.forceActiveFocus()
      }
    } else if (selectedButton > 0) {
      selectedButton--
    } else if (selectedRow > 0) {
      selectedRow--
      selectedButton = actionCount(selectedRow)
    } else {
      cursorActive = false
      searchField.forceActiveFocus()
    }
  }

  function activateCursor() {
    if (selectedRow < configured.length) {
      if (selectedButton === 0) switchLayout(selectedRow)
      else removeLayout(selectedRow)
    } else {
      var item = displayedCatalogModel.get(selectedRow - configured.length)
      if (item) addLayout({ code: item.layoutCode, description: item.layoutDescription })
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      var name = String(event.name)
      if (name.indexOf("activelayout") !== -1) refreshDevices()
      if (event && event.name === "configreloaded") refresh()
      if (name === "openlayer" || name === "closelayer" || name.indexOf("activelayout") !== -1)
        lockProbeDelay.restart()
    }
  }

  function refreshDevices() { devices.running = true }

  onBarChanged: root.restoreLayout()

  Process {
    id: devices
    command: ["hyprctl", "-j", "devices"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var hadDevices = root.devicesLoaded
          var state = Model.configuredLayouts(JSON.parse(text || "{}"))
          root.keyboardName = state.keyboard
          root.configured = state.layouts
          root.activeIndex = state.activeIndex
          root.devicesLoaded = true
          if (!hadDevices) root.restoreLayout()
          else if (!root.sessionLocked) {
            if (!root.restoreAttempted) root.restoreLayout()
            else root.persistLayout(state.activeIndex)
          }
          root.updateDisplayedCatalog()
        } catch (e) { }
      }
    }
  }

  Process {
    id: catalogProcess
    command: ["xkbcli", "list", "--load-exotic"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.catalog = Model.parseLayouts(text)
        root.updateDisplayedCatalog()
      }
    }
  }

  Process {
    id: stateReader
    command: ["bash", "-c", "cat \"$1/layout\" 2>/dev/null || true", "keyboard-layout-manager", root.stateDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.persistedLayout = String(text || "").trim().toLowerCase()
        root.stateLoaded = true
        root.restoreLayout()
      }
    }
  }

  Process {
    id: lockProbe
    command: ["omarchy-shell", "lock", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var locked = false
        try { locked = JSON.parse(String(text || "{}")).locked === true } catch (e) { return }
        if (locked !== root.sessionLocked) {
          var wasLocked = root.sessionLocked
          root.sessionLocked = locked
          if (wasLocked && !locked) {
            root.restoreAttempted = false
            root.refreshDevices()
          }
        }
      }
    }
  }

  Timer { id: refreshTimer; interval: 500; onTriggered: root.refreshDevices() }
  Timer {
    id: lockProbeDelay
    interval: 100
    repeat: false
    onTriggered: if (!lockProbe.running) lockProbe.running = true
  }

  Component.onCompleted: {
    stateReader.running = true
    refresh()
  }

  ListModel { id: displayedCatalogModel }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: fittedContentWidth(Style.space(620))
    contentHeight: fittedContentHeight(content.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.requestClose()
      onTabRequested: function(direction) { root.moveTabCursor(direction) }
      onTextKey: function(t) { if (t === "/") { searchField.forceActiveFocus(); searchField.selectAll() } }

      ColumnLayout {
        id: content
        anchors.fill: parent
        spacing: Style.space(12)

        PanelHero {
          Layout.fillWidth: true
          title: "Keyboard Layouts"
          meta: root.configured.length + " configured"
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component { Text { text: "󰌌"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.display } }
        }

        TextField {
          id: searchField
          Layout.fillWidth: true
          placeholderText: "Search layouts to add"
          foreground: root.foreground
          accent: root.accent
          font.family: root.fontFamily
          onTextChanged: {
            var query = searchField.text.trim().toLowerCase()
            root.searchQuery = query
            root.updateDisplayedCatalog(query)
            root.clampCursor()
          }
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
            else if (event.key === Qt.Key_Down) {
              if (root.configured.length + displayedCatalogModel.count > 0) root.setCursor(0, 0)
              keyCatcher.forceActiveFocus()
              event.accepted = true
            }
            else if (event.key === Qt.Key_Up) {
              var lastRow = root.configured.length + displayedCatalogModel.count - 1
              if (lastRow >= 0) root.setCursor(lastRow, 0)
              keyCatcher.forceActiveFocus()
              event.accepted = true
            }
            else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
              var direction = (event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1
              if (direction > 0) root.setCursor(0, 0)
              else {
                var lastRow = root.configured.length + displayedCatalogModel.count - 1
                if (lastRow >= 0) root.setCursor(lastRow, root.actionCount(lastRow))
              }
              if (root.cursorActive) keyCatcher.forceActiveFocus()
              event.accepted = true
            }
          }
        }

        Text {
          text: "Click a configured layout to switch. Search to add another."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          Layout.fillWidth: true
        }

        PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }
        PanelSectionHeader { text: "CONFIGURED LAYOUTS"; foreground: root.foreground; fontFamily: root.fontFamily }

        Repeater {
          model: root.configured
          CursorSurface {
            required property string modelData
            required property int index
            Layout.fillWidth: true
            implicitHeight: Style.space(40)
            foreground: root.foreground
            hasCursor: root.cursorActive && root.selectedRow === index
            current: root.activeIndex === index
            Text { anchors.left: parent.left; anchors.leftMargin: Style.space(10); anchors.right: switchButton.left; anchors.rightMargin: Style.space(6); anchors.verticalCenter: parent.verticalCenter; text: Model.layoutLabel(modelData) + (root.activeIndex === index ? "  (active)" : ""); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body }
            MouseArea { anchors.fill: parent; onClicked: root.switchLayout(index) }
            PanelActionButton { id: switchButton; anchors.right: removeButton.left; anchors.rightMargin: Style.space(2); anchors.verticalCenter: parent.verticalCenter; iconText: "󰁔"; tooltipText: "Switch layout"; foreground: root.foreground; fontFamily: root.fontFamily; hasCursor: root.cursorActive && root.selectedRow === index && root.selectedButton === 0; onClicked: root.switchLayout(index) }
            PanelActionButton { id: removeButton; visible: root.configured.length > 1; anchors.right: parent.right; anchors.rightMargin: Style.space(6); anchors.verticalCenter: parent.verticalCenter; iconText: ""; tooltipText: "Remove layout"; foreground: root.foreground; fontFamily: root.fontFamily; hasCursor: root.cursorActive && root.selectedRow === index && root.selectedButton === 1; onClicked: root.removeLayout(index) }
          }
        }

        PanelSectionHeader { text: "ADD LAYOUT"; foreground: root.foreground; fontFamily: root.fontFamily; visible: displayedCatalogModel.count > 0 }
        ListView {
          id: catalogList
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          model: displayedCatalogModel
          delegate: CursorSurface {
            required property string layoutCode
            required property string layoutDescription
            required property int index
            width: catalogList.width
            implicitHeight: Style.space(40)
            foreground: root.foreground
            hasCursor: root.cursorActive && root.selectedRow === root.configured.length + index
            Text { anchors.left: parent.left; anchors.leftMargin: Style.space(10); anchors.right: addButton.left; anchors.rightMargin: Style.space(6); anchors.verticalCenter: parent.verticalCenter; text: Model.layoutLabel(layoutCode) + "  " + layoutDescription; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
            MouseArea { anchors.fill: parent; onClicked: root.addLayout({ code: layoutCode, description: layoutDescription }) }
            PanelActionButton { id: addButton; anchors.right: parent.right; anchors.rightMargin: Style.space(6); anchors.verticalCenter: parent.verticalCenter; iconText: ""; tooltipText: "Add layout"; foreground: root.foreground; fontFamily: root.fontFamily; hasCursor: root.cursorActive && root.selectedRow === root.configured.length + index && root.selectedButton === 0; onClicked: root.addLayout({ code: layoutCode, description: layoutDescription }) }
          }
        }
      }
    }
  }
}
