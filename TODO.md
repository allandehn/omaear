# TODO

Planned work and ideas for OmaEar.

## Open

- [ ] **Cheaper feed refresh** — Send the stored ETag and Last-Modified back (If-None-Match / If-Modified-Since) and skip a feed entirely on 304; when it changed, stream-parse with QXmlStreamReader and stop at the first episode guid we already have; do the work off the UI thread and insert new episodes in one SQLite transaction; back off on feeds that rarely change. Measure about 20 real feeds before and after (bytes, CPU time, peak RSS, disk writes), plus one command for checking scroll smoothness on the Beelink.
- [ ] **Shelf right-click menu** — The menu stays where it opened, shows the podcast's name as a title, and every action stays tied to that podcast even if the Shelf reorders underneath; it closes if that podcast disappears.
- [ ] **Fewer idle wakeups** — Measure how often OmaEar wakes up when nothing is happening, and cut timers and redraws that aren't needed.
- [ ] **Right-click menus like Omarchy 4.5** — Redesign the look of every right-click menu to match Omarchy Stable 4.5, including pill-style toggles if 4.5 has them. Consult Design Champ. (Priority: first, together with dialogs.)
- [ ] **Dialogs like Omarchy 4.5** — Redesign all dialogs to match Omarchy Stable 4.5: button look, placement and default action. Consult Design Champ. (Priority: first, together with menus.)
- [ ] **Mark all podcasts played** — Mark every episode in every podcast as played, from the Shelf empty-space menu, a podcast's right-click menu and the top-right ⋯ menu.
- [ ] **Explore behaves like the Shelf** — Explore adopts the Shelf's lifts, animations, shades and keys, and responds to the same toggles and settings.
- [ ] **Explore cover cache, done right** — Switching regions (e.g. Poland, Switzerland, Poland…) is slow the first time, still not fast the second, and only good the third. Find why, make the second visit as fast as the third (or faster), consider drawing the page only once its covers are ready, and decide how many regions to keep cached (5–6 regions should work, even if rare), and keep each cover's identity stable across searches and regions so covers stay put instead of reloading. Consult Gonzales. Very important; next after the 4.5 look.
- [ ] **Smaller binary** — Strip the release binary.
- [ ] **SQLite tuning** — Tune the library database (pragmas, indexes, batched writes) for faster loads and fewer disk writes. Do it together with the cheaper feed refresh, which shares the batched-insert work; Explore covers don't use SQLite (they use Qt's network disk cache), so it won't help that item.

## Nice to have

Nothing here right now.

## Done

- [x] **Release from an exact merged commit (0.3.1)** — `scripts/release.sh --preview | --validate | --publish --sha <40-hex> --version X.Y.Z`: never commits or pushes `main` (no admin bypass), signing key only for `--publish`, refuses an existing tag, release or package before any write, and `--publish` needs an explicit `--repo-db` mode. UI tests in the release run use throwaway fixtures, never a copy of the real library. `scripts/release-flow-test.sh` covers it with mocks, and `--real-tools` with real makepkg, repo-add and gpg.
- [x] **Keyboard and mouse input modes (0.3.1)** — Keys switch to keyboard mode (ring shows), a real mouse move switches back. Tab/Shift+Tab move between top bar, page and player bar, remembering each area's last item. h/j/k/l work like the arrows (not while typing). ⋯ menu: Grid wrap rows/full (rows is the default and stays in a column) and Navigation animation (gliding ring and refresh spin). The cover lift is always on. Headless nav checks run with `tests/nav-feeds`.
- [x] **Episodes page like the shelf (0.3.1)** — Shelf-style focus ring, two-column key navigation (cover and text), a top bar with eye, refresh (this show), + and a ⋯ menu, and Search episodes from a show's menu is scoped to that show.
- [x] **Theme shapes (0.3.1)** — Corner radii follow Hyprland's live `decoration:rounding` (cards and panels R; buttons, chips, menus and tips min(R, 4)), plus an urgent colour; covers, icons and list rows follow it too. Bar, pill and dim tints are derived from the live theme colours in OKLCH, so hue and perceived lightness hold across theme changes.
- [x] **Lighter covers (0.3.1)** — Player-bar, episode and Explore covers are decoded at display size, and Explore keeps the previous region's covers within a small RAM-sized budget (2% of free memory, 8–32 MB).
- [x] **Cleaner Info page (0.2.0)** — Only what hovering can't tell you: Keys, Search, Artwork and Hidden tricks under bigger section headers; tooltip-covered items and the separate right-click lines are gone (one line now says which things have menus), and the "Info" title is dropped.
- [x] **New GitHub home (0.1.10)** — OmaEar moved to github.com/allandehn/omaear. Links, the installer, the update check and the package point there, and upgrading rewrites the [omaear] Server line in pacman.conf to the new address (old links still redirect).
- [x] **Menus instead of Mark buttons (0.2)** — One episode menu (Play now / next, mark played, newer, older, unplayed, queue, mark all) on Episodes rows and art; the player-bar art gets a trimmed variant with Pause / Resume; art menus with Mark as played on details and Now Playing; Mark all as played on the shelf cover menu. Mark / Unsubscribe / mark-all buttons left the top bars and player bar. Now Playing notes get clickable links and timestamps. Unsubscribe from all (two confirmations) in every shelf menu, including a new empty-space menu.
- [x] **Menus and popups (0.2)** — Volume and speed popups share the context-menu look (square corners, same border and highlight). Clicking outside any menu or popup closes it and the click goes through (Back, the next right-click); menus also close on page, layout or dialog changes and when the window loses focus. Mono button tip shows the state: Mono / Stereo.
- [x] **Decluttered shelf top bar (0.2)** — Eye, Refresh and Queue stay; gallery/list, Search, Find new podcasts, Add feed, Import, Export OPML (new, OPML 2.0) and Info move to a ⋯ menu (update dot on ⋯). Empty-space menu gets Add, Import, Export.
- [x] **Queue visibility** — Queue mark on episode art (lists and search) with "In queue (#n)", "In queue, #2 of 5" on episode details, and Previous / Next in the queue in the player bar and on Now Playing (always shown, dimmed when there is nowhere to go, "Up next / Previous: …" tips).
- [x] **Autoplay toggle** — Autoplay button with its own icon in the player bar, on Now Playing and on the Queue page; autoplay only decides what happens at the end of an episode.
- [x] **Mark played stops it** — Marking the playing episode played (any path) moves on in the queue with autoplay on, otherwise stops and hides the player bar (Now Playing steps back); played episodes leave the queue.
- [x] **Now Playing layout** — Size-tiered transport row (Play largest, seek, then Previous / Next) with volume, speed, autoplay and mono below; notes scroll in their own box and never run under the player bar.
- [x] **Speed presets** — 0.75×, 1×, 1.25×, 1.5×, 1.75×, 2× (older speeds snap to the nearest), fixed-width tabular labels; the Now Playing speed opens the same picker as the player bar.
- [x] **Scroll-wheel volume and speed** — Wheel on the buttons and popups, moving the slider or list highlight in the wheel's direction.
- [x] **Status pill** — Refresh progress and messages float above the player bar instead of shifting page content; repeated messages show every time.
- [x] **Popup timing** — One shared fade for menus, popups and dialogs; choosing a menu item closes the menu at once.
- [x] **Smoother launch** — No window bounce or cover stretch on start (fixed scale on Wayland), sharper Back icon, refresh progress counter.

