import QtQuick

// Artwork menu for one episode (Now Playing cover, episode details art):
// Copy / Save artwork… / Copy image URL, then Mark as played on its own.
AppMenu {
    id: menu
    property double episodeId: 0
    property double showId: 0
    property var info: ({})
    property bool played: false

    function openFor(epId, shId, anchor) {
        var st = backend.episodeMenuState(epId)
        episodeId = epId
        showId = shId ? shId : (st.showId || 0)
        info = backend.artworkInfo(epId, showId)
        played = st.played === true
        if (anchor)
            popupAt(anchor)
        else
            popup()
    }

    AppMenuItem {
        text: "Copy"
        enabled: menu.info.available === true
        onChosen: backend.copyArtwork(menu.episodeId, menu.showId)
    }
    AppMenuItem {
        text: "Save artwork…"
        enabled: menu.info.available === true
        onChosen: win.saveArtworkAs(menu.episodeId, menu.showId)
    }
    AppMenuItem {
        text: "Copy image URL"
        enabled: menu.info.hasUrl === true
        onChosen: backend.copyArtworkUrl(menu.episodeId, menu.showId)
    }
    AppMenuSeparator {}
    AppMenuItem {
        text: "Mark as played"
        enabled: menu.episodeId !== 0 && !menu.played
        onChosen: backend.markPlayed(menu.episodeId, true)
    }
}
