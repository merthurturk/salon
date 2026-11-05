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
    { artist: "goya", title: "Saturn", year: "1823", image: "https://uploads1.wikiart.org/a.jpg", width: 100, height: 200,
      wiki: { extract: "A painting.", url: "https://en.wikipedia.org/wiki/Saturn" } },
    { artist: "goya", title: "The Dog", year: "1823", image: "https://uploads2.wikiart.org/b.jpg", source: "https://evil.example/x" },
    { artist: "goya", title: "Bad host", image: "https://evil.example/c.jpg" },
    { artist: "nobody", title: "Orphan", image: "https://uploads1.wikiart.org/d.jpg" },
    { artist: "condo", title: "<img src=x>", image: "https://upload.wikimedia.org/e.jpg", medium: "oil on canvas", size: "50 × 60 cm" },
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

// The shipped catalog parses and every painting survives validation.
const shipped = fs.readFileSync(path.join(__dirname, "..", "catalog.json"), "utf8")
const real = M.parseCatalog(shipped)
assert.strictEqual(real.paintings.length, JSON.parse(shipped).paintings.length, "every shipped painting is valid")
assert.strictEqual(Object.keys(M.byArtist(real, [])).length, 9, "all nine artists have paintings")
console.log("ok", real.paintings.length, "paintings")