- [x] **Keyboard-first** — Arrows, Tab/Shift+Tab and Enter on every page (main page, episodes, details, Queue, search, Explore, Now Playing), with a quiet focus ring and focus restored on Back.
- [x] **Search: episodes within library** — Magnifier or Ctrl+F searches titles and show notes of every subscribed episode as you type (all words must match; title matches first, then newest; matches in bold). Click opens details, play over the art, right-click for the episode menu, Enter opens the top result. The globe button takes the same words to Find new podcasts.
- [x] **Refresh-all UX** — While refresh is in progress, gray out all shows that are more than “caught-up dim.” After refresh finishes, restore each show’s dim/full-lit state from played status. If refresh fails, recover a functional shelf. Animate the refresh icon while in progress; return it to the base icon on failure.
- [x] **Episode detail: web links** — Underline obvious web links in episode detail; open them in the system default browser.
- [x] **Episode detail: timestamps** — Recognize timestamps in episode detail; a click seeks the progress bar to that time and starts playback immediately, staying on the detail page.
- [x] **Main gallery columns** — Enforce min 1 column, max 10 columns.
- [x] **Artwork force-reload** — Ctrl+Left-click on the refresh button forces artwork reload.
- [x] **Eye-toggle filter** — Independent Main vs Episodes; open = show all, closed = unplayed only; persist preferred setting.
- [x] **Playback architecture** — The detached player over D-Bus stays the single play/pause/seek service, with a shared scrubber component.
- [x] **Header action order** — Empty shelf: Add feed and Import OPML only. Marking and unsubscribing live in right-click menus, not the top bars.
- [x] **Last-refresh indicator / skip auto-refresh** — Indicate when last update/refresh ran; if within ~30 minutes of last refresh, skip automatic refresh on launch (manual refresh still allowed).
- [x] **Small windows** — In a small window, keep the player controls and progress, and let the rest step aside.
- [x] **Scrubber time tooltip** — Show the time while hovering or dragging the scrubber, in the player bar and Now Playing.
- [x] **Faster mouse-wheel scroll** — About 2× wheel speed (FastWheel).
- [x] **Quiet scrollbar** — Minimal dynamic scrollbar (QuietScroll) on shelf and episode lists that tracks loaded content.
- [x] **Scroll look and feel** — Smooth wheel scrolling, a comfortable step size, and a draggable scrollbar that hides when idle.
- [x] **Add-feed URL dialog** — Restyle the add-by-URL dialog to match the rest of the app.
- [x] **Search: online podcast directory (Explore)** — Find podcasts out there (iTunes directory, top chart), preview and subscribe.
- [x] **Queue** — Add episodes to a queue, play from it, reorder, and remove.
- [x] **Page navigation** — Browser-style back/forward history; mouse side buttons, Alt+Left/Right.
- [x] **Now Playing art** — Ctrl+wheel resizes the cover (20–100%, saved, Ctrl+0 resets) without flicker; right-click Copy / Save artwork… / Copy image URL on Now Playing art and shelf covers.
- [x] **Explore: publisher link** — On an Explore podcast preview, make the publisher subtitle (e.g. "DR", "RADIO IIII") clickable to run a new search showing that publisher's podcasts.
- [x] **Update dot on ⓘ** — Show a small dot on the Info button (now on the shelf ⋯ button) when an update is available (after an update OmaEar restarts itself and resumes playback), so people notice without opening the Info page.
