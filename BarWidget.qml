import QtQuick
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Ui
import qs.Commons

// Sonos rooms in the bar, one row per room in the popup.
//
// Everything shown here is event-driven off the x2rock daemon's per-room MPRIS
// players (org.mpris.MediaPlayer2.x2rock-<room>) - nothing polls. Transport and
// the volume slider talk MPRIS directly; only the scroll gesture shells out to
// `x2rock vol +N -r <room>`, because a scroll is a stateless control and Sonos
// wants those as *relative* changes, which MPRIS cannot express.
//
// When the daemon is not running there are no players and the widget hides.
BarWidget {
  id: root
  moduleName: "x2rock.sonos"

  readonly property var rooms: {
    var players = Mpris.players ? Mpris.players.values : []
    var found = []
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (p && String(p.dbusName || "").indexOf("org.mpris.MediaPlayer2.x2rock-") === 0)
        found.push(p)
    }
    found.sort(function(a, b) {
      return String(a.identity || "").localeCompare(String(b.identity || ""))
    })
    return found
  }

  // The room the pill shows and scroll adjusts: last interacted with, else the
  // first one playing, else the first.
  property string focusedName: ""
  readonly property var focused: {
    for (var i = 0; i < rooms.length; i++)
      if (rooms[i].identity === focusedName) return rooms[i]
    for (var j = 0; j < rooms.length; j++)
      if (rooms[j].isPlaying) return rooms[j]
    return rooms.length > 0 ? rooms[0] : null
  }

  property bool popupOpen: false
  // Only the rooms popup. The picker, the queue and the grouping panel are
  // separate surfaces with owners of their own, because a shared one would
  // have each closing the other: a KeyboardPanel dismisses by calling
  // owner.close().
  function close() { popupOpen = false }

  // What the bar looks for before it will summon a widget: `open()`, `close()`
  // and an `opened` property, all three or none (Bar.findPanelWidget). With
  // them a keybinding or `omarchy-shell shell summon x2rock.sonos` opens the
  // rooms popup exactly as a click on the pill does.
  readonly property bool opened: popupOpen
  function open() { popupOpen = true }

  // Favorites are the one thing here that MPRIS cannot carry - it has no notion
  // of them, and Quickshell's Mpris does not implement the optional Playlists
  // interface either - so they come from the CLI instead. Fetched only when the
  // picker is first opened, never on a timer: the widget still does not poll.
  property var favorites: []
  property bool favoritesLoaded: false
  property string favoritesStatus: ""

  // x2rock's own saved items, as distinct from the household's favorites: an
  // id kept from something that played once, so it can be started again without
  // the service search that most services will not allow. Same JSON shape as
  // favorites, deliberately, so the picker concatenates rather than translates.
  property var bookmarks: []
  property bool bookmarksLoaded: false
  /// The queue panel's cursor, over the rows as listed. -1 until the first
  /// list arrives and puts it on whatever is playing.
  property int queueIndex: -1

  /// The room the picker is choosing for; empty when the picker is closed.
  property string pickingFor: ""
  property string filterText: ""
  property int selectedIndex: 0

  // Searching a music service, which is the one thing here that leaves the LAN
  // - and it does so in a Process of its own, never in the daemon, so a slow or
  // unreachable service cannot delay a single control. See "Rule: search never
  // enters the daemon" in docs/architecture.md.
  property var searchResults: []
  property string searchStatus: ""
  /// The term `searchResults` are answers to. Results are only shown while the
  /// typed text still matches it, so editing the query cannot leave stale hits
  /// sitting under a different word.
  property string searchedTerm: ""
  /// The term in flight, kept because the field can be edited while the
  /// subprocess runs and the reply belongs to what was asked, not to what is
  /// typed now.
  property string pendingTerm: ""

  // The services this machine holds a linked account for, read from
  // `x2rock accounts --json`. That command reads one local file - no player,
  // no service, no daemon - so it is the cheapest question the picker asks.
  // Feeds the default `browseServices`; see the binding below for why.
  property var linkedServices: []

  // Walking a service's containers. A stack rather than a current-id, because
  // the useful gesture is "back where I came from" and only the path knows
  // where that is. Empty means the picker is at home, showing favorites.
  //
  // Each frame is { service, id, title }. The first frame's id is "root", which
  // is where every service starts.
  property var browseStack: []
  property var browseItems: []
  property string browseStatus: ""
  /// The frame `browseItems` answers. A reply that arrives after someone has
  /// already gone back belongs to a container nobody is looking at, and showing
  /// it would silently move them somewhere they did not ask to be.
  property string browseAnsweredFor: ""

  readonly property bool browsing: browseStack.length > 0
  readonly property var browseFrame: browsing ? browseStack[browseStack.length - 1] : null

  // The same local filter the favorites list gets, over whatever container is
  // open. No round trip: a container is already in hand, and typing must not
  // put a network call behind a keystroke.
  readonly property var shownBrowseItems: {
    var needle = filterText.toLowerCase().trim()
    if (needle === "") return browseItems
    var found = []
    for (var i = 0; i < browseItems.length; i++) {
      var it = browseItems[i]
      var name = String(it.name || "").toLowerCase()
      var by = String(it.description || "").toLowerCase()
      if (name.indexOf(needle) !== -1 || by.indexOf(needle) !== -1) found.push(it)
    }
    return found
  }

  // Name or service, so "sonos" finds the radio stations and "bed" finds the
  // bedtime mixes. There are dozens of these; scrolling to one is the fallback,
  // not the plan.
  readonly property var shownFavorites: {
    var needle = filterText.toLowerCase().trim()
    if (needle === "") return favorites
    var found = []
    for (var i = 0; i < favorites.length; i++) {
      var favorite = favorites[i]
      var name = String(favorite.name || "").toLowerCase()
      var service = String(favorite.service || "").toLowerCase()
      if (name.indexOf(needle) !== -1 || service.indexOf(needle) !== -1)
        found.push(favorite)
    }
    return found
  }

  // Favorites and search hits in one list, because they answer the same
  // question - what should this room play - and a person filtering for
  // something they own should not have to decide in advance whether they own
  // it. The CLI emits both with the same field names, so this is a
  // concatenation rather than a translation.
  //
  // The search row is an *action*, not a result: nothing is sent until it is
  // chosen. Searching on every keystroke would put a network round trip behind
  // typing, which is the behaviour this widget exists to avoid.
  readonly property var pickerRows: {
    // Inside a container the list is that container and nothing else. Mixing
    // favorites into it would make "back" ambiguous and the count meaningless.
    if (browsing) {
      var out = [{
        kind: "up",
        item: {
          name: strings.up.arg(browseStack.length > 1
                               ? browseStack[browseStack.length - 2].title
                               : browseFrame.service),
          type: "",
          art_url: ""
        }
      }]
      // Only once the reply belongs to the container on screen. Until then the
      // status line says what is happening and the list stays honest.
      if (browseAnsweredFor === browseKey(browseFrame)) {
        var walk = shownBrowseItems
        for (var b = 0; b < walk.length; b++)
          out.push({ kind: walk[b].container ? "container" : "browseItem", item: walk[b] })
        if (walk.length === 0)
          out.push({ kind: "note", item: { name: browseItems.length > 0
                                                 ? strings.noMatch : strings.browseEmpty,
                                           type: "", art_url: "" } })
      }
      return out
    }

    var rows = []
    var favs = shownFavorites
    for (var i = 0; i < favs.length; i++) rows.push({ kind: "favorite", item: favs[i] })
    // After the household's own, because favorites are what a household shares
    // and these are what this machine happens to remember.
    var kept = shownBookmarks
    for (var k = 0; k < kept.length; k++) rows.push({ kind: "bookmark", item: kept[k] })

    // The way in to each service's own containers, and an *action* like the
    // search row: nothing leaves the machine until one is chosen. Listed after
    // what is already in hand, because a name someone saved beats a tree they
    // have to walk.
    var services = browseServices
    for (var v = 0; v < services.length; v++)
      rows.push({
        kind: "browseService",
        item: { name: strings.browseIn.arg(services[v]), type: "", art_url: "",
                service: services[v] }
      })

    var term = filterText.trim()
    if (!searchEnabled || term === "") return rows

    if (searchedTerm === term) {
      var hits = searchResults
      // A hit is not always a thing to play. Every Mixcloud search result is a
      // `tag:` collection, so a search can answer entirely in places - and
      // offering one as a track would hand a container id to `play-item`.
      for (var j = 0; j < hits.length; j++)
        rows.push({ kind: hits[j].container ? "container" : "result", item: hits[j] })
      if (hits.length === 0)
        rows.push({ kind: "note", item: { name: strings.noResults, type: "", art_url: "" } })
    } else {
      rows.push({
        kind: "search",
        item: { name: strings.searchFor.arg(searchService), type: "", art_url: "" }
      })
    }
    return rows
  }

  /// A frame's identity, for telling "the reply I am waiting for" from "a reply
  /// to somewhere I have already left".
  function browseKey(frame) {
    return frame ? frame.service + "\u0000" + frame.id : ""
  }

  function activateRow(row) {
    if (!row) return
    if (row.kind === "favorite") root.playFavorite(root.pickingFor, row.item)
    else if (row.kind === "bookmark") root.playBookmark(root.pickingFor, row.item)
    else if (row.kind === "result") root.playSearchResult(root.pickingFor, row.item)
    else if (row.kind === "search") root.runSearch()
    else if (row.kind === "browseService") root.browseInto(row.item.service, "root", row.item.service)
    else if (row.kind === "container")
      // The row's own service when it has one - a container can arrive as a
      // *search* hit, with no browse frame open to inherit a service from.
      root.browseInto(row.item.service || (root.browseFrame ? root.browseFrame.service : ""),
                      row.item.id, row.item.name)
    else if (row.kind === "browseItem") root.playSearchResult(root.pickingFor, row.item)
    else if (row.kind === "up") root.browseUp()
    // "note" is not actionable; selecting it and pressing Enter does nothing,
    // which is better than closing the picker on a row that said "Nothing
    // found".
  }

  readonly property var shownBookmarks: {
    var needle = filterText.toLowerCase().trim()
    if (needle === "") return bookmarks
    var found = []
    for (var i = 0; i < bookmarks.length; i++) {
      var b = bookmarks[i]
      var name = String(b.name || "").toLowerCase()
      var service = String(b.service || "").toLowerCase()
      var by = String(b.description || "").toLowerCase()
      if (name.indexOf(needle) !== -1 || service.indexOf(needle) !== -1
          || by.indexOf(needle) !== -1)
        found.push(b)
    }
    return found
  }

  // The picker dismisses itself, rather than the widget: see close() above.
  QtObject {
    id: pickerOwner
    function close() { root.closePicker() }
  }

  QtObject {
    id: queueOwner
    function close() { root.closeQueue() }
  }

  function openPicker(room) {
    root.focusedName = room
    root.filterText = ""
    root.selectedIndex = 0
    root.clearSearch()
    filterField.text = ""
    root.pickingFor = room
    // One surface at a time; the rooms popup is where this was chosen from.
    root.popupOpen = false
    root.clearBrowse()
    root.loadFavorites()
    root.loadBookmarks()
    // Re-read on every open, like favorites: an account linked in a terminal
    // minutes ago should not need a shell restart to reach the picker.
    root.loadLinkedServices()
  }

  function closePicker() {
    root.pickingFor = ""
    root.filterText = ""
    root.clearSearch()
    root.clearBrowse()
  }

  function clearSearch() {
    root.searchResults = []
    root.searchStatus = ""
    root.searchedTerm = ""
    root.pendingTerm = ""
  }

  Process {
    id: favoritesProc
    command: [root.command, "favorites", "--json"]
    onExited: function(code) {
      if (code !== 0 && !root.favoritesLoaded)
        root.favoritesStatus = root.strings.favoritesError
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // The CLI prints `[]` for none; nothing at all is a failure, and the
        // exit code says so. Reading it as an empty list would mark the load
        // done and leave the error branch above with nothing left to do.
        if (!text || text.trim() === "") return
        var parsed
        try {
          parsed = JSON.parse(text)
        } catch (e) {
          root.favoritesStatus = root.strings.favoritesError
          return
        }
        if (!Array.isArray(parsed)) {
          root.favoritesStatus = root.strings.favoritesError
          return
        }
        root.favorites = parsed
        root.favoritesLoaded = true
        root.favoritesStatus = parsed.length > 0 ? "" : root.strings.noFavorites
      }
    }
  }

  // Its own Process, deliberately. A hung or failed search is confined to this
  // object: rooms, transport and volume all come from MPRIS and never wait on
  // it. The failure handling copies favoritesProc's, and for the same reasons.
  Process {
    id: searchProc
    onExited: function(code) {
      if (code !== 0) {
        // Blunt from the CLI, gentle here: the results already on screen stay,
        // and the failure is one line rather than an empty list.
        root.searchStatus = root.strings.searchError.arg(root.searchService)
        root.pendingTerm = ""
      }
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // Nothing at all is a failure and the exit code says so; `[]` is a real
        // answer meaning the service has nothing. Reading the first as the
        // second would replace an error with a wrong result.
        if (!text || text.trim() === "") return
        var parsed
        try {
          parsed = JSON.parse(text)
        } catch (e) {
          root.searchStatus = root.strings.searchError.arg(root.searchService)
          return
        }
        if (!Array.isArray(parsed)) {
          root.searchStatus = root.strings.searchError.arg(root.searchService)
          return
        }
        root.searchResults = parsed
        // The reply answers what was asked, which may no longer be what is
        // typed. Binding to pendingTerm rather than to the field is what keeps
        // a slow answer from appearing under a query nobody made.
        root.searchedTerm = root.pendingTerm
        root.searchStatus = ""
        root.selectedIndex = 0
      }
    }
  }

  function runSearch() {
    var term = root.filterText.trim()
    if (term === "" || !root.searchEnabled || searchProc.running) return
    root.pendingTerm = term
    root.searchStatus = root.strings.searching
    var command = [root.command, "search", "-s", root.searchService,
                   "--json", "--count", String(root.searchCount)]
    // Without this the CLI searches the service's default category, which for
    // a service with no "all" is whatever its presentation map lists first -
    // Plex leads with artists, and a song title searched there finds nothing.
    if (root.searchCategory !== "") command.push("-c", root.searchCategory)
    command.push(term)
    searchProc.command = command
    searchProc.running = true
  }

  // Its own Process again, for the reasons searchProc has one: browsing leaves
  // the LAN, and a service that hangs must not reach anything the daemon does.
  Process {
    id: browseProc
    onExited: function(code) {
      if (code !== 0) {
        // Gentle here, blunt in the CLI. A container that will not open leaves
        // the path where it is, so "back" still works: the alternative is
        // dropping someone out of a tree they were halfway down.
        root.browseStatus = root.strings.browseError
      }
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // `[]` is an empty container, which is an answer; nothing at all is a
        // failure and the exit code already said so.
        if (!text || text.trim() === "") return
        var parsed
        try {
          parsed = JSON.parse(text)
        } catch (e) {
          root.browseStatus = root.strings.browseError
          return
        }
        if (!Array.isArray(parsed)) {
          root.browseStatus = root.strings.browseError
          return
        }
        root.browseItems = parsed
        root.browseAnsweredFor = root.browseKey(root.browseFrame)
        root.browseStatus = ""
        root.selectedIndex = 0
      }
    }
  }

  /// Descend. The frame is pushed before the reply arrives so the path and the
  /// back row are correct while it is still in flight.
  function browseInto(service, id, title) {
    if (!service || !id) return
    var stack = root.browseStack.slice()
    stack.push({ service: service, id: id, title: String(title || id) })
    root.browseStack = stack
    root.browseItems = []
    root.browseAnsweredFor = ""
    root.selectedIndex = 0
    // The filter belonged to the list being left. Carrying it into a new
    // container would hide most of it for a reason nobody could see.
    root.filterText = ""
    filterField.text = ""
    root.fetchBrowse()
  }

  /// Back one level, and out to favorites from the top.
  function browseUp() {
    var stack = root.browseStack.slice()
    stack.pop()
    root.browseStack = stack
    root.browseItems = []
    root.browseAnsweredFor = ""
    root.browseStatus = ""
    root.selectedIndex = 0
    root.filterText = ""
    filterField.text = ""
    if (stack.length > 0) root.fetchBrowse()
  }

  function fetchBrowse() {
    var frame = root.browseFrame
    if (!frame || browseProc.running) return
    root.browseStatus = root.strings.browseLoading
    browseProc.command = [root.command, "browse", "-s", frame.service,
                          "--json", "--count", String(root.browseCount), frame.id]
    browseProc.running = true
  }

  function clearBrowse() {
    root.browseStack = []
    root.browseItems = []
    root.browseStatus = ""
    root.browseAnsweredFor = ""
  }

  /// Whether a row can be added to a queue, which the CLI decides rather than
  /// this file. `search`/`browse --json` carry `queueable` for exactly this:
  /// a live stream has no queue form, a container may be refused even when a
  /// service marks it playable, and a service missing from the player's type
  /// list has no cdudn to name the account with. Only the CLI knows the third.
  ///
  /// Strictly `=== true`, like every other flag read here: an older CLI sends
  /// no such field, and undefined must hide the button rather than offer one
  /// that cannot work.
  function canQueue(item) {
    return !!(item && item.queueable === true)
  }

  Process { id: queueItemProc }

  /// Add without playing, and without closing the picker - the point of a
  /// separate button is queueing several things in a row, which a picker that
  /// dismissed itself would make worse than pressing play once.
  function queueSearchResult(room, item) {
    if (!item || queueItemProc.running || !root.canQueue(item)) return
    var service = String(item.service || root.searchService)
    var command = [root.command, "queue-item", "-s", service,
                   String(item.id), "--title", String(item.name || ""),
                   "-r", room]
    if (item.type) command.push("--kind", String(item.type))
    queueItemProc.command = command
    queueItemProc.running = true
  }

  // `play-item`, not `search --play N`: the widget already holds the id, and
  // re-running the search to find it again would cost a second round trip and
  // could land on a different hit if the service reordered.
  function playSearchResult(room, item) {
    if (!item || playFavoriteProc.running) return
    root.focusedName = room
    // The item's own service, falling back to the configured one. A browse row
    // can come from a service that is not `searchService`, and playing it as
    // though it did would hand one service's id to another.
    var service = String(item.service || root.searchService)
    // The row's kind decides how it plays: a live stream is streamed, and
    // anything on-demand has to go in the queue, because the player is the only
    // thing that can resolve a service's protected media. Passing it saves the
    // CLI a guess it would otherwise have to make by trying and falling back.
    var command = [root.command, "play-item", "-s", service,
                   String(item.id), "--title", String(item.name || ""),
                   "-r", room]
    if (item.type) command.push("--kind", String(item.type))
    playFavoriteProc.command = command
    playFavoriteProc.running = true
    root.closePicker()
    root.backToRooms()
  }

  // Only worth offering when there is a title to hang a name on. The CLI
  // refuses a live stream with no id of its own, and a button that always looks
  // available and sometimes silently does nothing is worse than a dim one.
  function canKeep(player) {
    return !!(player && player.trackTitle)
  }

  Process {
    id: keepProc
    // Re-read afterwards so a kept item shows in the picker immediately rather
    // than at the next open.
    onExited: root.loadBookmarks()
  }

  function keepPlaying(room) {
    if (keepProc.running) return
    keepProc.command = [root.command, "keep", "-r", room]
    keepProc.running = true
  }

  Process {
    id: bookmarksProc
    command: [root.command, "bookmarks", "--json"]
    onExited: function(code) {
      // Quieter than favorites on purpose: an empty bookmark list is the normal
      // state until someone keeps something, so a failure here says nothing and
      // simply leaves the section absent rather than claiming an error.
      if (code === 0) root.bookmarksLoaded = true
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!text || text.trim() === "") return
        try {
          var parsed = JSON.parse(text)
          if (Array.isArray(parsed)) root.bookmarks = parsed
        } catch (e) {
          // Leave whatever was already listed; see the favorites picker.
        }
      }
    }
  }

  function loadBookmarks() {
    if (bookmarksProc.running) return
    bookmarksProc.running = true
  }

  // `x2rock link` is already the act of configuration - a deliberate statement
  // that this household uses that service from this machine - so the picker
  // reads what it left behind rather than asking for the same names to be
  // typed a second time into `shell.json`. Failure is silent because the
  // fallback is exactly the un-discovered default: a row for `searchService`.
  Process {
    id: accountsProc
    command: [root.command, "accounts", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!text || text.trim() === "") return
        try {
          var parsed = JSON.parse(text)
          if (!Array.isArray(parsed)) return
          var names = []
          for (var i = 0; i < parsed.length; i++) {
            var name = String((parsed[i] && parsed[i].service) || "")
            if (name !== "" && names.indexOf(name) === -1) names.push(name)
          }
          // By name. The CLI's order is by service id, and "181 before 254"
          // means nothing to someone reading a list of rows.
          names.sort(function(a, b) {
            return a.toLowerCase() < b.toLowerCase() ? -1 : 1
          })
          root.linkedServices = names
        } catch (e) {
          // Leave whatever was already known; see the favorites picker.
        }
      }
    }
  }

  function loadLinkedServices() {
    if (accountsProc.running) return
    accountsProc.running = true
  }

  // By name, which is what `bookmark` matches on, and which is unique enough:
  // keeping the same object twice replaces rather than duplicates.
  function playBookmark(room, item) {
    if (!item || playFavoriteProc.running) return
    root.focusedName = room
    playFavoriteProc.command = [root.command, "bookmark", String(item.name || ""), "-r", room]
    playFavoriteProc.running = true
    root.closePicker()
    root.backToRooms()
  }

  Process { id: playFavoriteProc }

  // Re-read on every open. Favorites change rarely, but they do change - and
  // whoever added one in the Sonos app should not have to restart the shell to
  // see it. The list already on screen stays up while this runs, so a refresh
  // costs nothing visible; only a first load has anything to say.
  function loadFavorites() {
    if (favoritesProc.running) return
    if (!root.favoritesLoaded) root.favoritesStatus = root.strings.loading
    favoritesProc.running = true
  }

  // By id, not name: ids are unambiguous, and these names run to emoji and
  // full-width brackets. Passed as arguments rather than a command line, so
  // nothing needs quoting.
  function playFavorite(room, favorite) {
    if (!favorite || playFavoriteProc.running) return
    root.focusedName = room
    playFavoriteProc.command = [root.command, "favorite", String(favorite.id), "-r", room]
    playFavoriteProc.running = true
    root.closePicker()
    root.backToRooms()
  }

  /// Choosing something to play is the end of that errand, so the panel that
  /// chose it gives way to the list it was opened from, where the room is
  /// right there to pause or turn up. Escape still means gone, not back - and
  /// editing a queue or building a group is not an errand that ends with one
  /// row, so those panels stay where they are.
  function backToRooms() {
    root.popupOpen = true
  }

  // The daemon publishes each group's rooms as x2rock:members, because MPRIS
  // describes one player and cannot say that player is really several speakers.
  /// What a soundbar is receiving, empty unless it is on its TV input.
  function inputFormatOf(player) {
    var md = player && player.metadata ? player.metadata["x2rock:inputFormat"] : null
    return md ? String(md) : ""
  }

  /// Whether the room is on its TV input; the format can be empty there too.
  function onTvInput(player) {
    return !!(player && player.metadata && player.metadata["x2rock:onTvInput"] === true)
  }

  function hasTvInput(player) {
    return !!(player && player.metadata && player.metadata["x2rock:hasTvInput"] === true)
  }

  /// Whether what is playing is a live stream - internet radio, and anything
  /// else the player resolves continuously rather than as an item. Strictly
  /// `=== true`, like the other flags: an older daemon sends no such key, and
  /// undefined must read as "no" rather than mark every room a station.
  function isLiveStream(player) {
    return !!(player && player.metadata && player.metadata["x2rock:isLiveStream"] === true)
  }

  /// The station behind a live stream, when the title is not already it.
  ///
  /// Empty for everything else, including a station whose name *is* the title -
  /// TuneIn has no track, so the name on the line above is already the station
  /// and repeating it says nothing. Sonos Radio is the case this exists for: it
  /// names the track and leaves the station only in the container, so without
  /// this the row says "Intervallo (from \"Veruschka\") (II)" and never says
  /// what it is playing on.
  function stationOf(player) {
    var name = player && player.metadata ? player.metadata["x2rock:stationName"] : ""
    return String(name || "")
  }

  /// Which mark a picker row earns, or "" for the rows that earn none.
  ///
  /// This cannot ask the question the room row asks: the daemon's flag
  /// describes what is *playing*, and a row is a thing that is not. The three
  /// sources share field names but not vocabularies, because each passes
  /// through what its own origin called the item:
  ///
  /// - `search` and `browse` carry SMAPI's `itemType`, where a station is
  ///   `stream`. Verified against TuneIn on 2026-09-01.
  /// - `favorites` say **`STREAM`**, in capitals. Verified 2026-09-01 against a
  ///   Virgin Radio UK station saved from the Sonos app - the first favorite
  ///   this household has had. Note this was *predicted wrong*: the guess was
  ///   the DIDL-Lite class `object.item.audioItem.audioBroadcast`, and the mark
  ///   appears anyway only because the comparison lowercases first. The
  ///   `audiobroadcast` clause below is now untested rather than reasoned -
  ///   kept because some other service may well answer that way, but nothing
  ///   here has ever seen it.
  /// - `bookmarks` carries whatever x2rock stored, which is `stream` for a kept
  ///   station and so needs nothing of its own.
  ///
  /// An audiobook is `AUDIOBOOK` from a favorite and `chapter.audiobook` from
  /// a playing Audible track, both verified 2026-09-01, so that one matches on
  /// a substring where the others match whole.
  ///
  /// A podcast *show* is `show`, and gets the microphone. Its episodes are
  /// typed `track` - identical to a song, with nothing on the row telling them
  /// apart - so the show is the only honest place to mark. It is also the row
  /// someone actually chooses from; the episodes below inherit the context by
  /// being where you already are.
  ///
  /// Unknown reads as "": an unmarked station is a smaller wrong than a marked
  /// album, and a service typing things this file has never seen gets no mark
  /// rather than a guessed one.
  function markFor(item) {
    var kind = String((item && item.type) || "").toLowerCase()
    if (kind === "stream" || kind.indexOf("audiobroadcast") !== -1)
      return root.glyphs.radio
    if (kind === "show")
      return root.glyphs.podcast
    // Substring rather than equality: a favorite says AUDIOBOOK and a playing
    // Audible track says chapter.audiobook, and both are the same answer.
    if (kind.indexOf("audiobook") !== -1)
      return root.glyphs.audiobook
    return ""
  }

  Process { id: tvProc }

  function switchToTv(room) {
    if (tvProc.running) return
    root.focusedName = room
    tvProc.command = [root.command, "tv", "-r", room]
    tvProc.running = true
  }

  function membersOf(player) {
    var members = player && player.metadata ? player.metadata["x2rock:members"] : null
    return (members && members.length) ? members : []
  }

  // Rooms in the household, not players on the bus: a grouped household
  // publishes fewer players than it has speakers.
  readonly property int totalRooms: {
    var count = 0
    for (var i = 0; i < rooms.length; i++) {
      var members = membersOf(rooms[i])
      count += members.length > 0 ? members.length : 1
    }
    return count
  }

  // One group holding every room. Counting members rather than players is what
  // separates this from a household that simply has one speaker in it.
  readonly property bool partying: rooms.length === 1 && totalRooms > 1

  Process { id: partyProc }

  // Party from whichever room was clicked: that room hosts, everyone joins it
  // and plays what it plays. Once everyone is in, the same button ends it.
  function toggleParty(room) {
    if (partyProc.running) return
    root.focusedName = room
    partyProc.command = root.partying
      ? [root.command, "party", "off"]
      : [root.command, "party", "-r", room]
    partyProc.running = true
  }

  // Grouping needs no CLI read: x2rock:members already says which rooms each
  // group holds, so the lists below are bound straight to MPRIS state. That
  // also means they correct themselves - regrouping republishes the players,
  // and the bindings follow - rather than needing a refresh after every change.
  property string groupingFor: ""

  /// Every room in the household, whichever group it currently sits in.
  readonly property var allRooms: {
    var names = []
    for (var i = 0; i < rooms.length; i++) {
      var members = membersOf(rooms[i])
      if (members.length === 0 && rooms[i].identity) members = [rooms[i].identity]
      for (var j = 0; j < members.length; j++)
        if (names.indexOf(members[j]) === -1) names.push(members[j])
    }
    return names.sort()
  }

  /// The rooms grouped with the one being edited, found by membership rather
  /// than by name: grouping renames a group after its coordinator, so the
  /// player called "Kitchen" may not be there after the next change.
  readonly property var groupingMembers: {
    for (var i = 0; i < rooms.length; i++) {
      var members = membersOf(rooms[i])
      if (members.indexOf(groupingFor) !== -1) return members
    }
    return groupingFor === "" ? [] : [groupingFor]
  }

  /// The room whose player the group is: its identity, so the row that would
  /// have it "leave" its own group can be left out. Removing the coordinator is
  /// not something the CLI will do.
  readonly property string groupingCoordinator: {
    for (var i = 0; i < rooms.length; i++)
      if (membersOf(rooms[i]).indexOf(groupingFor) !== -1) return rooms[i].identity || ""
    return ""
  }

  readonly property var groupingOthers: {
    var out = []
    for (var i = 0; i < allRooms.length; i++)
      if (groupingMembers.indexOf(allRooms[i]) === -1) out.push(allRooms[i])
    return out
  }

  // A room on its own is not a group to list the members of, so the panel
  // draws none - and the keyboard has to count the same rows the eye does.
  readonly property var groupingShownMembers: groupingMembers.length > 1
    ? groupingMembers : []
  readonly property int groupingRowCount: groupingShownMembers.length + groupingOthers.length

  /// The panel's cursor, over the rows as drawn: members first, then the
  /// rooms that could join them. Hovering moves it too, so there is one
  /// cursor rather than one per input device.
  property int groupingIndex: 0

  function groupingRoomAt(at) {
    if (at < 0 || at >= groupingRowCount) return ""
    return at < groupingShownMembers.length
      ? groupingShownMembers[at]
      : groupingOthers[at - groupingShownMembers.length]
  }

  function groupingIsMember(at) {
    return at >= 0 && at < groupingShownMembers.length
  }

  function moveGroupingIndex(step) {
    if (groupingRowCount === 0) return
    root.groupingIndex = Math.max(0, Math.min(groupingRowCount - 1, groupingIndex + step))
  }

  // Enter does what clicking the row does: a member leaves, an outsider
  // joins. The coordinator is the group, so it has no leave target and the
  // key has nothing to do on it either.
  function activateGroupingRow() {
    var room = groupingRoomAt(groupingIndex)
    if (!room) return
    if (!groupingIsMember(groupingIndex)) return joinRoom(room)
    if (room !== groupingCoordinator) partRoom(room)
  }

  /// What a grouped room's slider shows: what was asked for until the player
  /// says otherwise.
  function groupingLevelOf(room) {
    var pending = root.pendingVolumes[room]
    if (pending !== undefined) return pending
    var at = groupingMembers.indexOf(room)
    return at >= 0 && groupingVolumes.length > at ? groupingVolumes[at] / 100 : 0
  }

  // The same 2% step the scroll gesture and the popup's arrows use. Only
  // members have a level of their own; a room outside the group has none.
  function nudgeGroupingVolume(step) {
    if (!groupingIsMember(groupingIndex)) return
    var room = groupingRoomAt(groupingIndex)
    setRoomVolume(room, Math.max(0, Math.min(1, groupingLevelOf(room) + step)))
  }

  QtObject {
    id: groupingOwner
    function close() { root.closeGrouping() }
  }

  Process { id: groupingProc }

  function openGrouping(room) {
    root.focusedName = room
    root.groupingIndex = 0
    root.groupingFor = room
    root.popupOpen = false
  }

  /// The one way out, for Escape and click-away alike, so an optimistic
  /// slider value does not outlive the panel it was dragged in.
  function closeGrouping() {
    root.groupingFor = ""
    pendingVolumesTimer.stop()
    root.pendingVolumes = ({})
  }

  /// Bring one room into this group.
  function joinRoom(room) {
    if (groupingProc.running) return
    groupingProc.command = [root.command, "group", room, "-r", root.groupingFor]
    groupingProc.running = true
  }

  /// Each grouped room's own volume, aligned with groupingMembers. Published
  /// by the daemon off playerVolume events, so these follow someone turning a
  /// speaker up from the Sonos app rather than needing a re-read.
  readonly property var groupingVolumes: {
    for (var i = 0; i < rooms.length; i++) {
      var members = membersOf(rooms[i])
      if (members.indexOf(groupingFor) === -1) continue
      var levels = rooms[i].metadata ? rooms[i].metadata["x2rock:memberVolumes"] : null
      // Decimal strings, not numbers: see the daemon's note on why an array of
      // ints does not survive the trip into QML.
      if (!levels || levels.length !== members.length) return []
      var out = []
      for (var j = 0; j < levels.length; j++) out.push(Number(levels[j]) || 0)
      return out
    }
    return []
  }

  // What a slider was just dragged to, per room, until the player confirms it.
  //
  // PanelSlider puts its handle back on the bound value the moment it is
  // released, which for the popup's own slider is instant because that writes
  // MPRIS directly. This one goes out through the CLI and back as an event, and
  // in that gap the handle would snap to the old level and then jump again -
  // reading as "the change did not take". So the asked-for value stands until
  // the real one catches up.
  property var pendingVolumes: ({})

  // A backstop only: a value normally stops being pending the moment the player
  // reports it, below. This catches a command that failed outright, so a slider
  // cannot sit forever showing something the speaker never accepted.
  Timer {
    id: pendingVolumesTimer
    interval: 6000
    onTriggered: root.pendingVolumes = ({})
  }

  /// Let go of a pending level once the player confirms it, so the slider is
  /// following the speaker again rather than its own optimism.
  onGroupingVolumesChanged: {
    var keep = {}
    var settled = false
    for (var room in pendingVolumes) {
      var at = groupingMembers.indexOf(room)
      var reported = (at >= 0 && at < groupingVolumes.length) ? groupingVolumes[at] / 100 : -1
      if (Math.abs(reported - pendingVolumes[room]) < 0.005) {
        settled = true
        continue
      }
      keep[room] = pendingVolumes[room]
    }
    if (settled) pendingVolumes = keep
  }

  /// Volume has its own process: a slider should not be dropped because a
  /// grouping command happens to be in flight, nor hold one up.
  ///
  /// A Process already running ignores a new `command`, so releasing a second
  /// slider while the first is in flight would lose it outright - and the
  /// optimistic value would then sit until the backstop expired, showing
  /// exactly the "it did not take" flicker this is all meant to prevent. So the
  /// latest request per room waits its turn instead.
  property var queuedVolumes: ({})

  Process {
    id: roomVolumeProc
    onExited: root.sendNextVolume()
  }

  function sendNextVolume() {
    if (roomVolumeProc.running) return
    for (var room in root.queuedVolumes) {
      var level = root.queuedVolumes[room]
      var rest = {}
      for (var other in root.queuedVolumes) if (other !== room) rest[other] = root.queuedVolumes[other]
      root.queuedVolumes = rest
      roomVolumeProc.command = [root.command, "vol", String(Math.round(level * 100)),
                                "--player", "-r", room]
      roomVolumeProc.running = true
      return
    }
  }

  /// One room's own level, not the group's. Absolute, because a slider knows
  /// where it is - the same reasoning as the popup's group slider.
  function setRoomVolume(room, level) {
    // A fresh object, not the same one mutated: assigning an unchanged
    // reference back does not count as a change in QML, so the sliders would
    // never see it and would snap to the old level while the command was still
    // in flight - which is exactly what this exists to prevent.
    var pending = {}
    for (var key in root.pendingVolumes) pending[key] = root.pendingVolumes[key]
    pending[room] = level
    root.pendingVolumes = pending
    pendingVolumesTimer.restart()

    // Latest wins per room: an older level for the same slider is worthless.
    var queued = {}
    for (var other in root.queuedVolumes) queued[other] = root.queuedVolumes[other]
    queued[room] = level
    root.queuedVolumes = queued
    root.sendNextVolume()
  }

  /// Send one room back out on its own.
  function partRoom(room) {
    if (groupingProc.running) return
    groupingProc.command = [root.command, "ungroup", room]
    groupingProc.running = true
  }

  // The queue, like favorites, is something MPRIS cannot carry: it describes one
  // track, not the list around it. So the list comes from the CLI, read when the
  // view is opened and again whenever the daemon says the queue moved - never on
  // a timer. x2rock:queueVersion changes however the queue changed, including
  // from the Sonos app, which is what keeps this honest when someone else edits.
  property string queueFor: ""
  property var queueItems: []
  property int queueTotal: 0
  property string queueStatus: ""

  readonly property var queueRoom: {
    for (var i = 0; i < rooms.length; i++)
      if (rooms[i].identity === queueFor) return rooms[i]
    return null
  }

  readonly property string queueVersion: {
    var player = queueRoom
    if (!player || !player.metadata) return ""
    return String(player.metadata["x2rock:queueVersion"] || "")
  }

  // Re-read when the version moves, but only while the view is open: a queue
  // nobody is looking at is not worth a process.
  onQueueVersionChanged: if (queueFor !== "") loadQueue()

  Process {
    id: queueProc
    onExited: function(code) {
      if (code !== 0) root.queueStatus = root.strings.queueError
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // An unreachable player leaves stdout empty. That is not an empty
        // queue, and whichever of this and onExited runs first, the error it
        // sets must be the word that stands.
        if (!text || text.trim() === "") return
        var parsed
        try {
          parsed = JSON.parse(text)
        } catch (e) {
          root.queueStatus = root.strings.queueError
          return
        }
        root.queueItems = parsed.items || []
        root.queueTotal = parsed.total || 0
        root.queueStatus = root.queueItems.length > 0 ? "" : root.strings.nothingQueued
        // Only the first list after opening places the cursor - a reload from
        // a version bump must not drag it out from under whoever is scrolling.
        if (root.queueIndex < 0) {
          root.queueIndex = 0
          for (var i = 0; i < root.queueItems.length; i++)
            if (root.queueItems[i].current === true) root.queueIndex = i
        }
      }
    }
  }

  /// Edits are fire-and-forget; the version bump brings the new list back.
  Process { id: queueEditProc }

  function loadQueue() {
    if (root.queueFor === "" || queueProc.running) return
    if (root.queueItems.length === 0) root.queueStatus = root.strings.loading
    queueProc.command = [root.command, "queue", "--json", "-r", root.queueFor]
    queueProc.running = true
  }

  function openQueue(room) {
    root.focusedName = room
    // Not yet placed: the first list to arrive puts it on the playing track.
    root.queueIndex = -1
    root.queueItems = []
    root.queueTotal = 0
    root.queueStatus = ""
    root.queueFor = room
    root.popupOpen = false
    root.loadQueue()
  }

  function closeQueue() {
    root.queueFor = ""
    root.queueItems = []
  }

  /// Jump to a queue position. `play N` handles making the queue the source
  /// first, which it is not after a radio stream.
  function playTrack(index) {
    if (queueEditProc.running) return
    queueEditProc.command = [root.command, "play", String(index), "-r", root.queueFor]
    queueEditProc.running = true
    root.closeQueue()
    root.backToRooms()
  }

  function queueEdit(args) {
    if (queueEditProc.running) return
    queueEditProc.command = [root.command, "queue"].concat(args).concat(["-r", root.queueFor])
    queueEditProc.running = true
  }

  /// A browse row's second line: its kind, and whatever the service offered as
  /// a description. Not the service name - the title bar already says it.
  ///
  /// **A container shows no kind at all.** The `\u203a` at the end of the row
  /// already says "somewhere to go", and the word underneath would be the
  /// service's own jargon rather than anything a person wants: TuneIn types
  /// every one of its featured sections `container`, so its root read
  /// "iHeartRadio / container", and iHeartRadio types one of its own
  /// `favorites`. Both are implementation words that leaked to the surface.
  /// A *playable* row keeps its kind, because "stream" or "album" is a real
  /// answer to what pressing it will do.
  function browseSubtitle(item) {
    var parts = []
    if (item.type && !item.container) {
      var raw = String(item.type)
      var key = "kind" + raw.charAt(0).toUpperCase() + raw.slice(1).toLowerCase()
      parts.push(root.strings[key] || raw.toLowerCase())
    }
    if (item.description) parts.push(String(item.description))
    return parts.join(" · ")
  }

  function favoriteSubtitle(favorite) {
    var parts = []
    if (favorite.type) {
      var raw = String(favorite.type)
      var key = "kind" + raw.charAt(0).toUpperCase() + raw.slice(1).toLowerCase()
      // A kind nobody has named still reads as itself rather than vanishing.
      parts.push(root.strings[key] || raw.toLowerCase())
    }
    // Service names are brands; they stay as the service spells them.
    if (favorite.service) parts.push(favorite.service)
    return parts.join(" · ")
  }

  // Every glyph the widget draws, and the sizes and lines that can be turned
  // off, all overridable from this widget's shell.json entry.
  //
  // This matters more than it looks: the plugin is installed by copying over
  // the previous one, so editing this file is a customization that does not
  // survive the next update. shell.json does survive, which is where a
  // customized look belongs. See README.md in this directory for every key.
  readonly property var defaultGlyphs: ({
    "speaker": "󰓃",
    "play": "󰐊",
    "pause": "󰏤",
    "previous": "󰒮",
    "next": "󰒭",
    "repeat": "󰑖",
    "repeatOne": "󰑘",
    "shuffle": "󰒝",
    // The button that opens the picker. Named `music` rather than `favorites`
    // because the picker stopped being only favorites: it is the household's
    // favorites, this machine's kept items, a service's own containers and a
    // search, and a person pressing it is asking for music rather than for a
    // list. `glyphs.favorites` still works - it is a documented setting and
    // breaking it to rename a key would be a poor trade.
    //
    // nf-md-music (U+F075A): two beamed quavers, from the same Material Design
    // set as every other glyph here. Plain `♪` (U+266A) was tried first, to
    // avoid depending on a patched font - but the dependency was already there,
    // since sixteen of the seventeen glyphs below are Nerd Font icons and the
    // widget draws boxes without one. Avoiding it for this one button bought
    // nothing and cost a per-character font fallback, because JetBrainsMono
    // Nerd Font has no U+266A: the note came from Adwaita or Liberation
    // instead, at a different weight from its neighbours.
    //
    // `♪` remains the right answer for a bar whose font is *not* patched, which
    // is what `glyphs.music` is for.
    "music": "󰝚",
    "party": "◉",
    "group": "󰌷",
    "ungroup": "󰌸",
    "tv": "󰠹",
    "queue": "󰲹",
    // nf-md-radio_tower (U+F043B), beside the name of anything the player is
    // resolving continuously rather than as an item. The tower rather than a
    // radio set: what it marks is a broadcast, not the receiver.
    "radio": "󰐻",
    // nf-md-stop (U+F04DB). Stands in for `pause` on a source that refuses to
    // be paused - see `stopRather` for which ones do and why it is not a
    // second button.
    "stop": "󰓛",
    // A microphone (nf-md-microphone, U+F036C) rather than the podcast icon
    // proper (nf-fa-podcast, U+F2CE), for two reasons. The podcast icon is
    // concentric waves and reads almost identically to `radio` at caption
    // size, and the two mark rows that sit beside each other in one list.
    // It is also Font Awesome where every other glyph here is Material
    // Design, which is the weight mismatch the `music` note below describes.
    "podcast": "󰍬",
    // An open book (nf-md-book_open_variant, U+F05DA) rather than headphones
    // (U+F02CB), which was the other legible candidate. The marks say what a
    // row *is*, not what plays it, and headphones beside the `speaker` glyph
    // already in this set would read as a device rather than a kind.
    "audiobook": "󰗚",
    // The picker's add-to-queue affordance. A plain "+" rather than a Nerd Font
    // icon: it is the one mark here that has to read as a *verb*, and every
    // font draws it.
    "add": "+",
    "remove": "󰅖",
    "moveUp": "󰅃",
    "moveDown": "󰅀"
  })

  // Each key falls back on its own, so overriding one glyph does not mean
  // restating the other eleven.
  readonly property var glyphs: {
    var merged = {}
    for (var name in defaultGlyphs) merged[name] = defaultGlyphs[name]
    var chosen = setting("glyphs", null)
    if (chosen)
      for (var key in chosen)
        if (typeof chosen[key] === "string" && chosen[key].length > 0)
          merged[key] = chosen[key]
    // The old name for `music`, honoured after the merge so that a shell.json
    // written before the rename still gets the glyph it asked for.
    if (chosen && typeof chosen["favorites"] === "string" && chosen["favorites"].length > 0)
      merged["music"] = chosen["favorites"]
    return merged
  }

  // Cover tile size, in the same units as the rest of the widget's spacing.
  // The picker's tiles sit a little smaller, keeping their proportion to it.
  readonly property int artSize: Math.max(12, Number(setting("artSize", 38)) || 38)
  readonly property int pickerArtSize: Math.max(12, artSize - 4)

  // The x2rock binary. A name is looked up on PATH; give an absolute path for
  // an install that is not on the shell's PATH, which is not the same PATH an
  // interactive terminal has.
  readonly property string command: {
    var given = setting("command", "")
    return (typeof given === "string" && given.length > 0) ? given : "x2rock"
  }

  // Every word the widget shows, overridable from shell.json like the glyphs.
  //
  // Not i18n proper: Qt's own machinery wants a translator installed at
  // startup, which Quickshell does not do and Omarchy has no catalogues for -
  // its own shell has no qsTr at all, so a translated widget would sit in a bar
  // where every other widget is still English. These let a household do the
  // words itself, which also serves anyone who just wants them shorter.
  readonly property var defaultStrings: ({
    "playing": "playing",
    "paused": "paused",
    "loading": "Loading…",
    "filterHint": "Type to filter",
    "noMatch": "No match",
    "noFavorites": "Nothing saved yet",
    "favoritesError": "Could not read favorites",
    // Searching a music service. %1 is the service's name, so a household that
    // points `searchService` somewhere else gets sentences that still read.
    "searchFor": "Search %1",
    "searching": "Searching…",
    // The + button'''s tooltip. A verb, because the glyph alone does not say
    // whether it adds here or plays next.
    "addToQueue": "Add to queue",
    "searchError": "Could not reach %1",
    "noResults": "Nothing found",
    // Walking a service's own containers. %1 is a service name in `browseIn`
    // and the place one level up in `up` - the parent container's name, or the
    // service's own at the top of the tree.
    "browseIn": "Browse %1",
    "up": "← %1",
    "browseLoading": "Opening…",
    "browseError": "Could not open that",
    "browseEmpty": "Nothing here",
    "nothingQueued": "Nothing queued",
    "queueError": "Could not read the queue",
    "playingTogether": "Playing together",
    "playTogetherWith": "Play together with",
    "addAnother": "Add another",
    "everyRoomGrouped": "Every room is in this group.",
    "leave": "leave",
    "join": "join",
    // A fragment, in "12 of 70". Word order is the price of not building
    // real message templates for one phrase.
    "of": "of",
    // Sonos labels a favorite's content in English of its own - STREAM, ALBUM,
    // TRACK, PROGRAM, PLAYLIST - and that word is shown under the name. Without
    // these it would be the one English left in an otherwise translated widget.
    "kindStream": "stream",
    "kindAlbum": "album",
    "kindTrack": "track",
    "kindProgram": "program",
    "kindPlaylist": "playlist",
    // The switch tooltips, in both states: what the glyph does, or - once it
    // is lit - what it is already doing. Blank any of them to turn that
    // tooltip off entirely.
    "tooltipTv": "TV Input",
    "tooltipTvOn": "TV Input (current source)",
    "tooltipParty": "Party",
    "tooltipPartyOn": "Party (on)",
    "tooltipGroup": "Group",
    // %1 is the size of the group the room is already in. A placeholder
    // rather than a fragment because this is the one phrase here where a
    // number sits mid-sentence, and languages disagree about where.
    "tooltipGroupOf": "Group (%1 rooms)"
  })

  readonly property var strings: {
    var merged = {}
    for (var name in defaultStrings) merged[name] = defaultStrings[name]
    var chosen = setting("strings", null)
    if (chosen)
      for (var key in chosen)
        if (typeof chosen[key] === "string")
          merged[key] = chosen[key]
    return merged
  }

  // Panel widths, because density is the thing a themed desktop is actually
  // about and a 340px list is a guess about someone else's screen. Both are
  // still clamped to what the screen allows.
  readonly property int popupWidth: Math.max(160, Number(setting("popupWidth", 340)) || 340)
  readonly property int panelWidth: Math.max(160, Number(setting("panelWidth", 380)) || 380)

  /// How strongly a row lights up under the cursor. One value, so the popup,
  /// the pickers and the grouping panel cannot drift apart from each other.
  /// Defaults to the shell's own hover strength rather than a number of this
  /// widget's choosing, so rows here light up like rows everywhere else.
  readonly property real highlight: {
    var given = Number(setting("highlight", Style.hoverFillAlpha))
    return isNaN(given) ? Style.hoverFillAlpha : Math.max(0, Math.min(1, given))
  }

  // The theme's own cursor colour at whatever strength the household asked
  // for. Derived from the bar's foreground *and* the theme accent, the way
  // every first-party row is: a fill mixed from the foreground alone ignored
  // the one colour a themed desktop uses to say "here".
  readonly property color highlightFill: bar
    ? Util.alpha(Style.hoverStateColor(bar.foreground, Color.accent), highlight)
    : "transparent"

  /// What marks the row that already is the thing - the playing track in a
  /// queue. Left at the shell's own strength: this says "this one", which is
  /// not the same claim as the cursor and does not follow it to zero.
  readonly property color selectedFill: bar
    ? Style.selectedFillFor(bar.foreground, Color.accent)
    : "transparent"

  readonly property bool showState: setting("showState", true) !== false
  readonly property bool showMembers: setting("showMembers", true) !== false

  // Cover art in the popup and the picker, off in `shell.json` for anyone whose
  // bar is themed tightly enough that album covers are an intrusion. Never on
  // the pill itself, which is always on screen - see CoverArt.qml.
  readonly property bool showArt: setting("art", true) !== false

  // Which service the picker searches, and how many hits to ask for. Only
  // services with anonymous access can be searched at all - the CLI says so
  // plainly if this names one that cannot. Set it to "" to leave the picker
  // exactly as it was, with no network call behind it.
  readonly property string searchService: String(setting("searchService", "TuneIn") || "")
  readonly property bool searchEnabled: searchService !== ""
  readonly property int searchCount: Math.max(1, Number(setting("searchCount", 20)) || 20)
  // Which of the service's categories the search row queries, passed to the
  // CLI as `-c`. Empty means the CLI's default (the service's "all" when it
  // has one, else its first category). Worth setting for a library-shaped
  // service: "tracks" is what a song title typed into a picker means on Plex.
  readonly property string searchCategory: String(setting("searchCategory", "") || "")

  // Which services the picker offers to walk. A service's own containers - a
  // personal library, a "For You", a genre tree - are the half of a linked
  // account no search term can name. Unset, the list is discovered: a row for
  // `searchService`, then one per account this machine has linked, because
  // `x2rock link` already named the services that matter and naming them a
  // second time here configures nothing. The 30-odd anonymous services stay
  // out of the discovered default on purpose - nobody chose them, and a picker
  // that lists a catalogue answers a different question from "what should this
  // room play". Naming `browseServices` by hand still wins verbatim, which is
  // how one of those anonymous services gets a row - and `[]` still turns
  // browsing off.
  readonly property var browseServices: {
    var given = setting("browseServices", null)
    if (Array.isArray(given)) {
      var names = []
      for (var i = 0; i < given.length; i++)
        if (typeof given[i] === "string" && given[i] !== "") names.push(given[i])
      return names
    }
    var out = root.searchService !== "" ? [root.searchService] : []
    for (var j = 0; j < root.linkedServices.length; j++) {
      var linked = root.linkedServices[j]
      var seen = false
      for (var k = 0; k < out.length; k++)
        if (out[k].toLowerCase() === linked.toLowerCase()) { seen = true; break }
      if (!seen) out.push(linked)
    }
    return out
  }
  readonly property int browseCount: Math.max(1, Number(setting("browseCount", 100)) || 100)

  // The three steps down from the bar foreground, named once: a control the
  // source does not allow, one it allows but that is off, and secondary text.
  // Bindings that mix these with per-room state re-run often; the darkening
  // itself only depends on the theme, so compute it here instead. Guarded
  // because the host injects `bar` after construction - the base class takes
  // the same care with its own `vertical` and `barSize`.
  readonly property color disabledFg: bar ? Qt.darker(bar.foreground, 2.0) : "transparent"
  readonly property color offFg: bar ? Qt.darker(bar.foreground, 1.6) : "transparent"
  readonly property color secondaryFg: bar ? Qt.darker(bar.foreground, 1.35) : "transparent"

  visible: rooms.length > 0
  implicitWidth: rooms.length > 0 ? glyph.implicitWidth + Style.space(14) : 0
  implicitHeight: barSize

  // Scroll ticks accumulate and fire once, so a flick is one relative volume
  // command rather than ten processes; the player coalesces changes anyway.
  property int pendingVolumeDelta: 0

  Timer {
    id: volumeTimer
    interval: 150
    onTriggered: {
      if (root.pendingVolumeDelta === 0 || !root.focused) return
      var delta = Math.max(-100, Math.min(100, root.pendingVolumeDelta))
      var sign = delta > 0 ? "+" : ""
      root.bar.run(Util.shellQuote(root.command) + " vol " + sign + delta
                   + " -r " + Util.shellQuote(root.focused.identity))
      root.pendingVolumeDelta = 0
    }
  }

  function nudgeVolume(player, ticks) {
    if (!player) return
    root.focusedName = player.identity
    root.pendingVolumeDelta += ticks * 2
    volumeTimer.restart()
  }

  // What a room's controls actually do, named once here rather than inside the
  // buttons, because the popup's key map has to reach the same decisions - and
  // a second copy of "which repeat states does this source allow" is a second
  // thing to get wrong. Each one takes the room it acts on and makes it the
  // focused one, which is what the pill and the scroll gesture follow.
  /// Whether this room's transport button should read "stop" rather than
  /// "pause" - which is the player's own answer, not a guess about the source.
  ///
  /// A live stream reports `canPause: false` and `canStop: true`, and MPRIS
  /// carries the first through as `CanPause`. Quickshell gates
  /// `canTogglePlaying` on it, so the pause button was inert on a station: it
  /// looked like a working control and did nothing, which is worse than not
  /// offering one.
  ///
  /// Only while playing. Stopped, the same button is `play` and MPRIS allows
  /// that - `CanPlay` stays true on a station, which is how it starts again.
  function stopRather(player) {
    return !!(player && player.isPlaying && !player.canPause)
  }

  function togglePlay(player) {
    if (!player) return
    root.focusedName = player.identity
    // Stop is a different MPRIS verb from pause and is gated on CanControl
    // rather than CanPause, which is exactly why it works here. It maps to the
    // player's own `pause`, which does stop a stream - the refusal was never
    // the command, only the capability flag in front of it.
    if (root.stopRather(player)) player.stop()
    else if (player.canTogglePlaying) player.togglePlaying()
  }

  function skip(player, forward) {
    if (!player || !(forward ? player.canGoNext : player.canGoPrevious)) return
    root.focusedName = player.identity
    if (forward) player.next()
    else player.previous()
  }

  // MPRIS has no CanLoop, so what the current source allows arrives as
  // x2rock:* metadata; a radio stream allows neither and the control dims.
  function repeatAvailable(player) {
    if (!player || !player.loopSupported) return false
    return player.metadata["x2rock:canRepeat"] === true
      || player.metadata["x2rock:canRepeatOne"] === true
  }

  // Off -> all -> one -> off, the way Sonos, MPRIS LoopStatus and the Sonos
  // app all model it, skipping whichever states this source cannot do.
  function cycleRepeat(player) {
    if (!repeatAvailable(player)) return
    root.focusedName = player.identity
    var now = player.loopState
    if (now === MprisLoopState.None)
      player.loopState = player.metadata["x2rock:canRepeat"] === true
        ? MprisLoopState.Playlist : MprisLoopState.Track
    else if (now === MprisLoopState.Playlist
        && player.metadata["x2rock:canRepeatOne"] === true)
      player.loopState = MprisLoopState.Track
    else
      player.loopState = MprisLoopState.None
  }

  function shuffleAvailable(player) {
    return !!player && player.shuffleSupported
      && player.metadata["x2rock:canShuffle"] === true
  }

  function toggleShuffle(player) {
    if (!shuffleAvailable(player)) return
    root.focusedName = player.identity
    player.shuffle = !player.shuffle
  }

  // Move the focused room by one. Clamped rather than wrapping: the list is
  // short enough that running off the end reads as a mistake, not a loop.
  function selectRoomBy(step) {
    if (root.rooms.length === 0) return
    var at = 0
    for (var i = 0; i < root.rooms.length; i++)
      if (root.rooms[i] === root.focused) at = i
    var next = Math.max(0, Math.min(root.rooms.length - 1, at + step))
    root.focusedName = root.rooms[next].identity
  }

  // The pill is the speaker glyph, lit when the focused room is playing. Which
  // room that is belongs to the popup, where it is said once per room with the
  // controls that act on it; on the bar it was a lone word that changed under
  // you as focus moved. Hovering still names it, and the track, in the tooltip.
  Text {
    id: glyph
    anchors.centerIn: parent
    text: root.glyphs.speaker
    color: root.focused && root.focused.isPlaying
      ? root.bar.barForeground
      : Qt.darker(root.bar.barForeground, 1.5)
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.body
  }

  MouseArea {
    id: pillArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton

    onClicked: function(mouse) {
      if (mouse.button === Qt.MiddleButton) {
        root.togglePlay(root.focused)
      } else {
        root.popupOpen = !root.popupOpen
      }
    }

    onWheel: function(wheel) {
      root.nudgeVolume(root.focused, wheel.angleDelta.y > 0 ? 1 : -1)
    }

    onEntered: {
      if (!root.bar || !root.focused) return
      var line = root.focused.identity
      if (root.focused.trackTitle)
        line += ": "
          + (root.isLiveStream(root.focused) ? root.glyphs.radio + " " : "")
          + root.focused.trackTitle
          + (root.focused.trackArtist ? " — " + root.focused.trackArtist : "")
      root.bar.showTooltip(root, line)
    }
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  // A KeyboardPanel, not a PopupCard: a PopupCard takes a focus grab for
  // click-away dismissal and never keyboard focus, and Omarchy is a desktop
  // meant to be drivable without a mouse. Nothing else about the swap is
  // interesting - KeyboardPanel's API is a subset of PopupCard's, and this
  // card used none of the parts left out.
  KeyboardPanel {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    // Qt needs a focused item inside the surface before a key handler runs.
    focusTarget: roomKeys
    contentWidth: popup.fittedContentWidth(Style.space(root.popupWidth))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Item {
      anchors.fill: parent

      // One key per control on the selected room, rather than a cursor walking
      // a row of ten: the fourth room's queue is three downs and a q. The
      // selected room is the focused one - the room whose name is bold, which
      // the pill and the scroll gesture already follow - so the keyboard moves
      // the same cursor the mouse does. Not PanelKeyCatcher: it claims h/j/k/l
      // and x, and here the letters are the controls.
      FocusScope {
        id: roomKeys
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
          var player = root.focused
          if (event.key === Qt.Key_Escape) {
            root.close()
          } else if (event.key === Qt.Key_Down) {
            root.selectRoomBy(1)
          } else if (event.key === Qt.Key_Up) {
            root.selectRoomBy(-1)
          } else if (event.key === Qt.Key_Right) {
            root.nudgeVolume(player, 1)
          } else if (event.key === Qt.Key_Left) {
            root.nudgeVolume(player, -1)
          } else if (event.key === Qt.Key_Space) {
            root.togglePlay(player)
          } else if (event.key === Qt.Key_N) {
            root.skip(player, true)
          } else if (event.key === Qt.Key_P) {
            root.skip(player, false)
          } else if (event.key === Qt.Key_R) {
            root.cycleRepeat(player)
          } else if (event.key === Qt.Key_S) {
            root.toggleShuffle(player)
          } else if (event.key === Qt.Key_F) {
            if (player) root.openPicker(player.identity)
          } else if (event.key === Qt.Key_Q) {
            if (player) root.openQueue(player.identity)
          } else if (event.key === Qt.Key_G) {
            // The keys are only offered where the glyphs are: no grouping or
            // party in a one-speaker household, no TV on a speaker without one.
            if (player && root.totalRooms > 1) root.openGrouping(player.identity)
          } else if (event.key === Qt.Key_Y) {
            if (player && root.totalRooms > 1) root.toggleParty(player.identity)
          } else if (event.key === Qt.Key_T) {
            if (root.hasTvInput(player)) root.switchToTv(player.identity)
          } else {
            return
          }
          event.accepted = true
        }
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        Repeater {
          model: root.rooms

          Column {
            id: roomRow
            required property var modelData
            readonly property var player: modelData

            width: column.width
            spacing: Style.space(4)

            // Art beside the room's text; the controls below keep the full width.
            Row {
              width: parent.width
              spacing: Style.space(8)

              CoverArt {
                id: roomArt
                visible: root.showArt
                width: visible ? size : 0
                size: Style.space(root.artSize)
                url: roomRow.player.trackArtUrl || ""
                // TV audio carries no artwork, and a speaker glyph for it says
                // the wrong thing - what is playing is the television.
                placeholder: root.onTvInput(roomRow.player)
                  ? root.glyphs.tv : root.glyphs.speaker
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
              }

              Column {
                width: parent.width
                  - (roomArt.visible ? roomArt.width + parent.spacing : 0)
                  - (switches.width > 0 ? switches.width + parent.spacing : 0)
                spacing: Style.space(2)

                MouseArea {
                  width: parent.width
                  height: header.implicitHeight
                  hoverEnabled: true
                  onWheel: function(wheel) {
                    root.nudgeVolume(roomRow.player, wheel.angleDelta.y > 0 ? 1 : -1)
                  }
                  onClicked: root.focusedName = roomRow.player.identity

                  Row {
                    id: header
                    width: parent.width
                    spacing: Style.space(8)

                    Text {
                      text: roomRow.player.identity || "?"
                      color: root.bar.foreground
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: root.focused === roomRow.player
                    }

                    Text {
                      visible: root.showState
                      text: roomRow.player.isPlaying ? root.strings.playing : root.strings.paused
                      color: root.offFg
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.caption
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }
                }

                // What the TV is actually sending. The one line here worth
                // reading at a glance rather than on purpose: a source that has
                // dropped to stereo says so nowhere else.
                Text {
                  width: parent.width
                  visible: text !== ""
                  text: root.inputFormatOf(roomRow.player)
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  visible: root.showMembers && text !== ""
                  text: {
                    var members = root.membersOf(roomRow.player)
                    return members.length > 1 ? members.join(" + ") : ""
                  }
                  color: root.offFg
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }

                // A live stream is marked rather than described. The name of a
                // station reads exactly like the name of a track - "Jazz Club"
                // says nothing about whether it ends - and the difference is
                // what decides whether seeking or a queue position mean
                // anything. The glyph carries it in the width a glyph costs.
                Row {
                  width: parent.width
                  spacing: nowMark.visible ? Style.space(4) : 0
                  visible: nowText.text !== ""

                  Text {
                    id: nowMark
                    visible: root.isLiveStream(roomRow.player)
                    // A hidden Item still reports its implicit width, and Row
                    // lays out only what is visible - so the title's width has
                    // to ask whether the mark is there, not just how wide it is.
                    width: visible ? implicitWidth : 0
                    text: root.glyphs.radio
                    color: root.secondaryFg
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter

                    // The station, on the one thing that is always there to
                    // point at. The line below carries it when there is room,
                    // but it elides on a narrow panel and is absent when the
                    // title already is the station - and the mark is neither.
                    MouseArea {
                      anchors.fill: parent
                      anchors.margins: -Style.space(2)
                      hoverEnabled: true
                      onEntered: {
                        if (!root.bar) return
                        // Falls back to the title, which on a service with no
                        // track *is* the station. Never an empty tooltip.
                        var name = root.stationOf(roomRow.player)
                          || String(roomRow.player.trackTitle || "")
                        if (name !== "") root.bar.showTooltip(nowMark, name)
                      }
                      onExited: if (root.bar) root.bar.hideTooltip(nowMark)
                    }
                  }

                  Text {
                    id: nowText
                    // Whatever the mark did not take, so a long title elides at
                    // the row's edge rather than past it. Computed from the
                    // mark rather than from this item's own `x`: inside a Row
                    // the layout assigns `x`, and a width that reads it is a
                    // binding loop waiting for a second glyph to be added.
                    width: parent.width - nowMark.width - parent.spacing
                    // Station name when there is no title at all: without the
                    // fallback the whole line hides, and the mark goes with it,
                    // so a playing stream would show nothing rather than less.
                    text: roomRow.player.trackTitle
                      ? roomRow.player.trackTitle
                        + (roomRow.player.trackArtist ? " — " + roomRow.player.trackArtist : "")
                      : root.stationOf(roomRow.player)
                    color: root.secondaryFg
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                // Only where the title is the track and the station would
                // otherwise go unsaid, which the daemon has already decided -
                // it sends nothing when the name above is already the station.
                Text {
                  width: parent.width
                  visible: text !== ""
                  text: root.stationOf(roomRow.player)
                  color: root.offFg
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              // The room's three switches - TV input, party mode and grouping -
              // in a cell of their own beside the text: they change what the
              // whole room is doing, which is not what the transport row below
              // is for.
              Row {
                id: switches
                spacing: Style.space(6)
                // Top, not centre: level with the room name is what "beside the
                // text" means on a card whose text can be four lines deep.
                // Centred, these drifted down towards the transport row and read
                // as belonging to it.
                anchors.top: parent.top

                // The room's own source sits left of the pair that reach beyond
                // it: changing what this room plays is not the same errand as
                // deciding which rooms play along.
                Text {
                  visible: root.hasTvInput(roomRow.player)
                  text: root.glyphs.tv
                  // Lit while it is the source, dim while it is merely available.
                  color: root.onTvInput(roomRow.player)
                    ? root.bar.foreground : root.offFg
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.body

                  MouseArea {
                    id: tvMouse
                    anchors.fill: parent
                    anchors.margins: -Style.space(4)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.switchToTv(roomRow.player.identity)
                  }

                  PanelToolTip {
                    visible: tvMouse.containsMouse && text !== ""
                    text: root.onTvInput(roomRow.player)
                      ? root.strings.tooltipTvOn : root.strings.tooltipTv
                    fontFamily: root.bar.fontFamily
                  }
                }

                Column {
                  spacing: Style.space(2)

                  // Nothing to party with in a one-speaker household.
                  Text {
                    id: partyButton
                    visible: root.totalRooms > 1
                    text: root.glyphs.party
                    color: root.partying ? root.bar.foreground : root.offFg
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    anchors.horizontalCenter: parent.horizontalCenter

                    MouseArea {
                      id: partyMouse
                      anchors.fill: parent
                      anchors.margins: -Style.space(4)
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.toggleParty(roomRow.player.identity)
                    }

                    PanelToolTip {
                      visible: partyMouse.containsMouse && text !== ""
                      text: root.partying
                        ? root.strings.tooltipPartyOn : root.strings.tooltipParty
                      fontFamily: root.bar.fontFamily
                    }
                  }

                  // Grouping belongs beside party, not beside the volume slider:
                  // one builds a group a room at a time, the other builds the
                  // whole-house one, and they are the same decision at two sizes.
                  Text {
                    // Only worth offering when there is another room to group with.
                    visible: root.totalRooms > 1
                    text: root.glyphs.group
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    anchors.horizontalCenter: parent.horizontalCenter

                    MouseArea {
                      id: groupMouse
                      anchors.fill: parent
                      anchors.margins: -Style.space(4)
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.openGrouping(roomRow.player.identity)
                    }

                    PanelToolTip {
                      visible: groupMouse.containsMouse && text !== ""
                      // A grouped room says how big the group it is already in
                      // is; an ungrouped one has nothing to report.
                      text: {
                        var members = root.membersOf(roomRow.player)
                        return members.length > 1
                          ? root.strings.tooltipGroupOf.arg(members.length)
                          : root.strings.tooltipGroup
                      }
                      fontFamily: root.bar.fontFamily
                    }
                  }
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(10)

              Text {
                text: root.glyphs.previous
                color: roomRow.player.canGoPrevious
                  ? root.bar.foreground : root.disabledFg
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  cursorShape: roomRow.player.canGoPrevious ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: root.skip(roomRow.player, false)
                }
              }

              Text {
                text: root.stopRather(roomRow.player)
                  ? root.glyphs.stop
                  : (roomRow.player.isPlaying ? root.glyphs.pause : root.glyphs.play)
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.togglePlay(roomRow.player)
                }
              }

              Text {
                text: root.glyphs.next
                color: roomRow.player.canGoNext
                  ? root.bar.foreground : root.disabledFg
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  cursorShape: roomRow.player.canGoNext ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: root.skip(roomRow.player, true)
                }
              }

              // A radio stream dims this the way an unskippable one dims next:
              // see root.repeatAvailable for what the source is allowed to do.
              Text {
                id: repeatButton
                readonly property bool available: root.repeatAvailable(roomRow.player)

                text: roomRow.player.loopState === MprisLoopState.Track ? root.glyphs.repeatOne : root.glyphs.repeat
                color: !available ? root.disabledFg
                  : roomRow.player.loopState !== MprisLoopState.None
                    ? root.bar.foreground : root.offFg
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  cursorShape: repeatButton.available ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: root.cycleRepeat(roomRow.player)
                }
              }

              Text {
                id: shuffleButton
                readonly property bool available: root.shuffleAvailable(roomRow.player)

                text: root.glyphs.shuffle
                color: !available ? root.disabledFg
                  : roomRow.player.shuffle ? root.bar.foreground : root.offFg
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  cursorShape: shuffleButton.available ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: root.toggleShuffle(roomRow.player)
                }
              }

              // Content, rather than transport: pick something for this room to
              // play. The room is whichever row the note was on, so choosing
              // never involves choosing a room as well.
              Text {
                text: root.glyphs.music
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openPicker(roomRow.player.identity)
                }
              }

              Text {
                text: root.glyphs.queue
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openQueue(roomRow.player.identity)
                }
              }

              PanelSlider {
                id: volumeSlider
                bar: root.bar
                // The buttons to the left take what they need first; the slider
                // gets the rest, but never so little that it cannot be dragged.
                width: Math.max(Style.space(48),
                                parent.width - x - volumeLabel.width - Style.space(20))
                anchors.verticalCenter: parent.verticalCenter
                minimum: 0
                maximum: 1
                step: 0.01
                value: roomRow.player.volumeSupported ? roomRow.player.volume : 0
                // A slider has a known position, so absolute volume is the right
                // semantic (Sonos's own guidance); set only on release so a drag
                // is one command, not a stream of them.
                onReleased: function(v) {
                  root.focusedName = roomRow.player.identity
                  roomRow.player.volume = v
                }
              }

              Text {
                id: volumeLabel
                text: Math.round((volumeSlider.dragging
                  ? volumeSlider.liveValue
                  : (roomRow.player.volumeSupported ? roomRow.player.volume : 0)) * 100)
                color: root.secondaryFg
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }
        }
      }
    }
  }

  // Its own surface with its own owner, not part of the rooms popup: both
  // dismiss by calling owner.close(), so one owner would have each closing the
  // other. Only ever one of them is open - openPicker closes the popup first.
  KeyboardPanel {
    id: pickerPanel
    anchorItem: root
    bar: root.bar
    owner: pickerOwner
    open: root.pickingFor !== ""
    // Qt needs a focused item inside the surface before any key handler runs.
    focusTarget: filterField
    contentWidth: pickerPanel.fittedContentWidth(Style.space(root.panelWidth))
    contentHeight: pickerPanel.fittedContentHeight(Style.space(440))

    Item {
      anchors.fill: parent

      Text {
        id: pickerTitle
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: pickerCount.left
        anchors.rightMargin: Style.space(6)
        elide: Text.ElideMiddle
        // The room is whose picker this is and never leaves; the container is
        // where in a service one currently stands. Eliding in the middle keeps
        // both ends readable, which is what matters when the two are "Media
        // Room" and a long station name.
        text: root.browsing ? root.pickingFor + "  ·  " + root.browseFrame.title
                            : root.pickingFor
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        id: pickerCount
        anchors.verticalCenter: pickerTitle.verticalCenter
        anchors.right: parent.right
        visible: root.favoritesLoaded || root.bookmarksLoaded
                 || root.searchStatus !== "" || root.browsing
        // The status goes here rather than over the list: a search that is
        // running, or that failed, must not take away the rows already shown.
        // The favorites status joins it whenever the list is up, so a failed
        // favorites load is still reported instead of being swallowed by the
        // rows that survived it.
        text: {
          // Inside a container, everything on screen belongs to that container,
          // so the count is about it and nothing else.
          if (root.browsing) {
            if (root.browseStatus !== "") return root.browseStatus
            var here = root.shownBrowseItems.length
            return here + (root.filterText !== ""
                           ? " " + root.strings.of + " " + root.browseItems.length : "")
          }
          if (root.searchStatus !== "") return root.searchStatus
          if (root.favoritesStatus !== "" && root.pickerRows.length > 0)
            return root.favoritesStatus
          var shown = root.shownFavorites.length + root.shownBookmarks.length
          var total = root.favorites.length + root.bookmarks.length
          return shown + (root.filterText !== "" ? " " + root.strings.of + " " + total : "")
        }
        color: root.secondaryFg
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }

      TextField {
        id: filterField
        anchors.top: pickerTitle.bottom
        anchors.topMargin: Style.space(8)
        anchors.left: parent.left
        anchors.right: parent.right
        placeholderText: root.strings.filterHint
        foreground: root.bar.foreground
        font.family: root.bar.fontFamily

        onTextChanged: {
          root.filterText = text
          // The old position means nothing once the list is a different list.
          root.selectedIndex = 0
          // A stale "could not reach" under a query nobody has run yet reads as
          // if the new text had already failed.
          if (root.searchStatus !== "" && !searchProc.running) root.searchStatus = ""
        }

        // Arrows and Enter drive the list while the text keeps arriving here.
        // PanelKeyCatcher is deliberately not used: it claims h/j/k/l/x and
        // space as navigation, which a typed name cannot survive.
        Keys.onPressed: function(event) {
          var items = root.pickerRows
          if (event.key === Qt.Key_Escape) {
            root.closePicker()
          } else if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Left)
                     && root.browsing && text === "") {
            // Only on an empty field. Both keys mean something to a text cursor,
            // and a filter someone is still editing outranks navigation.
            root.browseUp()
          } else if (event.key === Qt.Key_Down) {
            root.selectedIndex = Math.min(root.selectedIndex + 1, Math.max(0, items.length - 1))
          } else if (event.key === Qt.Key_Up) {
            root.selectedIndex = Math.max(root.selectedIndex - 1, 0)
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (items.length > 0)
              root.activateRow(items[root.selectedIndex])
          } else {
            return
          }
          event.accepted = true
        }
      }

      Text {
        id: pickerStatus
        // Only when there is genuinely nothing to show. A status must not
        // pre-empt the list: on a household with no favorites at all,
        // favoritesStatus is permanently set, and keying off it hid the search
        // row along with the empty list it was describing. Whatever the status
        // has to say is still said, in the count line, where it costs no rows.
        // Never while browsing: the back row means pickerRows is never empty
        // there, and a container's own emptiness is said in a note row instead.
        visible: !root.browsing && root.pickerRows.length === 0
                 && (root.favoritesLoaded || root.bookmarksLoaded
                     || root.favoritesStatus !== "")
        text: root.favoritesStatus !== "" ? root.favoritesStatus : root.strings.noMatch
        color: root.secondaryFg
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        anchors.top: filterField.bottom
        anchors.topMargin: Style.space(10)
        anchors.left: parent.left
      }

      ListView {
        id: favoritesList
        anchors.top: filterField.bottom
        anchors.topMargin: Style.space(8)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: !pickerStatus.visible
        clip: true
        model: root.pickerRows
        boundsBehavior: Flickable.StopAtBounds
        currentIndex: root.selectedIndex
        // Keep the keyboard selection in view when it walks off the edge.
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

        delegate: MouseArea {
          id: entry
          required property var modelData
          required property int index

          /// The row's payload, shaped the same whether it came from favorites
          /// or from a service - which is why the CLI emits both with the same
          /// field names.
          readonly property var payload: entry.modelData.item
          readonly property string kind: entry.modelData.kind
          /// A note is a sentence, not a thing to play.
          readonly property bool actionable: entry.kind !== "note"

          width: ListView.view.width
          height: Math.max(entryText.implicitHeight, root.showArt ? entryArt.size : 0)
                  + Style.space(10)
          hoverEnabled: true
          cursorShape: entry.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.activateRow(entry.modelData)
          // Hovering moves the keyboard selection too, so the two never
          // disagree about which row Enter would play.
          onEntered: root.selectedIndex = entry.index

          // CursorSurface rather than a Rectangle of our own: the shell's
          // row chrome, whose contract is that a row paints from the panel's
          // cursor rather than from its own hover state - which is what keeps
          // one highlight on screen no matter which device moved it.
          CursorSurface {
            anchors.fill: parent
            anchors.rightMargin: Style.space(2)
            hasCursor: entry.index === root.selectedIndex
            foreground: root.bar.foreground
            fill: root.highlightFill
            currentFill: root.selectedFill
          }

          // Only rows the list actually builds ask for their cover, so
          // scrolling fetches as it goes rather than all of them at once.
          CoverArt {
            id: entryArt
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.space(6)
            size: Style.space(root.pickerArtSize)
            // The action rows and the empty-result note carry no art, and a
            // placeholder speaker beside them would read as a thing to play.
            // A container often does have art - services give their own
            // sections icons - so it keeps its tile.
            visible: root.showArt && entry.kind !== "search" && entry.kind !== "note"
                     && entry.kind !== "browseService" && entry.kind !== "up"
            url: entry.payload.art_url || ""
            placeholder: root.glyphs.speaker
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          // Somewhere to go rather than something to play, said once at the
          // end of the row. The distinction is not decorative: a service can
          // mark a container playable and still refuse its id, so the widget
          // must never offer one as a track.
          Text {
            id: entryInto
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            visible: entry.kind === "container" || entry.kind === "browseService"
            text: "›"
            color: root.secondaryFg
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
          }

          // Add to the queue rather than play now, on the right where the row
          // already puts what it *does* - the chevron says "go here", this says
          // "keep this for later", and the two are mutually exclusive because a
          // container is never queueable.
          //
          // Whether it appears is the CLI's answer, not a guess from the type:
          // see `canQueue`. A row that cannot be queued simply has no button,
          // rather than one that reports a failure after the fact.
          Text {
            id: entryAdd
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            visible: entry.actionable && root.canQueue(entry.payload)
            text: root.glyphs.add
            color: addArea.containsMouse ? root.bar.foreground : root.secondaryFg
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body

            MouseArea {
              id: addArea
              anchors.fill: parent
              // Room to hit without widening the column the text lives in.
              anchors.margins: -Style.space(5)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: if (root.bar) root.bar.showTooltip(entryAdd, root.strings.addToQueue)
              onExited: if (root.bar) root.bar.hideTooltip(entryAdd)
              // The row underneath would play it. Adding is a different verb,
              // so the press must not reach it.
              onClicked: function(mouse) {
                mouse.accepted = true
                root.queueSearchResult(root.pickingFor, entry.payload)
              }
            }
          }

          // The same mark the room row gives what is playing, for a row that
          // is not playing yet. A station and an album are the same shape in
          // this list - a cover, a name, a service - and which one a row is
          // decides whether it ends, whether it can be seeked, and what
          // "play" even means. Left of the name, after the cover, so the
          // names still start on one line down the list.
          Text {
            id: entryMark
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: entryArt.visible ? entryArt.right : parent.left
            anchors.leftMargin: Style.space(6)
            // A note is a sentence, not a thing to play, so it is never a
            // station however its text reads.
            visible: entry.actionable && text !== ""
            text: root.markFor(entry.payload)
            color: root.secondaryFg
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
          }

          Column {
            id: entryText
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: entryMark.visible
              ? entryMark.right
              : (entryArt.visible ? entryArt.right : parent.left)
            anchors.right: entryInto.visible
              ? entryInto.left
              : (entryAdd.visible ? entryAdd.left : parent.right)
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(1)

            Text {
              width: parent.width
              text: entry.payload.name || ""
              // A note is not an offer, so it does not get the foreground the
              // playable rows have.
              color: entry.actionable ? root.bar.foreground : root.secondaryFg
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              visible: text !== ""
              // Inside a container the service is already in the title, so the
              // second line is the kind alone rather than "stream · iHeartRadio"
              // on every one of fifty rows.
              text: !entry.actionable ? ""
                    : root.browsing ? root.browseSubtitle(entry.payload)
                    : root.favoriteSubtitle(entry.payload)
              color: root.secondaryFg
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }

  // A surface of its own, like the favorites picker and for the same reason: a
  // bar popup takes no keyboard focus, and a queue wants arrows and Escape.
  KeyboardPanel {
    id: queuePanel
    anchorItem: root
    bar: root.bar
    owner: queueOwner
    open: root.queueFor !== ""
    focusTarget: queueKeys
    contentWidth: queuePanel.fittedContentWidth(Style.space(root.panelWidth))
    contentHeight: queuePanel.fittedContentHeight(Style.space(440))

    Item {
      anchors.fill: parent

      Text {
        id: queueTitle
        anchors.top: parent.top
        anchors.left: parent.left
        text: root.queueFor
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        anchors.verticalCenter: queueTitle.verticalCenter
        anchors.right: parent.right
        visible: root.queueTotal > 0
        text: root.queueTotal + (root.queueTotal > root.queueItems.length
          ? " (first " + root.queueItems.length + ")" : "")
        color: root.secondaryFg
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        id: queueStatusText
        visible: root.queueStatus !== ""
        text: root.queueStatus
        color: root.secondaryFg
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        anchors.top: queueTitle.bottom
        anchors.topMargin: Style.space(10)
        anchors.left: parent.left
      }

      // A cursor rather than a scroll: the rows are what you came for, and
      // Enter on one is the jump that clicking it makes. Not PanelKeyCatcher:
      // it claims h/j/k/l, which would be fine here, but its space and x are
      // not - x deletes.
      FocusScope {
        id: queueKeys
        anchors.fill: parent
        focus: true

        function step(by) {
          if (root.queueItems.length === 0) return
          root.queueIndex = Math.max(0, Math.min(root.queueItems.length - 1,
                                                 root.queueIndex + by))
          queueList.positionViewAtIndex(root.queueIndex, ListView.Contain)
        }

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.closeQueue()
          } else if (event.key === Qt.Key_Down) {
            queueKeys.step(1)
          } else if (event.key === Qt.Key_Up) {
            queueKeys.step(-1)
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            var item = root.queueItems[root.queueIndex]
            if (item) root.playTrack(item.index)
          } else {
            return
          }
          event.accepted = true
        }
      }

      ListView {
        id: queueList
        anchors.top: queueStatusText.visible ? queueStatusText.bottom : queueTitle.bottom
        anchors.topMargin: Style.space(8)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        model: root.queueItems
        boundsBehavior: Flickable.StopAtBounds

        delegate: MouseArea {
          id: track
          required property var modelData
          required property int index
          readonly property bool current: modelData.current === true
          width: ListView.view.width
          height: Math.max(trackText.implicitHeight, root.showArt ? trackArt.size : 0)
                  + Style.space(10)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          // The row itself jumps; the glyphs at the end do their own thing.
          onClicked: root.playTrack(track.modelData.index)
          onEntered: root.queueIndex = track.index

          CursorSurface {
            anchors.fill: parent
            anchors.rightMargin: Style.space(2)
            hasCursor: track.index === root.queueIndex
            // The playing track is the one the list is already about, which
            // is what `current` is for - it used to have nothing but bold.
            current: track.current
            foreground: root.bar.foreground
            fill: root.highlightFill
            currentFill: root.selectedFill
          }

          CoverArt {
            id: trackArt
            visible: root.showArt
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.space(6)
            size: Style.space(root.pickerArtSize)
            url: track.modelData.art_url || ""
            placeholder: root.glyphs.speaker
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Column {
            id: trackText
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: trackArt.visible ? trackArt.right : parent.left
            anchors.right: trackButtons.left
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)
            spacing: Style.space(1)

            Text {
              width: parent.width
              text: track.modelData.title || ""
              // The playing track is the one thing here worth weight.
              color: track.current ? root.bar.foreground : root.secondaryFg
              font.bold: track.current
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              visible: text !== ""
              text: track.modelData.artist || ""
              color: root.offFg
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Row {
            id: trackButtons
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(8)
            // Only on the row under the cursor: eighty rows of buttons would
            // be noise, and these are destructive enough to want deliberate.
            visible: track.containsMouse

            Text {
              text: root.glyphs.moveUp
              color: track.index > 0 ? root.bar.foreground : root.disabledFg
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(3)
                cursorShape: track.index > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (track.index > 0)
                  root.queueEdit(["move", String(track.modelData.index),
                                  String(track.modelData.index - 1)])
              }
            }

            Text {
              text: root.glyphs.moveDown
              color: track.index < root.queueItems.length - 1
                ? root.bar.foreground : root.disabledFg
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(3)
                cursorShape: track.index < root.queueItems.length - 1
                  ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (track.index < root.queueItems.length - 1)
                  root.queueEdit(["move", String(track.modelData.index),
                                  String(track.modelData.index + 1)])
              }
            }

            Text {
              text: root.glyphs.remove
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(3)
                cursorShape: Qt.PointingHandCursor
                onClicked: root.queueEdit(["remove", String(track.modelData.index)])
              }
            }
          }
        }
      }
    }
  }

  // Grouping, one room at a time. Its own surface like the other two pickers,
  // and for the same reason - Escape should close it.
  KeyboardPanel {
    id: groupingPanel
    anchorItem: root
    bar: root.bar
    owner: groupingOwner
    open: root.groupingFor !== ""
    focusTarget: groupingKeys
    contentWidth: groupingPanel.fittedContentWidth(Style.space(root.panelWidth))
    contentHeight: groupingPanel.fittedContentHeight(groupingColumn.implicitHeight)

    FocusScope {
      id: groupingKeys
      anchors.fill: parent
      focus: true
      // The same shape as the popup's map: a cursor over the rows, Enter for
      // whatever clicking that row does, and left/right for the level of the
      // room it is on.
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.closeGrouping()
        } else if (event.key === Qt.Key_Down) {
          root.moveGroupingIndex(1)
        } else if (event.key === Qt.Key_Up) {
          root.moveGroupingIndex(-1)
        } else if (event.key === Qt.Key_Right) {
          root.nudgeGroupingVolume(0.02)
        } else if (event.key === Qt.Key_Left) {
          root.nudgeGroupingVolume(-0.02)
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.activateGroupingRow()
        } else {
          return
        }
        event.accepted = true
      }

      Column {
        id: groupingColumn
        width: parent.width
        spacing: Style.space(8)

        Text {
          text: root.groupingFor
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        // Only when there is a group to speak of; a room on its own has
        // nothing to leave.
        Text {
          visible: root.groupingMembers.length > 1
          text: root.strings.playingTogether
          color: root.offFg
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: root.groupingShownMembers

          // Not a MouseArea: the row holds a slider, and a row-wide click
          // target would have the drag that adjusts a room's volume also
          // remove it from the group.
          Item {
            id: memberRow
            required property var modelData
            required property int index
            readonly property real level: root.groupingLevelOf(memberRow.modelData)
            readonly property bool selected: root.groupingIndex === memberRow.index
            // Hovering moves the cursor rather than lighting a second one.
            readonly property bool hovered: volumeHover.hovered || leaveArea.containsMouse
            onHoveredChanged: if (hovered) root.groupingIndex = memberRow.index
            width: groupingColumn.width
            height: memberName.implicitHeight + memberVolume.height + Style.space(12)

            // The outline this row used to draw while the leave target was
            // hovered is gone: CursorSurface paints the cursor's own border,
            // and a second one underneath it said less than the word "leave"
            // appearing at the end of the row already does.
            CursorSurface {
              anchors.fill: parent
              hasCursor: memberRow.selected
              foreground: root.bar.foreground
              fill: root.highlightFill
              currentFill: root.selectedFill
            }

            Text {
              id: memberName
              anchors.top: parent.top
              anchors.topMargin: Style.space(4)
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              text: memberRow.modelData
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              // The coordinator is the group; the others leave it.
              visible: memberRow.modelData !== root.groupingCoordinator
              anchors.verticalCenter: memberName.verticalCenter
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              // Named wherever the cursor is, because an unlabelled glyph
              // beside a room already in the group could read as "remove the
              // room" - and Enter needs to say what it is about to do.
              text: leaveArea.containsMouse || memberRow.selected
                ? root.strings.leave + "  " + root.glyphs.ungroup
                : root.glyphs.ungroup
              color: leaveArea.containsMouse ? root.bar.foreground : root.offFg
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption

              MouseArea {
                id: leaveArea
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.partRoom(memberRow.modelData)
              }
            }

            // This room's own level. The popup's slider stays the group's, so
            // the two are not the same control wearing different hats.
            PanelSlider {
              id: memberVolume
              bar: root.bar
              anchors.top: memberName.bottom
              anchors.topMargin: Style.space(4)
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              width: parent.width - Style.space(46)
              minimum: 0
              maximum: 1
              step: 0.01
              value: memberRow.level
              onReleased: function(v) { root.setRoomVolume(memberRow.modelData, v) }

              // A handler rather than PanelSlider's own `_hot`: that is
              // internal, and this does not take events away from the drag.
              HoverHandler { id: volumeHover }
            }

            Text {
              anchors.verticalCenter: memberVolume.verticalCenter
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              text: Math.round((memberVolume.dragging ? memberVolume.liveValue
                                                      : memberRow.level) * 100)
              color: root.secondaryFg
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Text {
          visible: root.groupingOthers.length > 0
          text: root.groupingMembers.length > 1 ? root.strings.addAnother : root.strings.playTogetherWith
          color: root.offFg
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: root.groupingOthers

          MouseArea {
            id: otherRow
            required property var modelData
            required property int index
            readonly property bool selected:
              root.groupingIndex === root.groupingShownMembers.length + otherRow.index
            width: groupingColumn.width
            height: otherName.implicitHeight + Style.space(8)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.joinRoom(otherRow.modelData)
            onEntered: root.groupingIndex = root.groupingShownMembers.length + otherRow.index

            CursorSurface {
              anchors.fill: parent
              hasCursor: otherRow.selected
              foreground: root.bar.foreground
              fill: root.highlightFill
              currentFill: root.selectedFill
            }

            Text {
              id: otherName
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              text: otherRow.modelData
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              visible: otherRow.selected
              text: root.strings.join + "  " + root.glyphs.group
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Text {
          visible: root.groupingOthers.length === 0 && root.groupingMembers.length > 1
          text: root.strings.everyRoomGrouped
          color: root.secondaryFg
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
