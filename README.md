# x2rock for Sonos — Omarchy bar widget

Sonos rooms in the bar: now-playing, transport, per-room volume, favorites,
browsing and searching a music service, grouping, party mode, and rating a
track up or down where the service offers it. Driven entirely by the `x2rock daemon`'s MPRIS players.

Needs `x2rock` on `PATH` and `x2rock daemon` running. When no Sonos players are detected, the widget hides itself.

![The popup: every room with per-room transport, volume and TV badges](preview.png)

## Installation

### Prerequisites

This widget communicates over local MPRIS D-Bus and requires the `x2rock` daemon running in the background. Refer to the [x2rock repository](https://github.com/rahga/x2rock) for daemon setup and service configuration.

### Add the Widget

Install and enable the widget in your Omarchy bar:

```bash
omarchy plugin add https://github.com/rahga/x2rock-sonos --enable
```

## Removal

To disable the widget from the bar without removing files:

```bash
omarchy plugin disable x2rock.sonos
```

To remove the plugin completely:

```bash
omarchy plugin remove x2rock.sonos
```

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
| `searchService` | `"TuneIn"` | Which service the picker's **Search** row queries. `""` turns searching off entirely. Only services x2rock can reach are valid — `x2rock search` lists them, and `x2rock link` adds to that list. Two values mean *more than one*: **`"all"`** asks every service that can answer, at once, and merges the hits; **`"linked"`** asks only those with an account. Each merged hit carries its own service, so a row plays from wherever it came from. Prefer `"linked"` if you have accounts worth searching — that tier has real albums, metadata the service vouches for, and content the player will queue rather than stream, where the anonymous tier is radio stations and blog aggregators. |
| `searchCount` | `20`, or `5` merged | Hits fetched **per service per category**, not in total. Minimum 1. Twenty is right for one service and far too many across thirty-five, so the default drops when `searchService` is `"all"` or `"linked"`. |
| `searchPerService` | `3` | Rows shown beneath one service's heading in a merged search, after its categories are interleaved. Three is what Sonos's own mobile app shows. The heading itself is the way to the rest — press it, or its **More ›**, for that service's whole answer grouped by category. Minimum 1. |
| `searchPerCategory` | `4` | Rows shown under one category heading inside a service's results, before that heading offers **More ›** to reveal the rest of it. Four, because six categories at full depth is a list nobody scans. Minimum 1. |
| `searchCategoryCount` | `20` | Rows a category shows once **More ›** has been pressed. The drill-in fetches one *more* than this and never displays it — that extra row is how the widget knows whether **Show all ›** has anything to offer, which nothing else can tell it: the JSON envelope's `total` is summed across every category, so it cannot speak for one. Minimum 1. |
| `searchCategoryAll` | `100` | The ceiling on **Show all ›**, which re-fetches the whole drill-in this deep. Arbitrary on purpose: past a hundred rows of one category nobody is reading, they are searching again. Minimum 1. |
| `searchDelay` | `600` | Milliseconds of no typing before a merged search runs itself, so a term does not need Enter. One request per pause, not per keystroke; the search row stays on screen while the pause is waited out, and Enter still runs it immediately. `0` turns it off and leaves the search row as the only way in. |
| `searchCategory` | `""` | Which categories the search row queries, passed to the CLI as `-c`. One name, or several in priority order — `"artists,tracks"`. **Empty is usually right in a merged search**: the CLI then asks each service for its `all` where it declares one (few do), else `tracks`, `artists` and `albums`, else whatever it lists first, and interleaves the answers so one service's three rows are a song, an artist and an album rather than three songs. **With `searchService` naming one service it is the opposite** — a single-service search with no `-c` picks exactly one category, `all` where the service has one and its first otherwise, which is how a search for an artist comes back with no artist. Set a list there: `"tracks,artists,albums"`. Set it to narrow the field — a service with no category by a given name is skipped rather than searched in the wrong one, so `"albums"` asks only services that really have albums. Pinning a *single* category is what makes a search for an artist return no artist, so prefer a list, or nothing. `x2rock search -s <service>` with no term lists what a service offers. |
| `browseServices` | discovered | Which services the picker offers to **walk**, as an array of names. A service's own containers — a personal library, a "For You", a genre tree — are the half of a service no search term can name. Unset, the list is discovered: a row for `searchService`, then one per account this machine has linked (`x2rock accounts` shows them), because `x2rock link` already named the services that matter. Set it to choose by hand — an anonymous service beyond `searchService` only gets a row this way — and `[]` turns browsing off. `"all"`, the string rather than an array, lists **every service the household can reach**, which is what `x2rock browse` prints and a different set from the accounts this machine has linked: a service added in the Sonos app appears here without being linked locally and without editing this file again. It is read when the picker opens, from the catalogue the CLI has cached, so it costs no round trip until a service is chosen; a household with dozens of services makes a long list, and the picker's filter box is how you get through it. |
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
| `thumbsUp` / `thumbsDown` | `󰔓` / `󰔑` | Room row — rate the current track, where the service offers it (a Pandora-shaped radio feature; never a Live broadcast). Shown only where the daemon reports a real track id (`x2rock:hasTrackId`) — so not on a live stream, a `play-url` stream or the TV input, where a thumb could only fail. Whether the *service* publishes ratings is still unknowable without the round trip pressing the button pays for, so a thumb can still fail on Spotify |
| `mute` | `󰝟` | Where a muted room's percentage would be, beside its dimmed slider |
| `music` | `󰝚` | Opens that room's music picker — favorites, kept items, browsing and search |
| `group` | `󰌷` | Opens that room's grouping panel |
| `ungroup` | `󰌸` | Sends one room back out on its own |
| `normalize` | `󰓦` | Grouping panel, opposite "Playing together" — sets every member to the group's level. Shown only while the members' levels differ |
| `tv` | `󰠹` | Switches a soundbar to its TV input, and stands in for cover art while it is on TV |
| `queue` | `󰲹` | Opens that room's queue |
| `radio` | `󰐻` | Before the name, when the room is playing a live stream. Hovering it names the station. In the picker it also marks a row the service types `stream` or `program` — a station, a Radio Paradise channel, an artist station, a saved "Favorites Radio": continuous, with nothing to seek |
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

The picker hides favorites the household can no longer play — the ones the
Sonos app greys out after their service is removed. It goes by `playable: false`
from `x2rock favorites --json`, which is the CLI's inference rather than a flag
the player sends: a favorite carrying neither a service nor a content type is
what those leftovers look like. x2rock can neither delete nor re-add a
favorite, so a dead one here would be a row with no action behind it; it is
left out rather than shown inert. Re-add the service in the Sonos app and its
favorites return on their own.

Anything the bar's font can draw works, including plain text — `"music":
"fav"` is valid. If a glyph comes out as a box, the font lacks that codepoint;
`fc-list ":charset=<hex>"` lists the fonts that have it.

### Words

| Key | Default |
|---|---|
| `playing` / `paused` | `playing` / `paused` — beside each room name |
| `fixedVolume` | `fixed` — in place of the percentage on a room whose volume is set on an amplifier |
| `loading` | `Loading…` |
| `filterHint` | `Type to filter` — the picker's filter placeholder. Filters favorites and kept items, and whatever container is open |
| `noMatch` | `No match` |
| `searchFor` | `Search %1` — the row that runs a query against one service. `%1` is the service |
| `searchEverywhere` / `searchLinked` | `Search all services` / `Search linked services` — the same row when `searchService` is `"all"` or `"linked"`, where no single service can be named |
| `searching` / `searchError` | `Searching…` / `Could not reach %1` |
| `searchFailed` | `Search failed` — in place of `searchError` for a merged search, which cannot blame one service |
| `addToQueue` | `Add to queue` — the `+` button's tooltip |
| `untitledTrack` | `(no title from the player)` — a queue row the player holds no metadata for |
| `link` | `Link` — on a service in the index that has no account on this machine. Deliberately not "register": linking stores *this machine's* token, which buys search and browse. What makes a service's tracks **queue** is the household holding its own account, added in the Sonos app, which nothing in the widget can do |
| `more` / `showAll` | `More` / `Show all` — on the right of a heading, beside the chevron, saying what pressing it does. A service heading always says `More`; a category heading says `More` to reach its page, then `Show all` to reach the rest, then nothing |
| `kindArtists` / `kindTracks` / `kindAlbums` / `kindPlaylists` / `kindStations` / `kindPodcasts` / `kindAll` | `Artists` / `Songs` / `Albums` / `Playlists` / `Stations` / `Podcasts` / `Everything` — headings inside one service's results, keyed by the **category id**, which is not always the word shown: the id is `tracks` and the heading is "Songs". A category with no key here is shown as the service spells it |
| `noResultsOn` | `Nothing on %1` — the row shown when a search finds nothing. `%1` is the service, or `everywhere` / `linkedServices` below. It names its haystack because it sits *above* any favorites and bookmarks that did match, where a bare "nothing" would look like a verdict on them |
| `everywhere` / `linkedServices` | `any service` / `the linked services` — what `noResultsOn` puts in `%1` for a merged search |
| `noResults` | `Nothing found` — no longer used; kept so an existing override does not change anything. Override `noResultsOn` instead |
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
| `normalize` | `normalize` — shown on hover beside its glyph |
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
| `u` / `d` | Rate the current track up or down, where the service offers it. |
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
| Grouping | Leaves the group, on a member; joins it, on a room outside | `←` / `→` set the selected member's own volume, not the group's. `n` normalizes the members to the group's level, while the button is shown |

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
- `preview.png` — gallery screenshot for marketplace discovery.
- `LICENSE` — 0BSD open source license.
