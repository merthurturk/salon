// Run with: node tests/model.test.js
const fs = require("fs"), path = require("path"), assert = require("assert")
const src = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(/^\.pragma library/, "")
const mod = { exports: {} }
new Function("module", src)(mod)
const M = mod.exports

const fixture = JSON.stringify({
  artists: { goya: { name: "Francisco Goya", about: "Spanish painter." }, condo: { name: "George Condo", about: "American." },
             "Bad Id!": { name: "x" } },
  paintings: [
    { key: "goya-saturn-1823", artist: "goya", title: "Saturn", year: "1823", image: "https://uploads1.wikiart.org/a.jpg", width: 100, height: 200,
      wiki: { extract: "A painting.", url: "https://en.wikipedia.org/wiki/Saturn" } },
    { key: "goya-dog-1823", artist: "goya", title: "The Dog", year: "1823", image: "https://uploads2.wikiart.org/b.jpg", source: "https://evil.example/x" },
    { artist: "goya", title: "Bad host", image: "https://evil.example/c.jpg" },
    { artist: "nobody", title: "Orphan", image: "https://uploads1.wikiart.org/d.jpg" },
    { key: "condo-img-nd", artist: "condo", title: "<img src=x>", image: "https://upload.wikimedia.org/e.jpg", medium: "oil on canvas", size: "50 × 60 cm" },
  ],
})

const c = M.parseCatalog(fixture)
assert.deepStrictEqual(c.artistIds, ["goya", "condo"], "drops malformed artist ids")
assert.strictEqual(c.paintings.length, 3, "drops foreign image hosts and unknown artists")
assert.strictEqual(c.paintings[1].link, "", "drops links to unknown hosts")
assert.strictEqual(c.paintings[2].title, "<img src=x>", "keeps text as text; the QML shows it as plain text")
assert.deepStrictEqual(M.parseCatalog("not json").paintings, [])

// Artists are drawn evenly even though Goya has twice as many paintings.
let condo = 0
for (let i = 0; i < 4000; i++) if (c.paintings[M.pick(c, [], [])].artist === "condo") condo++
assert(condo > 1700 && condo < 2300, "even split between artists, got " + condo)

// Recently shown paintings are skipped while others remain.
for (let i = 0; i < 200; i++) assert.notStrictEqual(M.pick(c, ["goya"], [0]), 0)
// A filter limits the pool; a filter naming nobody falls back to everyone.
for (let i = 0; i < 100; i++) assert.strictEqual(c.paintings[M.pick(c, ["condo"], [])].artist, "condo")
assert.notStrictEqual(M.pick(c, ["picasso"], []), -1)
// Everything recently seen still yields something.
assert.notStrictEqual(M.pick(c, [], [0, 1, 2]), -1)

let recent = []
for (let i = 0; i < 100; i++) recent = M.remember(recent, i)
assert.strictEqual(recent.length, M.RECENT)
assert.deepStrictEqual(M.remember([1, 2, 3], 1), [2, 3, 1])

assert.strictEqual(M.byline(c.paintings[0], c.artists.goya), "Francisco Goya, 1823")
assert.strictEqual(M.byline(c.paintings[2], c.artists.condo), "George Condo")
assert.strictEqual(M.facts(c.paintings[2]), "oil on canvas · 50 × 60 cm")
assert.deepStrictEqual(M.note(c.paintings[0], c.artists.goya), { text: "A painting.", aboutArtist: false })
assert.deepStrictEqual(M.note(c.paintings[1], c.artists.goya), { text: "Spanish painter.", aboutArtist: true })

// Favourites: newest first, removals left out, only cached paths inside
// the images folder, and favourites from other collections appended.
const favs = M.parseFavorites(JSON.stringify({ syncError: "offline", items: {
  "goya-saturn-1823": { added: "2026-11-01", cached: "images/goya-saturn-1823.jpg" },
  "goya-dog-1823": { added: "2026-11-03", cached: "../../etc/passwd" },
  "condo-img-nd": { added: "2026-11-02", pending: "remove" },
  "bosch-garden-1500": { added: "2026-11-04", title: "Garden", artist: "hieronymus-bosch", artistName: "Hieronymus Bosch",
                         image: "https://upload.wikimedia.org/g.jpg" },
  "bad-host-1900": { added: "2026-11-05", title: "Nope", artist: "x", image: "https://evil.example/x.jpg" },
} }))
const both = M.combine(c, favs)
assert.strictEqual(JSON.stringify(both.keys), JSON.stringify(["bosch-garden-1500", "goya-dog-1823", "goya-saturn-1823"]))
assert.strictEqual(both.cached["goya-saturn-1823"], "images/goya-saturn-1823.jpg")
assert.strictEqual(both.cached["goya-dog-1823"], undefined)
assert.strictEqual(both.syncError, "offline")
assert.strictEqual(both.catalog.paintings.length, c.paintings.length + 1, "the Bosch is appended, the bad host is not")
assert.strictEqual(both.catalog.byKey["goya-dog-1823"], c.byKey["goya-dog-1823"], "catalog positions stay put")
assert.strictEqual(both.catalog.artists["hieronymus-bosch"].name, "Hieronymus Bosch")
for (let i = 0; i < 300; i++) assert.notStrictEqual(both.catalog.paintings[M.pick(both.catalog, [], [])].artist, "hieronymus-bosch",
  "random picks stay within the collection")
assert.strictEqual(M.parseFavorites("garbage").rows.length, 0)
for (let i = 0; i < 50; i++) assert.notStrictEqual(M.pickFavorite(both.catalog, both.keys, [0]), 0, "skips the one just shown")
assert.strictEqual(M.pickFavorite(c, [], []), -1)

// Artist lists as people type them.
assert.strictEqual(JSON.stringify(M.artistSlugs("Francis Bacon, philip-guston ,, Égon Schiele, francis-bacon")),
  JSON.stringify(["francis-bacon", "philip-guston", "egon-schiele"]))
assert.strictEqual(JSON.stringify(M.artistSlugs(["Goya", "Bosch"])), JSON.stringify(["goya", "bosch"]))
assert.strictEqual(M.artistSlugs("").length, 0)

// The shipped catalog parses and every painting survives validation.
const shipped = fs.readFileSync(path.join(__dirname, "..", "catalog.json"), "utf8")
const real = M.parseCatalog(shipped)
assert.strictEqual(real.paintings.length, JSON.parse(shipped).paintings.length, "every shipped painting is valid")
assert(Object.keys(M.byArtist(real, [])).length >= 5, "the built-in artists all have paintings")
console.log("ok", real.paintings.length, "paintings")
