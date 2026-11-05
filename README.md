# Salon

A painting in your Omarchy bar. Click the palette for a random work by the
artists you choose, with its title, date, medium, collection and a few lines
about it. Keep favourites, browse them in a grid, and see any painting full
screen.

## Install

```
omarchy plugin add https://github.com/merthurturk/salon --enable
```

## Choose your artists

Out of the box Salon shows masters whose work is out of copyright: Goya,
Bosch, Bruegel, Rembrandt, Turner and Van Gogh (980 paintings, built in).

To use your own artists, list them in the widget's settings, or in
`~/.config/omarchy/shell.json`:

```json
{ "id": "merthurturk.salon", "artists": "Francis Bacon, Philip Guston, Egon Schiele", "paintingsPerArtist": 150 }
```

Names are as WikiArt has them. Salon builds that collection on your computer
in the background (a few minutes the first time, longer for many artists) and
shows the built-in paintings meanwhile. Artists WikiArt lacks are looked up on
Wikipedia and Wikimedia Commons. `omarchy-shell merthurturk.salon rebuild`
fetches everything again.

| Setting | Default | |
|---|---|---|
| `artists` | empty | Comma-separated artist names; empty for the built-in masters |
| `paintingsPerArtist` | 150 | The most a built collection keeps of one artist |
| `contextEngine` | `Auto` | Sync favourites to Context Engine when its plugin is installed; `Off` keeps them local |

## Keys

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

From a keybinding or script: `omarchy-shell merthurturk.salon next |
favorite | fullView | closeFullView | favorites | rebuild`.

## Favourites

Kept in `~/.local/state/salon/favorites.json`, with a copy of each image so a
favourite outlives its web page, and shown even after you switch to a
collection that does not include it. With the
[Context Engine](https://contextengine.com) plugin installed, each favourite
is also a note (slug `salon-favourite-<key>`, tag `salon-favourite`), so your
other machines share them; removing one archives the note.

## Development

`bin/build-catalog` builds a catalog (`--artists`, `--out`,
`--max-per-artist`); with no options it rebuilds the built-in `catalog.json`.
`bin/salon` manages favourites. Tests: `node tests/model.test.js` and
`python3 -I tests/salon_test.py` (against a fake `ce`). After editing QML, run
`omarchy restart shell`: the shell reloads plugins but keeps compiled QML.

## Credits

Data from WikiArt (its unofficial app endpoints), Wikipedia and Wikimedia
Commons. Paintings are shown from their public pages for personal viewing and
belong to their rights holders; Salon does not host them. Text from Wikipedia
is CC BY-SA.
