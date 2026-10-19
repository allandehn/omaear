import QtQuick

// The one episode menu: Episodes page rows and art, and the player bar's art.
// State is read when it opens (openFor), so every item is enabled correctly.
AppMenu {
    id: menu
    property double episodeId: 0
    property var st: ({})
    // From the player bar: the episode is the loaded one, so Play now/next
    // give way to a single Pause/Resume item.
    property bool forPlayer: false
    // Snapshot at open, so the label matches the state the menu was opened in.
    property bool wasPlaying: false
    readonly property bool loaded: episodeId !== 0 && episodeId === backend.playerEpisodeId

    function openFor(id, anchor, fromPlayer) {
        episodeId = id
        forPlayer = fromPlayer === true
        wasPlaying = backend.playerStatus === "playing"
        st = backend.episodeMenuState(id)
        if (anchor)
            popupAt(anchor)
        else
            popup()
    }

    AppMenuItem {
        text: menu.wasPlaying ? "Pause" : "Resume"
        visible: menu.forPlayer
        height: visible ? implicitHeight : 0
        enabled: menu.loaded
        onChosen: backend.togglePlayback()
    }
    AppMenuItem {
        text: "Play now"
        visible: !menu.forPlayer
        height: visible ? implicitHeight : 0
        enabled: !(menu.loaded && backend.playerStatus === "playing")
        onChosen: backend.playEpisode(menu.episodeId)
    }
    AppMenuItem {
        text: "Play next"
        visible: !menu.forPlayer
        height: visible ? implicitHeight : 0
        enabled: !menu.loaded && backend.nextQueuedId() !== menu.episodeId
        onChosen: backend.playNext(menu.episodeId)
    }
    AppMenuSeparator {}
    AppMenuItem {
        text: "Mark as played"
        enabled: menu.st.played === false
        onChosen: backend.markPlayed(menu.episodeId, true)
    }
    AppMenuItem {
        text: "Mark newer as played"
        visible: !menu.forPlayer
        height: visible ? implicitHeight : 0
        enabled: menu.st.newerUnplayed === true
        onChosen: backend.markNewerPlayed(menu.episodeId)
    }
    AppMenuItem {
        text: "Mark older as played"
        visible: !menu.forPlayer
        height: visible ? implicitHeight : 0
        enabled: menu.st.olderUnplayed === true
        onChosen: backend.markOlderPlayed(menu.episodeId)
    }
    AppMenuItem {
        text: "Mark as unplayed"
        enabled: menu.st.played === true
        onChosen: backend.markPlayed(menu.episodeId, false)
    }
    AppMenuSeparator {}
    AppMenuItem {
        text: "Add to queue"
        enabled: menu.st.queued === false
        onChosen: backend.addToQueue(menu.episodeId)
    }
    AppMenuItem {
        text: "Remove from queue"
        enabled: menu.st.queued === true
        onChosen: backend.removeFromQueue(menu.episodeId)
    }
    AppMenuSeparator {}
    AppMenuItem {
        text: "Mark all as played"
        enabled: menu.st.showId !== undefined
        onChosen: win.confirmMarkShow(menu.st.showId, menu.st.showTitle)
    }
}
