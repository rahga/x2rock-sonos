# x2rock.sonos — Omarchy bar widget

Sonos rooms in the bar: now-playing, transport, per-room volume, favorites,
browsing and searching a music service, grouping and party mode. Driven entirely by the `x2rock daemon`'s MPRIS players.

Needs `x2rock` on `PATH` and `x2rock daemon` running. With no daemon there are
no players, and the widget hides itself.

## Configuring

Everything below is set on this widget's entry in the `bar.layout` subtree of
`~/.config/omarchy/shell.json`. **Edit that, not the QML in this directory** —
the plugin is installed by copying over the previous copy, so changes to
`BarWidget.qml` are lost on the next install. `shell.json` survives.

```jsonc
{
  "id": "x2rock.sonos",
  "art": true,
  "artSize": 38,
  "showState": true,
  "showMembers": true,
  "popupWidth": 340,
  "panelWidth": 380,
  "highlight": 0.12,
  "command": "x2rock",
  "searchService": "TuneIn",
  "browseServices": ["iHeartRadio", "Bandcamp"],
  "glyphs": {
    "music": "󰝚"
  },
  "strings": {
    "playing": "spiller",
    "leave": "forlat"
  }
}
```

| Key | Default | Effect |
|---|---|---|
| `art` | `true` | Cover art beside each room and each favorite. Never appears on the bar pill itself, at any setting. |
| `artSize` | `38` | Cover tile size, in the same spacing units as the rest of the widget, so it follows display scaling. Picker tiles sit 4 smaller. Minimum 12. |
| `showState` | `true` | The `playing` / `paused` word beside each room name. |
| `showMembers` | `true` | The `Kitchen + Guest TV` line under a grouped room. Never shown for an ungrouped one. |
| `popupWidth` | `340` | Width of the room list, in the widget's own spacing units. Clamped to what the screen allows. |
| `panelWidth` | `380` | Width of the music, queue and grouping panels. Same units, same clamp. |
| `highlight` | the shell's own | How strongly a row lights up under the cursor, as an opacity over the theme's cursor colour - which follows the accent, like every first-party row. Unset it and the widget lights up exactly as the rest of the shell does; set a number to diverge, or `0` to turn cursor highlighting off. The playing track in a queue keeps its own mark either way. |
| `command` | `"x2rock"` | The x2rock binary. A bare name is looked up on the shell's `PATH`, which is not the same `PATH` an interactive terminal has — give an absolute path if the widget can read rooms but its buttons do nothing. |
| `strings` | see below | Per-word overrides, for a household that is not English or one that just wants shorter labels. Each key falls back on its own. |
| `glyphs` | see below | Per-glyph overrides. Each key falls back on its own, so overriding one does not mean restating the rest. |
| `searchService` | `"TuneIn"` | Which service the picker's **Search** row queries. `""` turns searching off entirely. Only services x2rock can reach are valid — `x2rock search` lists them, and `x2rock link` adds to that list. |
| `searchCount` | `20` | Hits fetched per search. Minimum 1. |
| `searchCategory` | `""` | Which of the service's categories the search row queries, passed to the CLI as `-c`. Empty means the CLI's default: the service's `all` when it has one, else its first category. Worth setting for a library-shaped service — Plex has no `all` and leads with `artists`, so a picker pointed at Plex wants `"tracks"` here. `x2rock search -s <service>` with no term lists what a service offers. |
| `browseServices` | discovered | Which services the picker offers to **walk**, as an array of names. A service's own containers — a personal library, a "For You", a genre tree — are the half of a service no search term can name. Unset, the list is discovered: a row for `searchService`, then one per account this machine has linked (`x2rock accounts` shows them), because `x2rock link` already named the services that matter. Set it to choose by hand — an anonymous service beyond `searchService` only gets a row this way — and `[]` turns browsing off. |
| `browseCount` | `100` | Rows fetched per container. Minimum 1. |

### Glyphs

Defaults are Material Design icons from the bar's own Nerd Font, except `party`,
which is an ordinary Unicode character. Override any subset:

