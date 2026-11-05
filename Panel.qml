import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The card: one painting, its title and date, what it is made of, where it
// hangs, and a few lines about it. Each opening brings a new painting, and
// the next one is already loading in the background so it appears at once.
//
// BarWidget.qml owns the bar icon and hands this panel the button to anchor
// against.
Panel {
  id: root
  moduleName: "mert.salon"
  ipcTarget: "mert.salon"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // ---- Catalog and position.
  property var catalog: ({ artists: {}, artistIds: [], paintings: [] })
  // Paintings shown so far, oldest first, and where in that trail we are.
  property var trail: []
  property int position: -1
  // Already chosen and loading, so the next step is instant.
  property int upcoming: -1
  // The painting on the card was seen; the next opening moves on.
  property bool seen: false
  property int failures: 0

  readonly property var only: setting("artists", [])
  readonly property int currentIndex: position >= 0 && position < trail.length ? trail[position] : -1
  readonly property var painting: currentIndex >= 0 ? catalog.paintings[currentIndex] : null
  readonly property var artist: painting ? catalog.artists[painting.artist] : null
  readonly property var upcomingPainting: upcoming >= 0 ? catalog.paintings[upcoming] : null
  readonly property var noteInfo: painting ? Model.note(painting, artist) : ({ text: "", aboutArtist: false })
  readonly property bool offline: failures >= 3

  readonly property string tooltip: painting
    ? strings.t("salon.tooltip").arg(painting.title).arg(Model.byline(painting, artist))
    : strings.t("salon.name")

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dimmed: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int cardWidth: Style.space(520)
  readonly property int maxImageHeight: Style.space(440)

  onOnlyChanged: if (catalog.paintings.length) restart()

  property FileView catalogFile: FileView {
    path: String(Qt.resolvedUrl("catalog.json")).replace(/^file:\/\//, "")
    printErrors: false
    onLoaded: {
      root.catalog = Model.parseCatalog(text())
      root.restart()
    }
    onLoadFailed: root.catalog = Model.parseCatalog("")
  }

  function restart() {
    trail = []
    position = -1
    upcoming = Model.pick(catalog, only, [])
    advance()
    seen = false
  }

  function advance() {
    if (upcoming < 0) return
    var nextTrail = trail.slice(0, position + 1)
    nextTrail.push(upcoming)
    if (nextTrail.length > 100) nextTrail = nextTrail.slice(nextTrail.length - 100)
    trail = nextTrail
    position = trail.length - 1
    upcoming = Model.pick(catalog, only, trail.slice(-Model.RECENT))
  }

  function next() {
    seen = false
    if (position < trail.length - 1) position += 1
    else advance()
  }

  function back() {
    if (position > 0) position -= 1
  }

  function retry() {
    failures = 0
    next()
  }

  function openLink() {
    var url = painting ? Model.safeLink(painting.link) : ""
    if (url !== "") Qt.openUrlExternally(url)
  }

  function open() {
    if (seen) next()
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    if (root.opened) seen = true
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // Fits the painting in the card without blowing a small picture up past
  // half again its size, where it starts to look soft.
  function frameSize(p) {
    var maxW = root.cardWidth
    if (!p || !p.width || !p.height) return Qt.size(maxW, root.maxImageHeight)
    var w = Math.min(maxW, p.width * 1.5)
    var h = w * p.height / p.width
    if (h > root.maxImageHeight) { h = root.maxImageHeight; w = h * p.width / p.height }
    return Qt.size(Math.round(w), Math.round(h))
  }

  // Loads the upcoming painting into the pixmap cache. Same source and
  // sourceSize as the visible image, so switching to it is a cache hit.
  Image {
    visible: false
    asynchronous: true
    cache: true
    source: root.upcomingPainting && !root.offline ? root.upcomingPainting.image : ""
    sourceSize.width: 1200
    sourceSize.height: 1200
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(root.cardWidth)
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onMoveRequested: function(dx, dy) {
        if (dx > 0) root.next()
        else if (dx < 0) root.back()
      }
      onActivateRequested: root.offline ? root.retry() : root.next()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "o" || t === "O") root.openLink()
      }

      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: scroller.width
          spacing: Style.space(10)

          // ---- The picture.
          Item {
            id: frame
            readonly property size fitted: root.frameSize(root.painting)
            width: parent.width
            height: root.painting ? fitted.height : Style.space(120)

            Image {
              id: picture
              anchors.centerIn: parent
              width: frame.fitted.width
              height: frame.fitted.height
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              cache: true
              smooth: true
              mipmap: true
              source: root.painting && !root.offline ? root.painting.image : ""
              sourceSize.width: 1200
              sourceSize.height: 1200
              opacity: status === Image.Ready ? 1 : 0

              onStatusChanged: {
                if (status === Image.Ready) root.failures = 0
                else if (status === Image.Error) {
                  // One broken link should not leave an empty card: move on,
                  // and only after several in a row say something is wrong.
                  root.failures += 1
                  if (!root.offline) Qt.callLater(root.next)
                }
              }
            }

            Text {
              anchors.centerIn: parent
              visible: picture.status !== Image.Ready
              width: parent.width - Style.space(40)
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: root.offline ? strings.t("salon.offline")
                : root.catalog.paintings.length === 0 ? strings.t("salon.empty")
                : strings.t("salon.loading")
              color: root.dimmed
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          // ---- Title and date.
          Column {
            width: parent.width
            spacing: Style.space(3)
            visible: root.painting !== null

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: root.painting ? root.painting.title : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: root.painting ? Model.byline(root.painting, root.artist) : ""
              color: Commons.Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
            }

            Text {
              width: parent.width
              visible: text !== ""
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: root.painting ? Model.facts(root.painting) : ""
              color: root.dimmed
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              width: parent.width
              visible: text !== ""
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: root.painting ? root.painting.collection : ""
              color: root.dimmed
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          // ---- A few lines about it.
          Column {
            width: parent.width
            spacing: Style.space(3)
            visible: root.noteInfo.text !== ""

            Text {
              visible: root.noteInfo.aboutArtist
              textFormat: Text.PlainText
              text: strings.t("salon.aboutArtist").toUpperCase()
              color: root.dimmed
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              maximumLineCount: 7
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: root.noteInfo.text
              color: root.foreground
              lineHeight: 1.15
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          // ---- Keys.
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: strings.t("salon.keys")
            color: root.dimmed
            opacity: 0.8
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
