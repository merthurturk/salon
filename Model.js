.pragma library

// Pure helpers for Salon: reading the catalog, picking the next painting,
// and the lines of text under the picture. No QML in here so it can be tested
// from Node (tests/model.test.js).

// Images only ever come from these hosts; anything else in the catalog is
// dropped rather than handed to an Image element.
var IMAGE_HOSTS = /^https:\/\/(uploads\d?\.wikiart\.org|upload\.wikimedia\.org|thumb\.wikimedia\.org)\//
// Links the card opens in the browser.
var LINK_HOSTS = /^https:\/\/(www\.wikiart\.org|en\.wikipedia\.org|commons\.wikimedia\.org)\//

var MAX_TEXT = 900
var MAX_SHORT = 200
var MAX_PAINTINGS = 5000
var RECENT = 60

function str(value, limit) {
  if (value === undefined || value === null) return ""
  var s = String(value)
  return s.length > limit ? s.slice(0, limit) : s
}

function safeLink(url) {
  var s = str(url, 600)
  return LINK_HOSTS.test(s) ? s : ""
}

// The catalog ships with the plugin, but it is still read defensively: a
// hand edit or a bad rebuild must not put markup, odd URLs, or megabytes of
// text into the shell.
function parseCatalog(text) {
  var empty = { artists: {}, artistIds: [], paintings: [] }
  var raw
  try { raw = JSON.parse(text) } catch (e) { return empty }
  if (!raw || typeof raw !== "object") return empty

  var artists = {}
  var artistIds = []
  var rawArtists = raw.artists || {}
  for (var id in rawArtists) {
    if (!/^[a-z0-9-]{1,40}$/.test(id)) continue
    var a = rawArtists[id] || {}
    artists[id] = { id: id, name: str(a.name, MAX_SHORT), about: str(a.about, MAX_TEXT), url: safeLink(a.url) }
    artistIds.push(id)
  }

  var paintings = []
  var byKey = {}
  var list = Array.isArray(raw.paintings) ? raw.paintings.slice(0, MAX_PAINTINGS) : []
  for (var i = 0; i < list.length; i++) {
    var p = list[i] || {}
    var image = str(p.image, 600)
    if (!artists[p.artist] || !IMAGE_HOSTS.test(image)) continue
    var wiki = p.wiki && typeof p.wiki === "object" ? p.wiki : null
    var key = str(p.key, 130)
    if (!/^[a-z0-9][a-z0-9-]*$/.test(key) || byKey[key] !== undefined) continue
    byKey[key] = paintings.length
    paintings.push({
      key: key,
      artist: p.artist,
      title: str(p.title, MAX_SHORT) || "Untitled",
      year: str(p.year, 20),
      image: image,
      width: Math.max(0, Number(p.width) || 0),
      height: Math.max(0, Number(p.height) || 0),
      style: str(p.style, MAX_SHORT),
      genre: str(p.genre, MAX_SHORT),
      medium: str(p.medium, MAX_SHORT),
      size: str(p.size, 60),
      collection: str(p.collection, MAX_SHORT),
      series: str(p.series, MAX_SHORT),
      note: str(wiki ? wiki.extract : p.description, MAX_TEXT),
      link: safeLink(wiki && wiki.url ? wiki.url : p.source)
    })
  }
  return { artists: artists, artistIds: artistIds, paintings: paintings, byKey: byKey }
}

// The favourites file bin/salon writes. Only what the widget needs: which
// keys are favourites (newest first), where a kept copy of the image is, and
// whether Context Engine could be reached. Keys the catalog does not know are
// left out, and so are favourites being removed.
function parseFavorites(text, catalog) {
  var result = { keys: [], cached: {}, syncError: "" }
  var raw
  try { raw = JSON.parse(text) } catch (e) { return result }
  if (!raw || typeof raw !== "object" || !raw.items || typeof raw.items !== "object") return result
  var rows = []
  for (var key in raw.items) {
    var item = raw.items[key] || {}
    if (catalog.byKey[key] === undefined || item.pending === "remove") continue
    rows.push({ key: key, added: str(item.added, 40) })
    var cached = str(item.cached, 200)
    if (/^images\/[a-z0-9-]+\.(jpg|png|webp|gif)$/.test(cached)) result.cached[key] = cached
  }
  rows.sort(function(a, b) { return a.added < b.added ? 1 : a.added > b.added ? -1 : 0 })
  result.keys = rows.map(function(r) { return r.key })
  result.syncError = str(raw.syncError, 200)
  return result
}

