<p align="center"><img src="assets/icons/banner.png" srcset="assets/icons/banner@2x.png 2x" alt="OmaEar"></p>

OmaEar is a podcast player for [Omarchy](https://omarchy.org). It keeps a shelf of your shows and keeps playing after you close the window.

Designed together by [Allan Kristensen](https://github.com/allanjorch) and [Grok](https://x.ai).

![OmaEar shelf with a few shows and an episode playing](assets/screenshots/shelf.png)

![Now Playing](assets/screenshots/now-playing.png)

## Install

On Omarchy, run:

```
curl -fsSL https://raw.githubusercontent.com/allanjorch/omaear/main/install.sh | bash
```

It adds the OmaEar package repository, with packages signed by Allan Kristensen (key `AC6F F13C 76D8 916C CCF2  DA05 C322 5162 B525 7DB4`), and installs the app. Updates then arrive with `omarchy update`. Open **OmaEar** from the app launcher, or run `omaear`.

Prefer to do it by hand? Read [install.sh](install.sh). It's a handful of lines.

## Getting started

Paste a feed URL with **Add feed**, find shows in **Explore**, or bring your whole library over from another podcast app with **Import OPML**.

## Features

**Shelf.** Your shows as a gallery or a list. Shows with unheard episodes sit in front, newest first, with an unheard count on the cover. Caught-up shows sit behind, dimmed. The eye button switches between all shows and unplayed only.

**Search.** The magnifier (or Ctrl+F) searches show names, episode titles and show notes across everything you subscribe to, with results updating as you type. Show matches come first, then titles, then notes, newest first within each. The Show, Title and Notes chips (Alt+1/2/3) pick what to search. The globe button sends the same words to Explore.

**Explore.** Search the podcast directory or browse the top charts for any region (the flag picks it, and the choice is remembered). Preview a show before you subscribe. Click a publisher name to see all of that publisher's shows, newest first.

**Episodes.** Play straight from the episode art. Open an episode for its full notes, where links open in your browser and timestamps jump the player to that point.

**Queue.** Add episodes, play next, drag to reorder. An episode stays in the queue while it plays and leaves once it's finished. With **autoplay** on, the queue decides what plays next. With it off, the queue is simply a pinned list.

**Player.** Back 15 s, forward 30 s, a scrubber that shows the time on hover, speeds from 0.5× to 2×, volume (click to mute, scroll to adjust; scroll on the speed to change it too), and a **mono** toggle for recordings with lopsided channels. Now Playing gives you a large cover you can resize with Ctrl+wheel.

**Keyboard.** Every page works from the keyboard: arrows and Tab move a quiet focus ring through the buttons, podcasts, episodes and player bar, Enter opens or presses, the Menu key opens the right-click menu, and Back returns the ring to where you came from.

**Keeps playing.** Close the window and the episode carries on, with controls in the Omarchy bar and media keys. Open OmaEar again and the same window comes back.

**Fits your theme.** Colors and fonts come from the current Omarchy theme and change live when you switch themes, logo included. Text size follows your display scale.

**Info.** The ⓘ button (or `?`) lists every shortcut and mouse trick, shows the version, and tells you when an update is available. Click "run omarchy update" and it does just that.

## Shortcuts

| Key / mouse | Action |
| --- | --- |
| Space | Play / pause |
| Arrows | Move through buttons, podcasts, episodes and the player bar; Enter opens or presses |
| Tab / Shift+Tab | Jump between areas (top bar, list, player bar) |
| Menu / Shift+F10 | Right-click menu for the highlighted item |
| Delete (queue) | Remove the highlighted episode from the queue |
| Ctrl+F | Search your episodes (Enter opens the top result) |
| Esc, Alt+Left, Backspace, mouse Back | Back |
| Alt+Right, mouse Forward | Forward |
| Ctrl+wheel, Ctrl+= / Ctrl+− | Resize covers and art |
| Ctrl+0 | Reset art to its default size |
| ? | Info |
| Ctrl+Q | Close the window (audio keeps playing) |

## Marking played

Right-click an episode, or use **Mark**, to mark it played or unplayed, mark everything older or newer, or mark the whole show. An episode counts as heard in its last few percent, so a closing jingle doesn't keep a show in front. Playing an episode you've already heard marks it unplayed again.

## Your data

The library lives in `~/.local/share/omaear/` and downloaded audio and artwork in `~/.cache/omaear/`.

## Uninstall

Press Del on OmaEar in the app menu, or run:

```sh
sudo pacman -Rns omaear
```

That removes the app but keeps your shows, progress, and settings, so a reinstall picks up where you left off. To remove those too:

```sh
rm -rf ~/.local/share/omaear ~/.cache/omaear ~/.config/omaear.conf
```

To also remove the OmaEar package source, delete the `[omaear]` section from `/etc/pacman.conf` and run `sudo pacman-key --delete AC6FF13C76D8916CCCF2DA05C3225162B5257DB4`.

## Build from source

Needs Qt 6 (Quick, Quick Controls, Multimedia, SQL, Network, D-Bus), all already on Omarchy.

```
qmake6
make -j
./omaear --self-test
make install    # installs to ~/.local, no root needed
```

To build the Arch package yourself, use `packaging/PKGBUILD`, or run `packaging/build-local.sh` to build one from this checkout.

## License

[MIT](LICENSE)