| Key | Default | Where |
|---|---|---|
| `speaker` | `󰓃` | The pill, and the placeholder when a cover is missing or still loading |
| `play` | `󰐊` | Room row, when paused |
| `pause` | `󰏤` | Room row, when playing |
| `previous` | `󰒮` | Room row |
| `next` | `󰒭` | Room row |
| `repeat` | `󰑖` | Room row, off or repeating the queue |
| `repeatOne` | `󰑘` | Room row, repeating one track |
| `shuffle` | `󰒝` | Room row |
| `music` | `󰝚` | Opens that room's music picker — favorites, kept items, browsing and search |
| `group` | `󰌷` | Opens that room's grouping panel |
| `ungroup` | `󰌸` | Sends one room back out on its own |
| `tv` | `󰠹` | Switches a soundbar to its TV input, and stands in for cover art while it is on TV |
| `queue` | `󰲹` | Opens that room's queue |
| `radio` | `󰐻` | Before the name, when the room is playing a live stream. Hovering it names the station |
| `stop` | `󰓛` | Stands in for `pause` on a source that refuses to be paused, such as a live stream |
| `podcast` | `󰍬` | Before the name of a podcast show in the picker. A microphone, not the podcast icon proper, which reads too much like `radio` beside it |
| `audiobook` | `󰗚` | Before the name of an audiobook. An open book rather than headphones: the marks say what a row is, not what plays it |
| `add` | `+` | On the right of a picker row, adds it to the queue instead of playing it. Only on rows the CLI reports as queueable |
| `remove` | `󰅖` | Drop a track from the queue |
| `moveUp` | `󰅃` | Move a queue track earlier |
| `moveDown` | `󰅀` | Move a queue track later |
| `party` | `◉` | Party mode, hosted by that room. Plain Unicode, not a Nerd Font icon, so it draws in almost any font |

`party` is the one plain-Unicode default, and draws in almost any font. If your
bar's font is **not** a patched Nerd Font every other glyph here comes out as a
box, and plain characters are the fix — `"music": "♪"` (U+266A) is the note for
that case, and `"radio": "📻"` (U+1F4FB) the radio set.

Both come at a cost on a bar whose font *is* patched, which is why neither is
the default. JetBrainsMono Nerd Font has neither codepoint, so each one is a
per-character fallback to some other font at some other weight. 📻 is the
louder of the two: `RADIO` is `Emoji_Presentation=Yes`, so fontconfig resolves
it to Noto Color Emoji and it arrives in full colour beside seventeen
monochrome line icons — and, being colour, it ignores the row's foreground and
stops dimming with its neighbours. Appending U+FE0E asks for text presentation
instead, which helps only if a font on the box draws it that way.

`music` was called `favorites` before the picker grew browsing and search, and
that name still works: a `shell.json` written against it needs no editing.