// A random favourite, skipping the ones shown lately while others remain.
function pickFavorite(catalog, keys, recent, random) {
  random = random || Math.random
  var indexes = keys.map(function(k) { return catalog.byKey[k] }).filter(function(i) { return i !== undefined })
  if (!indexes.length) return -1
  var seen = {}
  for (var r = 0; r < (recent || []).length; r++) seen[recent[r]] = true
  var fresh = indexes.filter(function(i) { return !seen[i] })
  var pool = fresh.length ? fresh : indexes
  return pool[Math.floor(random() * pool.length)]
}

// Indexes of the paintings by each artist, limited to the artists the user
// kept in shell.json (all of them when the list is empty or names nobody).
function byArtist(catalog, only) {
  var wanted = {}
  var any = false
  if (Array.isArray(only)) {
    for (var i = 0; i < only.length; i++) {
      if (catalog.artists[only[i]]) { wanted[only[i]] = true; any = true }
    }
  }
  var groups = {}
  for (var j = 0; j < catalog.paintings.length; j++) {
    var artist = catalog.paintings[j].artist
    if (any && !wanted[artist]) continue
    if (!groups[artist]) groups[artist] = []
    groups[artist].push(j)
  }
  return groups
}

// The artist is drawn first and the painting second, so Goya's three hundred
// works do not drown out Condo's four. Recently shown paintings are skipped
// while there is anything else left to show.
function pick(catalog, only, recent, random) {
  random = random || Math.random
  recent = recent || []
  var groups = byArtist(catalog, only)
  var artists = Object.keys(groups)
  if (artists.length === 0) return -1

  var seen = {}
  for (var r = 0; r < recent.length; r++) seen[recent[r]] = true

  var order = artists.slice()
  for (var k = order.length - 1; k > 0; k--) {
    var swap = Math.floor(random() * (k + 1))
    var t = order[k]; order[k] = order[swap]; order[swap] = t
  }
  // Prefer an artist other than the last one shown, then any fresh painting.
  var last = recent.length ? catalog.paintings[recent[recent.length - 1]] : null
  if (last && order.length > 1 && order[0] === last.artist) order.push(order.shift())

  for (var a = 0; a < order.length; a++) {
    var fresh = groups[order[a]].filter(function(index) { return !seen[index] })
    if (fresh.length) return fresh[Math.floor(random() * fresh.length)]
  }
  var all = groups[order[0]]
  return all[Math.floor(random() * all.length)]
}

function remember(recent, index) {
  var next = recent.filter(function(i) { return i !== index })
  next.push(index)
  return next.length > RECENT ? next.slice(next.length - RECENT) : next
}

function byline(painting, artist) {
  var name = artist ? artist.name : ""
  return painting.year ? name + ", " + painting.year : name
}

function facts(painting) {
  var parts = []
  if (painting.medium) parts.push(painting.medium)
  if (painting.size) parts.push(painting.size)
  if (painting.style) parts.push(painting.style)
  return parts.join(" · ")
}

// What to say about the painting: its own article or description when there
// is one, otherwise a word about the artist.
function note(painting, artist) {
  if (painting.note) return { text: painting.note, aboutArtist: false }
  return { text: artist ? artist.about : "", aboutArtist: true }
}

// Height the picture gets for a given width, so the card is the right size
// before the image arrives instead of jumping when it does.
function frameHeight(painting, width, maxHeight) {
  if (!painting || !painting.width || !painting.height) return maxHeight
  return Math.min(maxHeight, Math.round(width * painting.height / painting.width))
}

if (typeof module !== "undefined") {
  module.exports = { parseCatalog: parseCatalog, parseFavorites: parseFavorites, pickFavorite: pickFavorite, byArtist: byArtist, pick: pick, remember: remember,
    byline: byline, facts: facts, note: note, frameHeight: frameHeight, safeLink: safeLink, RECENT: RECENT }
}
