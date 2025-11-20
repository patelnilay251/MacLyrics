//
//  PlaybackControl.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import Foundation

func controlSpotify(_ command: String) {
    let script = """
    tell application "Spotify"
        if it is running then
            \(command)
        end if
    end tell
    """
    _ = runAppleScript(script)
}

func controlAppleMusic(_ command: String) {
    let script = """
    tell application "Music"
        if it is running then
            \(command)
        end if
    end tell
    """
    _ = runAppleScript(script)
}

func playPause() {
    controlSpotify("playpause")
    controlAppleMusic("playpause")
}

func nextTrack() {
    controlSpotify("next track")
    controlAppleMusic("next track")
}

func previousTrack() {
    controlSpotify("previous track")
    controlAppleMusic("previous track")
}

