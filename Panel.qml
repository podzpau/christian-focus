import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Christian-Focus: bar label + prev/play/next buttons, and a panel (opened by
// clicking the label) with three tabs: My Songs, Playlists and Channels. All
// state lives in the `christian-focus` script next to this file.
Panel {
  id: root
  ipcTarget: "christian-focus"
  manageIpc: false

  readonly property string backend: decodeURIComponent(String(Qt.resolvedUrl("christian-focus")).replace(/^file:\/\//, ""))
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Library, loaded from `christian-focus library` at start, when the panel
  // opens and after every change.
  property var items: []
  property var playlists: []
  property var channels: []
  property bool welcomed: true
  property var songsByUrl: ({})
  property string libraryText: ""

  // Player, polled from `christian-focus state`.
  property bool playing: false
  property bool paused: false
  property string path: ""
  property string mediaTitle: ""
  property real position: 0
  property real mpvDuration: 0
  property var context: null
  property string contextText: "null"

  // The library entry being played gives the clean title and length: the tags
  // inside a free recording can be wrong, and mpv only estimates its length.
  readonly property var song: songsByUrl[path] || null
  readonly property string current: song ? song.id : youtubeId(path)
  readonly property string title: song ? song.title : mediaTitle
  readonly property real duration: song && song.duration > 0 ? song.duration : mpvDuration

  // UI state
  property string tab: "songs"
  property string openPlaylistId: ""
  property string hoveredKey: ""
  property string pendingDelete: ""
  property string statusText: ""
  property bool statusError: false
  property bool busy: false
  property bool stateAgain: false
  property bool libraryAgain: false

  // First run: the starter playlists can be unticked before the panel opens
  // for real. `dropped` holds the unticked ones.
  property var dropped: []
  readonly property var starters: playlists.filter(function(p) { return p.id.indexOf("cat-") === 0 })
  readonly property bool welcoming: !welcomed && starters.length > 0
  readonly property int keptCount: starters.filter(function(p) { return dropped.indexOf(p.id) < 0 }).length

  readonly property bool live: playing && !paused
  readonly property var openPlaylist: findById(playlists, openPlaylistId)

  function findById(list, id) {
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
    return null
  }

  function youtubeId(url) {
    var m = /[?&]v=([A-Za-z0-9_-]{11})/.exec(url)
    return m ? m[1] : ""
  }

  function shortTitle(text) {
    var full = String(text || "").trim()
    var words = full.split(/\s+/).filter(function(w) { return w !== "" && w !== "|" && w !== "-" })
    var out = words.slice(0, 3).join(" ")
    if (out.length > 22) out = out.slice(0, 22).trim()
    return out + (out.length < full.length ? "…" : "")
  }

  function clock(seconds) {
    var s = Math.max(0, Math.floor(Number(seconds) || 0))
    var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60
    var mm = h > 0 && m < 10 ? "0" + m : String(m)
    return (h > 0 ? h + ":" : "") + mm + ":" + (r < 10 ? "0" + r : r)
  }

  function totalTime(songs) {
    var t = 0
    for (var i = 0; i < songs.length; i++) t += Number(songs[i].duration) || 0
    return clock(t)
  }

  function playingFrom(kind, id) {
    return playing && context && context.kind === kind && (kind === "songs" || context.id === id)
  }

  function progress(songDuration) {
    return clock(position) + " / " + clock(duration || songDuration)
  }

  // Rows don't depend on the playing position, so they're only rebuilt when
  // the library or the playing song changes; the row shows progress itself.
  function songRows(songs, kind, id) {
    return songs.map(function(s) {
      return { key: s.id, icon: "󰝚", label: shortTitle(s.title), meta: clock(s.duration),
               duration: Number(s.duration) || 0, current: playingFrom(kind, id) && current === s.id, opens: false }
    })
  }

  // Rows for whatever the panel is showing right now.
  readonly property var rows: {
    if (tab === "songs") return songRows(items, "songs", "")
    if (tab === "playlists" && openPlaylist) return songRows(openPlaylist.items || [], "playlist", openPlaylist.id)
    if (tab === "playlists") return playlists.map(function(p) {
      var n = (p.items || []).length
      return { key: p.id, icon: p.source ? "󰗃" : "󰲸", label: p.name,
               meta: n + (n === 1 ? " song" : " songs") + (n ? " · " + totalTime(p.items) : ""),
               duration: 0, current: playingFrom("playlist", p.id), opens: true }
    })
    return channels.map(function(c) {
      return { key: c.id, icon: "󰗃", label: c.name, meta: "shuffle", duration: 0,
               current: playingFrom("channel", c.id), opens: false }
    })
  }

  readonly property string listHeader: {
    if (tab === "songs") return "MY SONGS (" + items.length + ")"
    if (tab === "playlists" && openPlaylist) return "SONGS (" + (openPlaylist.items || []).length + ")"
    if (tab === "playlists") return "PLAYLISTS (" + playlists.length + ")"
    return "CHANNELS (" + channels.length + ")"
  }

  readonly property string emptyText: {
    if (tab === "songs") return playlists.length
      ? "No songs yet. Paste a YouTube link above, or play a starter playlist under Playlists."
      : "No songs yet. Paste a YouTube link above."
    if (tab === "playlists" && openPlaylist) return "Empty playlist. Paste a song link above."
    if (tab === "playlists") return "No playlists yet."
    return "No channels yet."
  }

  readonly property string placeholder: {
    if (tab === "songs") return "Paste a YouTube song link…"
    if (tab === "playlists" && openPlaylist) return "Paste a song or playlist link to add…"
    if (tab === "playlists") return "Paste a YouTube playlist, or type a name…"
    return "Paste a YouTube channel link…"
  }

  // Rows go through a ListModel updated in place, so a refresh doesn't
  // rebuild the delegates under the pointer.
  ListModel { id: rowModel }
  onRowsChanged: {
    var r = rows
    var same = rowModel.count === r.length
    for (var i = 0; same && i < r.length; i++) same = rowModel.get(i).key === r[i].key
    if (!same) {
      rowModel.clear()
      for (var j = 0; j < r.length; j++) rowModel.append(r[j])
    } else {
      for (var k = 0; k < r.length; k++) rowModel.set(k, r[k])
    }
  }

  // A request made while the same process runs is queued, so a click right
  // after a poll still gets a fresh answer.
  function refresh() {
    if (stateProc.running) stateAgain = true
    else stateProc.running = true
  }

  function loadLibrary() {
    if (libraryProc.running) libraryAgain = true
    else libraryProc.running = true
  }

  function applyState(raw) {
    var s
    try { s = JSON.parse(raw) } catch (e) { return }
    var p = {}, alive = false
    var replies = s.replies || []
    for (var i = 0; i < replies.length; i++) {
      if (!replies[i] || !replies[i].request_id) continue
      p[replies[i].request_id] = replies[i].data
      alive = true
    }
    playing = alive
    paused = !!p[1]
    path = p[2] || ""
    position = Number(p[3]) || 0
    mpvDuration = Number(p[4]) || 0
    mediaTitle = p[5] || ""
    var ctx = alive ? JSON.stringify(s.ctx || null) : "null"
    if (ctx !== contextText) {
      contextText = ctx
      context = JSON.parse(ctx)
    }
  }

  function applyLibrary(raw) {
    if (raw === libraryText) return
    var lib
    try { lib = JSON.parse(raw) } catch (e) { return }
    if (lib.ok === false) { statusError = true; statusText = lib.message || ""; return }
    libraryText = raw
    items = lib.items || []
    playlists = lib.playlists || []
    channels = lib.channels || []
    welcomed = !!lib.welcomed
    var index = {}
    items.forEach(function(s) { index[s.url] = s })
    playlists.forEach(function(p) { (p.items || []).forEach(function(s) { index[s.url] = s }) })
    songsByUrl = index
    if (openPlaylistId !== "" && !findById(playlists, openPlaylistId)) openPlaylistId = ""
  }

  // A plain "ok" from a player control leaves the status line alone; an
  // action's "ok" clears its progress message.
  function showReply(text, fromAction) {
    try {
      var r = JSON.parse(text)
      if (r.ok && r.message === "ok" && !fromAction) return
      statusError = !r.ok
      statusText = r.message === "ok" ? "" : (r.message || "")
    } catch (e) {}
  }

  function action(args, message) {
    if (actionProc.running) return
    busy = true
    statusError = false
    statusText = message || ""
    actionProc.command = ["bash", backend].concat(args)
    actionProc.running = true
  }

  // Player controls run on their own process so they still work while a
  // slow action (importing, loading a channel) is in flight.
  function control(cmd) {
    if (controlProc.running) return
    controlProc.command = ["bash", backend, cmd]
    controlProc.running = true
  }

  function submit() {
    var text = linkField.text.trim()
    if (text === "") return
    if (tab === "songs") action(["add", text], "Adding…")
    else if (tab === "playlists" && openPlaylist) action(["pl-add", openPlaylist.id, text], "Adding…")
    else if (tab === "playlists") {
      if (/^(https?:\/\/|www\.|youtube\.|youtu\.be|m\.youtube)/i.test(text)) action(["pl-import", text], "Importing playlist…")
      else action(["pl-new", text])
    }
    else action(["ch-add", text], "Looking up channel…")
    linkField.text = ""
  }

  function playRow(row) {
    if (row.current) { control("toggle"); return }
    if (tab === "songs") action(["play", "songs", row.key])
    else if (tab === "playlists" && openPlaylist) action(["play", "playlist", openPlaylist.id, row.key])
    else if (tab === "playlists") action(["play", "playlist", row.key])
    else action(["play", "channel", row.key], "Loading channel…")
  }

  // Deleting a whole playlist or channel takes a second click to confirm.
  function removeRow(row) {
    if (tab === "songs") action(["remove", row.key])
    else if (tab === "playlists" && openPlaylist) action(["pl-del", openPlaylist.id, row.key])
    else if (pendingDelete !== row.key) {
      pendingDelete = row.key
      statusError = true
      statusText = "Click 󰆴 again to delete \"" + row.label + "\""
      confirmTimer.restart()
    } else {
      pendingDelete = ""
      action([tab === "playlists" ? "pl-remove" : "ch-remove", row.key])
    }
  }

  function showTab(value) {
    tab = value
    openPlaylistId = ""
    pendingDelete = ""
    statusText = ""
    Qt.callLater(function() { linkField.forceActiveFocus() })
  }

  function toggleStarter(id) {
    var d = dropped.slice()
    var i = d.indexOf(id)
    if (i < 0) d.push(id)
    else d.splice(i, 1)
    dropped = d
  }

  // The unticked starter playlists are deleted, and the panel opens on Playlists.
  function finishWelcome() {
    tab = "playlists"
    openPlaylistId = ""
    action(["welcome"].concat(dropped.filter(function(id) { return findById(starters, id) !== null })))
  }

  implicitWidth: barRow.implicitWidth
  implicitHeight: barRow.implicitHeight

  onOpenedChanged: {
    if (opened) {
      refresh()
      loadLibrary()
      Qt.callLater(function() { (root.welcoming ? keepButton : linkField).forceActiveFocus() })
    } else {
      linkField.text = ""
      pendingDelete = ""
    }
  }
  onWelcomingChanged: if (!welcoming && opened) Qt.callLater(function() { linkField.forceActiveFocus() })

  // `omarchy-shell christian-focus <method>`, e.g. for a keybinding.
  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function showTab(name: string): void { root.showTab(name); root.open() }
    function openPlaylist(id: string): void { root.showTab("playlists"); root.openPlaylistId = id; root.open() }
    function playPause(): void { root.control("toggle") }
    function next(): void { root.control("next") }
    function previous(): void { root.control("prev") }
  }

  Process {
    id: stateProc
    command: ["bash", root.backend, "state"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyState(text) }
    onExited: if (root.stateAgain) { root.stateAgain = false; Qt.callLater(function() { root.refresh() }) }
  }

  Process {
    id: libraryProc
    command: ["bash", root.backend, "library"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyLibrary(text) }
    onExited: if (root.libraryAgain) { root.libraryAgain = false; Qt.callLater(function() { root.loadLibrary() }) }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.showReply(text, true) }
    onExited: { root.busy = false; root.refresh(); root.loadLibrary() }
  }

  Process {
    id: controlProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.showReply(text, false) }
    onExited: root.refresh()
  }

  // Starter playlists (catalog.json next to the backend) are merged once per
  // shell start; the backend skips the work when that file hasn't changed.
  Process {
    command: ["bash", root.backend, "catalog"]
    running: true
    onExited: root.loadLibrary()
  }

  // Polling starts a small process (no jq), so it's fast only while the panel
  // is open and playing. Closed, the bar only needs the play/pause icon, which
  // the controls refresh themselves; the slow poll catches media keys and the
  // end of a playlist.
  Timer {
    interval: root.opened ? (root.live ? 1000 : 5000) : 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: confirmTimer
    interval: 4000
    onTriggered: { root.pendingDelete = ""; if (root.statusError) root.statusText = "" }
  }

  Row {
    id: barRow
    anchors.fill: parent

    WidgetButton {
      id: labelButton
      bar: root.bar
      text: (root.live ? "󰎈" : "󰝚") + " Christian-Focus"
      tooltipText: "Right-click to play or pause, middle-click to skip"
      useActiveColor: false
      onPressed: function(buttonCode) {
        if (buttonCode === Qt.RightButton) root.control("toggle")
        else if (buttonCode === Qt.MiddleButton) root.control("next")
        else root.toggle()
      }
    }

    BarIconButton {
      bar: root.bar
      text: "󰒮"
      dimmed: !root.playing
      onPressed: root.control("prev")
    }

    BarIconButton {
      bar: root.bar
      text: root.live ? "󰏤" : "󰐊"
      onPressed: root.control("toggle")
    }

    BarIconButton {
      bar: root.bar
      text: "󰒭"
      dimmed: !root.playing
      onPressed: root.control("next")
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: labelButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: root.welcoming ? keepButton : linkField
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    Flickable {
      id: panelFlick
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: column
        width: panelFlick.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "Christian-Focus"
          meta: root.welcoming ? "Calm Christian music for focused work"
            : root.playing
            ? (root.paused ? "Paused · " : "") + root.shortTitle(root.title) + "  " + root.clock(root.position) + " / " + root.clock(root.duration)
            : "Not playing"
          detail: root.playing && root.context ? root.context.name : ""
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: "†"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              font.bold: true
            }
          }
        }

        // First run: choose which starter playlists to keep.
        Column {
          visible: root.welcoming
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "PICK YOUR STARTER PLAYLISTS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "Untick any you don't want. You can add your own music anytime."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.starters
              Button {
                required property var modelData
                readonly property bool kept: root.dropped.indexOf(modelData.id) < 0
                text: modelData.name
                iconText: kept ? "󰄬" : "󰄱"
                tooltipText: (modelData.items || []).length + " songs"
                selected: kept
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.toggleStarter(modelData.id)
              }
            }
          }

          Button {
            id: keepButton
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.keptCount === 0 ? "Start with my own music"
              : "Keep " + root.keptCount + (root.keptCount === 1 ? " playlist" : " playlists")
            bordered: true
            focusable: true
            enabled: !root.busy
            foreground: root.foreground
            fontFamily: root.fontFamily
            Keys.onEscapePressed: root.close()
            onClicked: root.finishWelcome()
          }

          Text {
            textFormat: Text.PlainText
            visible: root.statusError && root.statusText !== ""
            width: parent.width
            text: root.statusText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "On the bar, right-click the name to play or pause, and middle-click to skip."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }

        Column {
          visible: !root.welcoming
          width: parent.width
          spacing: Style.space(12)

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(6)

            PanelActionButton {
              iconText: "󰒮"; tooltipText: "Previous"
              foreground: root.foreground; fontFamily: root.fontFamily
              enabled: root.playing
              onClicked: root.control("prev")
            }
            PanelActionButton {
              iconText: root.live ? "󰏤" : "󰐊"
              tooltipText: root.live ? "Pause" : "Play"
              foreground: root.foreground; fontFamily: root.fontFamily
              onClicked: root.control("toggle")
            }
            PanelActionButton {
              iconText: "󰒭"; tooltipText: "Next"
              foreground: root.foreground; fontFamily: root.fontFamily
              enabled: root.playing
              onClicked: root.control("next")
            }
            PanelActionButton {
              iconText: "󰓛"; tooltipText: "Stop"
              foreground: root.foreground; fontFamily: root.fontFamily
              enabled: root.playing
              onClicked: root.control("stop")
            }
          }

          ButtonGroup {
            anchors.horizontalCenter: parent.horizontalCenter
            focusable: false
            foreground: root.foreground
            fontFamily: root.fontFamily
            options: [
              { value: "songs", label: "My Songs" },
              { value: "playlists", label: "Playlists" },
              { value: "channels", label: "Channels" }
            ]
            value: root.tab
            onChanged: function(v) { root.showTab(v) }
          }

          // Inside a playlist: back button, name, and playlist actions.
          RowLayout {
            visible: root.tab === "playlists" && root.openPlaylist !== null
            width: parent.width
            spacing: Style.space(6)

            PanelActionButton {
              iconText: "󰁍"; tooltipText: "All playlists"
              foreground: root.foreground; fontFamily: root.fontFamily
              onClicked: { root.openPlaylistId = ""; root.statusText = "" }
            }

            Text {
              textFormat: Text.PlainText
              Layout.fillWidth: true
              text: root.openPlaylist ? root.openPlaylist.name : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }

            PanelActionButton {
              iconText: root.playingFrom("playlist", root.openPlaylistId) && root.live ? "󰏤" : "󰐊"
              tooltipText: "Play playlist"
              foreground: root.foreground; fontFamily: root.fontFamily
              enabled: root.openPlaylist !== null && (root.openPlaylist.items || []).length > 0
              onClicked: root.playingFrom("playlist", root.openPlaylistId)
                ? root.control("toggle") : root.action(["play", "playlist", root.openPlaylistId])
            }

            PanelActionButton {
              visible: root.openPlaylist !== null && !!root.openPlaylist.source
              iconText: "󰑓"; tooltipText: "Sync from YouTube"
              foreground: root.foreground; fontFamily: root.fontFamily
              enabled: !root.busy
              onClicked: root.action(["pl-sync", root.openPlaylistId], "Syncing…")
            }
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: linkField
              Layout.fillWidth: true
              placeholderText: root.placeholder
              foreground: root.foreground
              font.family: root.fontFamily
              enabled: !root.busy
              onAccepted: root.submit()
              Keys.onEscapePressed: root.close()
            }

            PanelActionButton {
              iconText: "󰐕"; tooltipText: "Add"
              foreground: root.foreground; fontFamily: root.fontFamily
              bordered: true
              enabled: !root.busy && linkField.text.trim() !== ""
              Layout.alignment: Qt.AlignVCenter
              onClicked: root.submit()
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.statusText !== ""
            width: parent.width
            text: root.statusText
            color: root.statusError ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: root.listHeader
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            visible: root.rows.length === 0
            width: parent.width
            text: root.emptyText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          Column {
            id: rowColumn
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: rowModel
              ListRow {
                required property var model
                width: rowColumn.width
                row: model
              }
            }
          }
        }
      }
    }
  }

  // One line in any tab: icon, short label, time/count, and play + remove
  // buttons that appear while the row is hovered.
  component ListRow: CursorSurface {
    id: listRow
    property var row: ({})
    readonly property bool hot: root.hoveredKey === row.key

    hasCursor: hot
    current: !!row.current
    foreground: root.foreground
    implicitHeight: Math.max(rowContent.implicitHeight, Style.space(22)) + Style.spacing.rowPaddingX

    // HoverHandler (unlike a MouseArea) keeps reporting hover while the
    // pointer is over the row's own buttons, so they don't flicker away.
    HoverHandler {
      onHoveredChanged: {
        if (hovered) root.hoveredKey = listRow.row.key
        else if (root.hoveredKey === listRow.row.key) root.hoveredKey = ""
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: if (listRow.row.opens) { root.openPlaylistId = listRow.row.key; root.statusText = "" }
      onDoubleClicked: if (!listRow.row.opens) root.playRow(listRow.row)
    }

    RowLayout {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: listRow.row.current ? (root.paused ? "󰏤" : "󰎈") : listRow.row.icon
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: listRow.row.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: !!listRow.row.current
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        text: listRow.row.current && listRow.row.duration > 0 ? root.progress(listRow.row.duration) : listRow.row.meta
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      PanelActionButton {
        visible: listRow.hot
        iconText: listRow.row.current && root.live ? "󰏤" : (root.tab === "channels" ? "󰒝" : "󰐊")
        tooltipText: listRow.row.current && root.live ? "Pause" : (root.tab === "channels" ? "Shuffle play" : "Play")
        foreground: root.foreground; fontFamily: root.fontFamily
        onClicked: root.playRow(listRow.row)
      }

      PanelActionButton {
        visible: listRow.hot
        iconText: "󰆴"
        tooltipText: root.pendingDelete === listRow.row.key ? "Click again to delete" : "Remove"
        foreground: root.pendingDelete === listRow.row.key ? root.urgent : root.foreground
        hoverColor: root.urgent; fontFamily: root.fontFamily
        onClicked: root.removeRow(listRow.row)
      }
    }
  }
}
