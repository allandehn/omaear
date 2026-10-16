# TODO

Planned work and ideas for OmaEar.

## Open

Nothing open right now.

## Nice to have

Nothing here right now.

## Done

- [x] **Keyboard-first** — Arrows, Tab/Shift+Tab and Enter on every page (main page, episodes, details, Queue, search, Explore, Now Playing), with a quiet focus ring and focus restored on Back.
- [x] **Search: episodes within library** — Magnifier or Ctrl+F searches titles and show notes of every subscribed episode as you type (all words must match; title matches first, then newest; matches in bold). Click opens details, play over the art, right-click for the episode menu, Enter opens the top result. The globe button takes the same words to Explore.
- [x] **Refresh-all UX** — While refresh is in progress, gray out all shows that are more than “caught-up dim.” After refresh finishes, restore each show’s dim/full-lit state from played status. If refresh fails, recover a functional shelf. Animate the refresh icon while in progress; return it to the base icon on failure.
- [x] **Episode detail: web links** — Underline obvious web links in episode detail; open them in the system default browser.
- [x] **Episode detail: timestamps** — Recognize timestamps in episode detail; a click seeks the progress bar to that time and starts playback immediately, staying on the detail page.
- [x] **Main Mark button** — After a confirm dialog that matches the existing design language, mark all podcasts and episodes as played.
- [x] **Main gallery columns** — Enforce min 1 column, max 10 columns.
- [x] **Artwork force-reload** — Ctrl+Left-click on the refresh button forces artwork reload.
- [x] **Eye-toggle filter** — Independent Main vs Episodes; open = show all, closed = unplayed only; persist preferred setting.
- [x] **Playback architecture** — The detached player over D-Bus stays the single play/pause/seek service, with a shared scrubber component.
- [x] **Header action order** — Empty shelf: Add feed and Import OPML only. Once shows exist: Eye, gallery/list, Refresh, gap, Mark all played, Add, Import. Show page: Eye, Refresh, gap, Mark this show played, Remove.
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
- [x] **Update dot on ⓘ** — Show a small dot on the Info button when an update is available (after an update OmaEar restarts itself and resumes playback), so people notice without opening the Info page.
