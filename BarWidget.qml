import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// A palette in the bar. Left click opens the card with a painting, right
// click changes the painting without opening it, middle click opens the
// current painting's page in the browser.
BarWidget {
  id: root
  moduleName: "mert.salon"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  // The bar routes shell.summon/hide/toggle through these on the widget
  // itself, the same contract the clock and weather widgets keep.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  // For keybindings and scripts: omarchy-shell mert.salon <function>.
  IpcHandler {
    target: "mert.salon"

    function next(): void { if (panelLoader.item) panelLoader.item.next() }
    function favorite(): void { if (panelLoader.item) panelLoader.item.toggleFavorite() }
    function fullView(): void { if (panelLoader.item) panelLoader.item.showFullView() }
    function closeFullView(): void { if (panelLoader.item && panelLoader.item.fullView) panelLoader.item.closeFullView() }
    function favorites(): void {
      if (!panelLoader.item) return
      panelLoader.item.openGrid()
      if (!root.opened) root.open()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰏘"
    slotSize: Style.bar.statusSlot
    tooltipText: panelLoader.item && !root.opened ? panelLoader.item.tooltip : ""

    onPressed: function(b) {
      var panel = panelLoader.item
      if (!panel) return
      if (b === Qt.RightButton) panel.next()
      else if (b === Qt.MiddleButton) panel.openLink()
      else panel.toggle()
    }
  }
}
