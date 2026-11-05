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
| O | Open the painting's page |
| Esc | Close |

Limit the artists in `~/.config/omarchy/shell.json`:
`{ "id": "mert.salon", "artists": ["bacon", "guston"] }`.

## How it works

`catalog.json` ships with the widget; only the images are loaded at runtime,
from WikiArt and Wikimedia. `bin/build-catalog` rebuilds it from WikiArt,
Wikipedia and Wikimedia Commons, checks every image link, and drops what does
not load. `node tests/model.test.js` tests the picking and validation.

Install: `ln -sfn "$PWD" ~/.config/omarchy/plugins/mert.salon`, then
`omarchy bar put mert.salon --section centerEnd --index 0`.

Paintings are shown from their public pages for personal viewing; the
artworks belong to their rights holders. Text from Wikipedia is CC BY-SA.
