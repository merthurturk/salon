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
// Favourites are kept by bin/salon, which writes favorites.json and tells
// Context Engine; this panel only reads that file and asks the helper for
// changes. G swaps the card for a grid of them; Z shows the painting large.
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

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string helper: pluginDir + "/bin/salon"
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/salon"

  // ---- Catalog and position.
  property var catalog: ({ artists: {}, artistIds: [], paintings: [], byKey: {} })
  // Paintings shown so far, oldest first, and where in that trail we are.
  property var trail: []
  property int position: -1
  // Already chosen and loading, so the next step is instant.
  property int upcoming: -1
  // The painting on the card was seen; the next opening moves on.
  property bool seen: false
  property int failures: 0

  // ---- Favourites.
  property var favorites: ({ keys: [], cached: {}, syncError: "" })
  // Taps not yet reflected in the file, so the heart answers at once.
  property var overrides: ({})
  readonly property var favoriteSet: {
    var set = {}
    for (var i = 0; i < favorites.keys.length; i++) set[favorites.keys[i]] = true
    for (var key in overrides) { if (overrides[key]) set[key] = true; else delete set[key] }
    return set
  }
  readonly property var favoriteKeys: {
    var keys = []
    for (var i = 0; i < favorites.keys.length; i++) if (favoriteSet[favorites.keys[i]]) keys.push(favorites.keys[i])
    for (var key in overrides) if (overrides[key] && keys.indexOf(key) < 0) keys.unshift(key)
    return keys
  }
  property bool favoritesOnly: false
  property bool showingGrid: false
  property int gridIndex: 0
  property bool fullView: false

  readonly property var only: setting("artists", [])
  readonly property int currentIndex: position >= 0 && position < trail.length ? trail[position] : -1
  readonly property var painting: currentIndex >= 0 ? catalog.paintings[currentIndex] : null
  readonly property var artist: painting ? catalog.artists[painting.artist] : null
  readonly property var upcomingPainting: upcoming >= 0 ? catalog.paintings[upcoming] : null
  readonly property var noteInfo: painting ? Model.note(painting, artist) : ({ text: "", aboutArtist: false })
  readonly property bool offline: failures >= 3
  readonly property bool currentIsFavorite: painting ? favoriteSet[painting.key] === true : false
  readonly property bool nothingToShow: favoritesOnly && favoriteKeys.length === 0

  readonly property string tooltip: painting
    ? strings.t("salon.tooltip").arg(painting.title).arg(Model.byline(painting, artist))
    : strings.t("salon.name")

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dimmed: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int cardWidth: Style.space(520)
  readonly property int maxImageHeight: Style.space(440)

  onOnlyChanged: if (catalog.paintings.length && !favoritesOnly) restart()

  property FileView catalogFile: FileView {
    path: root.pluginDir + "/catalog.json"
    printErrors: false
    onLoaded: {
      root.catalog = Model.parseCatalog(text())
      favoritesFile.reload()
      root.restart()
    }
    onLoadFailed: root.catalog = Model.parseCatalog("")
  }

  property FileView favoritesFile: FileView {
    path: root.stateDir + "/favorites.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.takeFavorites(text())
    onLoadFailed: root.takeFavorites("")
  }

  function takeFavorites(text) {
    favorites = Model.parseFavorites(text, catalog)
    // Drop the taps the file now agrees with.
    var still = {}
    var inFile = {}
    for (var i = 0; i < favorites.keys.length; i++) inFile[favorites.keys[i]] = true
    for (var key in overrides) if ((inFile[key] === true) !== overrides[key]) still[key] = overrides[key]
    overrides = still
  }

  // ---- The helper runs one command at a time; quick taps queue up.
  property var queue: []

  function runHelper(args) {
    queue = queue.concat([args])
    pump()
  }

  function pump() {
    if (helperProc.running || queue.length === 0) return
    helperProc.command = [root.helper].concat(queue[0])
    queue = queue.slice(1)
    helperProc.running = true
  }

  Process {
    id: helperProc
    onExited: {
      favoritesFile.reload()
      Qt.callLater(root.pump)
    }
  }

  // Favourites made on another machine arrive with the next sync.
  Timer {
    interval: 30 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.runHelper(["sync"])
  }

  function toggleFavorite(p) {
    p = p || root.painting
    if (!p) return
    var next = !(favoriteSet[p.key] === true)
    var o = {}
    for (var key in overrides) o[key] = overrides[key]
    o[p.key] = next
    overrides = o
    runHelper(["fav", next ? "add" : "remove", p.key])
  }

  // A kept copy of a favourite beats the website, which may drop it.
  function imageSource(p) {
    if (!p) return ""
    var cached = favorites.cached[p.key]
    return cached ? "file://" + root.stateDir + "/" + cached : p.image
  }

  // ---- Moving through paintings.
  function chooseNext() {
    var recent = trail.slice(-Model.RECENT)
    return favoritesOnly ? Model.pickFavorite(catalog, favoriteKeys, recent) : Model.pick(catalog, only, recent)
  }

  function restart() {
    trail = []
    position = -1
    upcoming = chooseNext()
    advance()
    seen = false
  }

  function advance() {
    if (upcoming < 0) upcoming = chooseNext()
    if (upcoming < 0) return
    var nextTrail = trail.slice(0, position + 1)
    nextTrail.push(upcoming)
    if (nextTrail.length > 100) nextTrail = nextTrail.slice(nextTrail.length - 100)
    trail = nextTrail
    position = trail.length - 1
    upcoming = chooseNext()
  }

  function next() {
    seen = false
    if (position < trail.length - 1) position += 1
    else advance()
  }

  function back() {
    if (position > 0) position -= 1
  }

  function show(index) {
    var nextTrail = trail.slice(0, position + 1)
    nextTrail.push(index)
    trail = nextTrail
    position = trail.length - 1
  }

  function retry() {
    failures = 0
    next()
  }

  function setFavoritesOnly(value) {
    if (favoritesOnly === value) return
    favoritesOnly = value
    upcoming = chooseNext()
    if (value && painting && favoriteSet[painting.key]) return
    advance()
  }

  function openGrid() {
    var at = painting ? favoriteKeys.indexOf(painting.key) : -1
    gridIndex = Math.max(0, at)
    showingGrid = true
  }

  function moveGrid(dx, dy) {
    var count = favoriteKeys.length
    if (!count) return
    gridIndex = Math.max(0, Math.min(count - 1, gridIndex + dx + dy * 3))
  }

  function openFromGrid(i) {
    var index = catalog.byKey[favoriteKeys[i]]
    if (index === undefined) return
    show(index)
    showingGrid = false
  }

  function openLink() {
    var url = painting ? Model.safeLink(painting.link) : ""
    if (url !== "") Qt.openUrlExternally(url)
  }

  function showFullView() {
    if (!painting) return
    fullView = true
    root.controller.hide()
  }

  function closeFullView() {
    fullView = false
    root.controller.show()
  }

  function open() {
    if (seen && !showingGrid) next()
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
    source: root.upcomingPainting && !root.offline ? root.imageSource(root.upcomingPainting) : ""
    sourceSize.width: 1200
    sourceSize.height: 1200
  }

  FullView {
    shown: root.fullView
    painting: root.painting
    byline: root.painting ? Model.byline(root.painting, root.artist) : ""
    source: root.imageSource(root.painting)
    favorite: root.currentIsFavorite
    fontFamily: root.fontFamily
    onCloseRequested: root.closeFullView()
    onNextRequested: root.next()
    onBackRequested: root.back()
    onFavoriteRequested: root.toggleFavorite()
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
      implicitHeight: root.showingGrid ? gridColumn.implicitHeight : column.implicitHeight
      onMoveRequested: function(dx, dy) {
        if (root.showingGrid) root.moveGrid(dx, dy)
        else if (dx > 0) root.next()
        else if (dx < 0) root.back()
      }
      onActivateRequested: {
        if (root.showingGrid) root.openFromGrid(root.gridIndex)
        else if (root.offline) root.retry()
        else root.next()
      }
      onCloseRequested: root.showingGrid ? root.showingGrid = false : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "f") root.showingGrid ? root.toggleFavorite(root.catalog.paintings[root.catalog.byKey[root.favoriteKeys[root.gridIndex]]]) : root.toggleFavorite()
        else if (t === "F") root.setFavoritesOnly(!root.favoritesOnly)
        else if (t === "g" || t === "G") root.showingGrid ? root.showingGrid = false : root.openGrid()
        else if (t === "z" || t === "Z") { if (root.showingGrid) root.openFromGrid(root.gridIndex); root.showFullView() }
        else if (t === "o" || t === "O") root.openLink()
      }

      // ================= The card =================
      Flickable {
        id: scroller
        anchors.fill: parent
        visible: !root.showingGrid
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: scroller.width
          spacing: Style.space(10)

          Text {
            visible: root.favoritesOnly
            textFormat: Text.PlainText
            text: strings.tn("salon.favoritesOnly", root.favoriteKeys.length).arg(root.favoriteKeys.length).toUpperCase()
            color: Commons.Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }

          // ---- The picture. Double-click for the full view.
          Item {
            id: frame
            readonly property size fitted: root.frameSize(root.painting)
            width: parent.width
            height: root.painting && !root.nothingToShow ? fitted.height : Style.space(120)

            Image {
              id: picture
              anchors.centerIn: parent
              width: frame.fitted.width
              height: frame.fitted.height
              visible: !root.nothingToShow
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              cache: true
              smooth: true
              mipmap: true
              source: root.painting && !root.offline ? root.imageSource(root.painting) : ""
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

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onDoubleClicked: root.showFullView()
              }
            }

            Text {
              anchors.centerIn: parent
              visible: root.nothingToShow || picture.status !== Image.Ready
              width: parent.width - Style.space(40)
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: root.nothingToShow ? strings.t("salon.noFavorites")
                : root.offline ? strings.t("salon.offline")
                : root.catalog.paintings.length === 0 ? strings.t("salon.empty")
                : strings.t("salon.loading")
              color: root.dimmed
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          // ---- Title and date, with the heart.
          Item {
            width: parent.width
            height: titleColumn.implicitHeight
            visible: root.painting !== null && !root.nothingToShow

            Column {
              id: titleColumn
              anchors.left: parent.left
              anchors.right: heart.left
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(3)

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

            Text {
              id: heart
              anchors.right: parent.right
              anchors.top: parent.top
              textFormat: Text.PlainText
              text: root.currentIsFavorite ? "󰋑" : "󰋕"
              color: root.currentIsFavorite || heartMouse.containsMouse ? Commons.Color.accent : root.dimmed
              font.family: root.fontFamily
              font.pixelSize: Style.font.display

              MouseArea {
                id: heartMouse
                anchors.fill: parent
                anchors.margins: -Style.space(6)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleFavorite()
              }

              PanelToolTip {
                visible: heartMouse.containsMouse
                text: root.currentIsFavorite ? strings.t("salon.unfavorite") : strings.t("salon.favorite")
                fontFamily: root.fontFamily
              }
            }
          }

          // ---- A few lines about it.
          Column {
            width: parent.width
            spacing: Style.space(3)
            visible: root.noteInfo.text !== "" && !root.nothingToShow

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

          // ---- Keys, and a word when Context Engine is out of reach.
          Text {
            width: parent.width
            visible: root.favorites.syncError !== "" && root.favoriteKeys.length > 0
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: strings.t("salon.syncError").arg(root.favorites.syncError)
            color: Commons.Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: strings.t("salon.keys")
            color: root.dimmed
            opacity: 0.8
            lineHeight: 1.3
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      // ================= The favourites grid =================
      Column {
        id: gridColumn
        anchors.left: parent.left
        anchors.right: parent.right
        visible: root.showingGrid
        spacing: Style.space(10)

        readonly property int cell: Math.floor(width / 3)
        readonly property int rows: Math.ceil(root.favoriteKeys.length / 3)

        Text {
          textFormat: Text.PlainText
          text: strings.tn("salon.favoritesCount", root.favoriteKeys.length).arg(root.favoriteKeys.length).toUpperCase()
          color: Commons.Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
        }

        Text {
          visible: root.favoriteKeys.length === 0
          width: parent.width
          height: Style.space(120)
          verticalAlignment: Text.AlignVCenter
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: strings.t("salon.noFavorites")
          color: root.dimmed
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        GridView {
          id: grid
          visible: root.favoriteKeys.length > 0
          width: parent.width
          height: Math.min(gridColumn.rows, 3.4) * gridColumn.cell
          cellWidth: gridColumn.cell
          cellHeight: gridColumn.cell
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: root.showingGrid ? root.favoriteKeys : []
          currentIndex: root.gridIndex
          onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)

          delegate: Item {
            id: tile
            required property var modelData
            required property int index
            readonly property var p: root.catalog.paintings[root.catalog.byKey[modelData]]
            readonly property bool current: index === root.gridIndex
            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
              anchors.fill: parent
              anchors.margins: Style.space(4)
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
              border.width: tile.current ? Math.max(2, Style.space(2)) : 0
              border.color: Commons.Color.accent
              radius: Math.min(4, Style.cornerRadius)

              Image {
                anchors.fill: parent
                anchors.margins: tile.current ? Math.max(2, Style.space(2)) : 0
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
                source: root.imageSource(tile.p)
                sourceSize.width: 400
                sourceSize.height: 400
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.gridIndex = tile.index
              onClicked: root.openFromGrid(tile.index)
            }
          }
        }

        // The selected painting's name, so the grid reads without hovering.
        Text {
          visible: root.favoriteKeys.length > 0
          width: parent.width
          elide: Text.ElideRight
          textFormat: Text.PlainText
          readonly property var p: root.catalog.paintings[root.catalog.byKey[root.favoriteKeys[root.gridIndex]]]
          text: p ? p.title + " — " + Model.byline(p, root.catalog.artists[p.artist]) : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: strings.t("salon.gridKeys")
          color: root.dimmed
          opacity: 0.8
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
