# TODO

Planned work and ideas for OmaEar. Checked items are done.

1. [x] **Refresh-all UX** — While refresh is in progress, gray out all shows that are more than “caught-up dim.” After refresh finishes, restore each show’s dim/full-lit state from played status. If refresh fails, recover a functional shelf. Animate the refresh icon while in progress; return it to the base icon on failure.
2. [x] **Episode detail: web links** — Underline obvious web links in episode detail; open them in the system default browser.
3. [x] **Episode detail: timestamps** — Recognize timestamps in episode detail; a click seeks the progress bar to that time and starts playback immediately, staying on the detail page.
4. [x] **Main Mark button** — After a confirm dialog that matches the existing design language, mark all podcasts and episodes as played.
5. [x] **Main gallery columns** — Enforce min 1 column, max 10 columns.
6. [x] **Artwork force-reload** — Ctrl+Left-click on the refresh button forces artwork reload.
7. [ ] **Keyboard-first** — Make the whole app usable from the keyboard, in line with Omarchy.
8. [x] **Eye-toggle filter** — Independent Main vs Episodes; open = show all, closed = unplayed only; persist preferred setting.
9. [x] **Playback architecture** — The detached player over D-Bus stays the single play/pause/seek service, with a shared scrubber component.
10. [x] **Header action order** — Empty shelf: Add feed and Import OPML only. Once shows exist: Eye, gallery/list, Refresh, gap, Mark all played, Add, Import. Show page: Eye, Refresh, gap, Mark this show played, Remove.
11. [x] **Last-refresh indicator / skip auto-refresh** — Indicate when last update/refresh ran; if within ~30 minutes of last refresh, skip automatic refresh on launch (manual refresh still allowed).
12. [x] **Small windows** — In a small window, keep the player controls and progress, and let the rest step aside.
13. [x] **Scrubber time tooltip** — Show the time while hovering or dragging the scrubber, in the player bar and Now Playing.
14. [x] **Faster mouse-wheel scroll** — About 2× wheel speed (FastWheel).
15. [x] **Quiet scrollbar** — Minimal dynamic scrollbar (QuietScroll) on shelf and episode lists that tracks loaded content.
16. [x] **Scroll look and feel** — Smooth wheel scrolling, a comfortable step size, and a draggable scrollbar that hides when idle.
17. [x] **Add-feed URL dialog** — Restyle the add-by-URL dialog to match the rest of the app.
18. [x] **Search: online podcast directory (Explore)** — Find podcasts out there (iTunes directory, top chart), preview and subscribe.
19. [x] **Queue** — Add episodes to a queue, play from it, reorder, and remove.
20. [x] **Page navigation** — Browser-style back/forward history; mouse side buttons, Alt+Left/Right.
21. [x] **Now Playing art** — Ctrl+wheel resizes the cover (20–100%, saved, Ctrl+0 resets) without flicker; right-click Copy / Save artwork… / Copy image URL on Now Playing art and shelf covers.
22. [ ] **Search: episodes within library** — Search episode titles/notes across subscribed shows.
23. [x] **Explore: publisher link** — On an Explore podcast preview, make the publisher subtitle (e.g. "DR", "RADIO IIII") clickable to run a new search showing that publisher's podcasts.
24. [x] **Update dot on ⓘ** — Show a small dot on the Info button when an update is available (after an update OmaEar restarts itself and resumes playback), so people notice without opening the Info page.
