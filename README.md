# Salon

An Omarchy bar widget that shows a random painting by Goya, Ensor, Bacon,
de Kooning, Guston, Dubuffet, Appel, Jorn or Condo, with its title, date,
medium, collection and a few lines about it.

| Input | Does |
|---|---|
| Click the palette | Open the card (a new painting each time) |
| Right-click | Change the painting without opening |
| Middle-click | Open the painting's page |
| Space / → | Next painting |
| ← | Back |
| F / the heart | Save to favourites, or remove |
| Shift+F | Favourites only, on and off |
| G | Grid of favourites (arrows, Enter opens, F removes) |
| Z / double-click | Full view (Space and arrows keep going, Esc returns) |
| O | Open the painting's page |
| Esc | Close |

From a keybinding or script: `omarchy-shell mert.salon next | favorite |
fullView | closeFullView | favorites`.

## Favourites

`bin/salon` keeps them in `~/.local/state/salon/favorites.json`, with a copy
of each image in `images/` beside it so a favourite outlives its web page.
Each favourite is also a note in Context Engine (through the
`relote.context-engine` plugin's `ce`), slug `salon-favourite-<key>`, tagged
`salon-favourite`; removing one archives the note. Changes made offline are
sent on the next sync, and every 30 minutes the widget takes in favourites
saved on your other machines.

Limit the artists in `~/.config/omarchy/shell.json`:
`{ "id": "mert.salon", "artists": ["bacon", "guston"] }`.

## How it works

`catalog.json` ships with the widget; only the images are loaded at runtime,
from WikiArt and Wikimedia. `bin/build-catalog` rebuilds it from WikiArt,
Wikipedia and Wikimedia Commons, checks every image link, and drops what does
not load. Tests: `node tests/model.test.js` (picking, validation) and
`python3 -I tests/salon_test.py` (favourites, against a fake `ce`).

Install: the repository lives at `~/.config/omarchy/plugins/mert.salon`
(the shell does not reload plugins reached through a symlink), then
`omarchy bar put mert.salon --section centerEnd --index 0`. After editing
QML, run `omarchy restart shell`: the shell reloads the plugin but keeps the
compiled QML it already has.

Paintings are shown from their public pages for personal viewing; the
artworks belong to their rights holders. Text from Wikipedia is CC BY-SA.
