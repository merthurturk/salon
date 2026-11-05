import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The painting as large as the screen allows, on a dark ground, with its
// name underneath. Esc, Z or a click goes back to the card; Space and the
// arrows keep walking through paintings here; F saves the one on screen.
OverlayWindow {
  id: view

  property var painting: null
  property string byline: ""
  property string source: ""
  property bool favorite: false
  property string fontFamily: Style.font.family

  signal closeRequested()
  signal nextRequested()
  signal backRequested()
  signal favoriteRequested()

  WlrLayershell.namespace: "mert-salon"

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0.04, 0.04, 0.04, 0.96)
  }

  MouseArea {
    anchors.fill: parent
    onClicked: view.closeRequested()
  }

  Item {
    id: keys
    anchors.fill: parent
    focus: view.shown
    Keys.onPressed: function(event) {
      var t = event.text
      if (event.key === Qt.Key_Escape || t === "z" || t === "Z" || t === "q") view.closeRequested()
      else if (event.key === Qt.Key_Space || event.key === Qt.Key_Right || t === "l") view.nextRequested()
      else if (event.key === Qt.Key_Left || t === "h") view.backRequested()
      else if (t === "f") view.favoriteRequested()
      else return
      event.accepted = true
    }
  }

  onShownChanged: if (shown) keys.forceActiveFocus()

  Image {
    id: big
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -caption.height / 2
    width: parent.width - Style.space(120)
    height: parent.height - Style.space(120) - caption.height
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    cache: true
    smooth: true
    mipmap: true
    source: view.shown ? view.source : ""
    sourceSize.width: 2400
    sourceSize.height: 2400
    opacity: status === Image.Ready ? 1 : 0
  }

  // Shown while the larger rendition decodes, so the screen is never blank.
  Text {
    anchors.centerIn: big
    visible: big.status !== Image.Ready
    textFormat: Text.PlainText
    text: big.status === Image.Error ? "×" : "…"
    color: "#808080"
    font.family: view.fontFamily
    font.pixelSize: Style.font.display
  }

  Column {
    id: caption
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(36)
    spacing: Style.space(4)

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(10)

      Text {
        textFormat: Text.PlainText
        text: view.painting ? view.painting.title : ""
        color: "#ececec"
        font.family: view.fontFamily
        font.pixelSize: Style.font.heading
        font.bold: true
      }

      Text {
        visible: view.favorite
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "󰋑"
        color: Commons.Color.accent
        font.family: view.fontFamily
        font.pixelSize: Style.font.heading
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: view.byline
      color: "#a0a0a0"
      font.family: view.fontFamily
      font.pixelSize: Style.font.subtitle
    }
  }
}