Anything the bar's font can draw works, including plain text — `"music":
"fav"` is valid. If a glyph comes out as a box, the font lacks that codepoint;
`fc-list ":charset=<hex>"` lists the fonts that have it.

### Words

| Key | Default |
|---|---|
| `playing` / `paused` | `playing` / `paused` — beside each room name |
| `loading` | `Loading…` |
| `filterHint` | `Type to filter` — the picker's filter placeholder. Filters favorites and kept items, and whatever container is open |
| `noMatch` | `No match` |
| `searchFor` | `Search %1` — the row that runs a query. `%1` is the service |
| `searching` / `searchError` | `Searching…` / `Could not reach %1` |
| `addToQueue` | `Add to queue` — the `+` button's tooltip |
| `noResults` | `Nothing found` |
| `browseIn` | `Browse %1` — the row that opens a service's own containers. `%1` is the service |
| `up` | `← %1` — the row back out of a container. `%1` is where it goes: the parent's name, or the service's own at the top of the tree |
| `browseLoading` / `browseError` | `Opening…` / `Could not open that` |
| `browseEmpty` | `Nothing here` — a container the service says is empty |
| `noFavorites` / `favoritesError` | `No favorites saved` / `Could not read favorites` |
| `nothingQueued` / `queueError` | `Nothing queued` / `Could not read the queue` |
| `playingTogether` | `Playing together` — heading over a group's members |
| `playTogetherWith` / `addAnother` | `Play together with` / `Add another` — heading over the rooms that can join |
| `everyRoomGrouped` | `Every room is in this group.` |
| `leave` / `join` | `leave` / `join` — shown on hover beside their glyphs |
| `of` | `of`, as in "12 of 70" |
| `kindStream` `kindAlbum` `kindTrack` `kindProgram` `kindPlaylist` | `stream` `album` `track` `program` `playlist` — the word under a favorite's name. Sonos supplies these in English of its own; without these keys they would be the only English left in a translated widget. |
| `tooltipTv` / `tooltipTvOn` | `TV Input` / `TV Input (current source)` — the TV switch's tooltip, before and while that room is on its TV input |
| `tooltipParty` / `tooltipPartyOn` | `Party` / `Party (on)` — the party switch, off and on |
| `tooltipGroup` / `tooltipGroupOf` | `Group` / `Group (%1 rooms)` — the second is used when the room is already in a group; `%1` is that group's size and may sit anywhere in the phrase |

Blanking a tooltip key — `"tooltipParty": ""` — turns that tooltip off rather
than showing an empty bubble.

This is not Qt translation. Qt's own machinery needs a translator installed at startup, which
Quickshell does not do and Omarchy has no catalogues for — its shell contains no `qsTr` at all, so
a properly translated widget would sit in a bar whose every other widget is still English. These
keys let a household do its own words instead. Most of what you actually read here — room names,
track titles, artists, playlists — comes from your Sonos household already, in whatever language
you keep it in.

Everything else the widget shows already comes from your household — room names, track titles,
artists, playlists — and from music services, whose names stay as they spell them. So with
`strings` set there is no English left in the widget.

The CLI is still English throughout. Nothing the widget displays is taken from its output text, so
translating one does not require the other; the CLI could be translated later without touching any
of this.

## Opening it without the mouse

The widget answers the shell's own summon calls, so the room list can be opened
from a hotkey instead of a click on the pill:

```bash
omarchy-shell shell summon x2rock.sonos   # open
omarchy-shell shell hide x2rock.sonos     # close
omarchy-shell shell toggle x2rock.sonos   # either way
```

Bound in `~/.config/hypr/bindings.lua`, that is:

```lua
o.bind("SUPER + SHIFT + S", "Sonos", "omarchy-shell shell toggle x2rock.sonos")
```

Once the room list is open it is driven from the keyboard. `↑` and `↓` pick a
room - the selected one is the room whose name is bold, the same room the pill
shows and the scroll gesture acts on - and every control on that room has a key
of its own, so the fourth room's queue is `↓↓↓ q` rather than a cursor walked
along a row of ten:

| Key | Does |
|---|---|
| `↑` / `↓` | Select the room above or below. Stops at the ends rather than wrapping. |
| `←` / `→` | That room's volume, down or up, in the same 2% steps as the scroll gesture. |
| `Space` | Play or pause. |
| `n` / `p` | Next or previous track, where the source allows it. |
| `r` | Repeat: off → all → one → off, skipping what the source cannot do. |
| `s` | Shuffle. |
| `f` | Music picker for that room: favorites, kept items, browsing and search. |
| `q` | Its queue. |
| `g` | Its grouping panel. |
| `t` | Switch it to TV input, on a soundbar that has one. |
| `y` | Party mode, hosted by that room. |
| `Esc` | Close the room list. |

A key does nothing where the matching control would not be shown: no `g`, `y`
in a one-speaker household, no `t` on a speaker without a TV input, and no `n`
on a radio stream.

The three panels those keys open are driven the same way - `↑` and `↓` move a
cursor, `Enter` does whatever clicking the row under it does, `Esc` closes -
and the cursor is the highlighted row whether the pointer or the keyboard put
it there, so there is one of them rather than one per input device:

| Panel | `Enter` on the cursor | Also |
|---|---|---|
| Music | Plays the row in the room, or opens it when it is a container | Type to filter. `Backspace` or `←` on an empty filter goes back up a container |
| Queue | Jumps to that track | The cursor starts on the playing track |
| Grouping | Leaves the group, on a member; joins it, on a room outside | `←` / `→` set the selected member's own volume, not the group's |

The room that hosts a group is the group, so it has no leave target and `Enter`
does nothing on its row. Closing a panel does not bring the room list back,
the same as when it was opened by clicking.

## What is not configurable, and why

Colours. Everything is derived from the bar's own foreground, so the widget
follows whatever theme the bar is set to without being told about it. Fixing a
colour here would mean it stops tracking the theme, which is the opposite of
what it is for.

Cover art on the bar pill. The pill is always on screen, and a full-colour
thumbnail in a themed bar is an intrusion rather than a feature. Art appears in
the popup and the picker, which are opened deliberately.

## Files

- `BarWidget.qml` — the widget. Installed by copy; edits do not survive updates.
- `CoverArt.qml` — cover tile with the themed placeholder.
- `manifest.json` — plugin metadata for Omarchy's loader.
