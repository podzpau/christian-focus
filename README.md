# Christian-Focus

Calm Christian music for focused work, played from your Omarchy bar.

Christian-Focus puts a small player in the top bar. It plays the audio of YouTube videos and freely licensed recordings without opening a window, so nothing competes for your attention.

- **Eight starter playlists**, mostly hour-long mixes: Gregorian chant, sacred polyphony, instrumental hymns, Marian hymns, Eastern and Byzantine chant, organ, Taizé and Catholic lofi.
- **Your own music, too.** Paste a YouTube song, playlist or channel link to add it.
- **Picked by hand.** AI-generated music was left out wherever we could tell.

## Install

```sh
omarchy plugin add https://github.com/podzpau/christian-focus --enable
```

Omarchy asks where on the bar to put it. There's nothing else to install: the player uses mpv, yt-dlp, jq and socat, which come with Omarchy. It needs Omarchy 4 or newer.

The first time you open the player, pick which starter playlists to keep.

## Use

- **Open the player:** click **Christian-Focus** on the bar.
- **Play, pause, skip:** use the buttons next to the name. You can also right-click the name to play or pause, and middle-click it to skip. With nothing playing, play starts whatever you played last. While music plays, your keyboard's media keys work too.
- **Start listening:** open the **Playlists** tab and press play on a playlist.
- **Add your own:** paste a YouTube link into the box at the top.
  - On **My Songs**, a song link adds the song. A playlist link imports the whole playlist.
  - On **Playlists**, paste a playlist link to import it, or type a name to start an empty playlist. Imported playlists have a sync button that picks up new videos.
  - On **Channels**, paste a channel link. Playing a channel shuffles its latest videos.
- **Remove something:** hover over it and click the bin.

### Keyboard shortcut

To play or pause from the keyboard, add a line like this to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + P", "Christian-Focus", "omarchy-shell christian-focus playPause")
```

`next`, `previous` and `toggle` (open or close the panel) work the same way.

## Update

```sh
omarchy plugin update christian-focus
omarchy restart shell
```

Restarting the bar loads the new version; your music keeps playing. Updates can bring new starter songs. They never bring back songs or playlists you deleted, and they never touch the music you added.

## Remove

Stop the music first (■ in the panel), then:

```sh
omarchy plugin remove christian-focus
```

If you forget, the music stops by itself within two minutes. Your library stays in `~/.config/omarchy/christian-focus.json` in case you reinstall. Delete that file to start fresh.

## Light on your system

- No background service. mpv runs only while music plays, audio only.
- With the panel closed, the bar asks the player for its state once every 30 seconds: one small query, nothing more.
- Your library is read only when you open the panel or change something.

## Privacy

There's no account and no tracking. Your library stays on your computer. The player connects only to YouTube, Wikimedia Commons and the Internet Archive, to stream what you play.

## Content and credits

Christian-Focus plays links. It hosts no audio and copies none, and every recording belongs to the people who made it. The free recordings are credited in [CREDITS.md](CREDITS.md).

If you made something in the starter playlists and want it taken out, [open a removal request](https://github.com/podzpau/christian-focus/issues/new?template=removal-request.md). It's taken out in the next update, and it leaves each listener's library when they update.

## Suggest a song

Know a long, calm, human-made Christian piece that belongs here? [Suggest it](https://github.com/podzpau/christian-focus/issues/new?template=suggest-a-song.md). Links must come from the people who made the music, not re-uploads.

## License

The code is under the [MIT License](LICENSE). Each recording keeps its own license; see [CREDITS.md](CREDITS.md).
