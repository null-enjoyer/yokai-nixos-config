pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Singleton {
    id: root
    readonly property var players: Mpris.players.values
    property string selectedPlayer: ""
    readonly property var player: players.find(item => item.dbusName === selectedPlayer)
        ?? players.find(item => item.isPlaying) ?? players[0] ?? null
    readonly property int playerIndex: player ? players.indexOf(player) : -1

    function selectNextPlayer() {
        if (players.length < 2) return;
        selectedPlayer = players[(playerIndex + 1) % players.length].dbusName;
    }
    function togglePlayback() {
        const current = player;
        if (!current) return;
        if (current.isPlaying) {
            if (current.canPause) current.pause();
        } else if (current.canPlay) current.play();
    }
    function formatTime(seconds) {
        const value = Math.max(0, Math.floor(Number(seconds) || 0));
        const minutes = Math.floor(value / 60);
        return minutes + ":" + String(value % 60).padStart(2, "0");
    }
}
