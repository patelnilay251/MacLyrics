//
//  PlaybackDetection.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import Foundation

// Cached AppleScript objects for better performance (avoiding recompilation)
private let spotifyScript: NSAppleScript? = {
    let script = """
    tell application "Spotify"
        if it is running then
            if player state is playing or player state is paused then
                set trackName to name of current track
                set artistName to artist of current track
                set playerPos to player position as integer
                set trackDur to (duration of current track) / 1000 as integer
                set isPlaying to (player state is playing)
                try
                    set artworkURL to artwork url of current track
                on error
                    set artworkURL to ""
                end try
                return trackName & "||||" & artistName & "||||" & playerPos & "||||" & trackDur & "||||" & isPlaying & "||||" & artworkURL
            end if
        end if
    end tell
    return ""
    """
    return NSAppleScript(source: script)
}()

private let appleMusicScript: NSAppleScript? = {
    let script = """
    tell application "Music"
        if it is running then
            if player state is playing or player state is paused then
                set trackName to name of current track
                set artistName to artist of current track
                set playerPos to player position as integer
                set trackDur to duration of current track as integer
                set isPlaying to (player state is playing)
                set hasArtwork to "false"
                try
                    if exists artwork 1 of current track then
                        set hasArtwork to "true"
                    end if
                on error
                    set hasArtwork to "false"
                end try
                return trackName & "||||" & artistName & "||||" & playerPos & "||||" & trackDur & "||||" & isPlaying & "||||" & hasArtwork
            end if
        end if
    end tell
    return ""
    """
    return NSAppleScript(source: script)
}()

// Separate script to fetch Apple Music artwork on demand (only when track changes)
private let appleMusicArtworkScript: NSAppleScript? = {
    let script = """
    tell application "Music"
        if it is running then
            if player state is playing or player state is paused then
                set artworkPath to ""
                try
                    if exists artwork 1 of current track then
                        set artworkPath to (path to temporary items folder as string) & "lyrics_artwork_" & (random number from 1000 to 9999) & ".jpg"
                        set artworkFile to open for access file artworkPath with write permission
                        write (data of artwork 1 of current track) to artworkFile
                        close access artworkFile
                        return artworkPath
                    end if
                on error
                    return ""
                end try
            end if
        end if
    end tell
    return ""
    """
    return NSAppleScript(source: script)
}()

func runAppleScript(_ script: String) -> String? {
    var error: NSDictionary?
    guard let scriptObject = NSAppleScript(source: script) else { return nil }
    let output = scriptObject.executeAndReturnError(&error)
    return error == nil ? output.stringValue : nil
}

func getSpotifyPlayback() -> PlaybackInfo? {
    var error: NSDictionary?
    guard let script = spotifyScript else { return nil }
    guard let result = script.executeAndReturnError(&error).stringValue, !result.isEmpty, error == nil else { return nil }
    
    let parts = result.components(separatedBy: "||||")
    guard parts.count >= 5 else { return nil }
    
    let artworkURL = parts.count >= 6 && !parts[5].isEmpty ? parts[5] : nil
    
    return PlaybackInfo(
        title: parts[0],
        artist: parts[1],
        position: Double(parts[2]) ?? 0,
        duration: Double(parts[3]) ?? 0,
        isPlaying: parts[4] == "true",
        artworkURL: artworkURL,
        artworkData: nil
    )
}

func getAppleMusicPlayback() -> PlaybackInfo? {
    var error: NSDictionary?
    guard let script = appleMusicScript else { return nil }
    guard let result = script.executeAndReturnError(&error).stringValue, !result.isEmpty, error == nil else { return nil }
    
    let parts = result.components(separatedBy: "||||")
    guard parts.count >= 5 else { return nil }
    
    // parts[5] is now a boolean flag ("true"/"false") indicating artwork existence
    // We don't fetch artwork data here anymore - it's fetched on demand
    
    return PlaybackInfo(
        title: parts[0],
        artist: parts[1],
        position: Double(parts[2]) ?? 0,
        duration: Double(parts[3]) ?? 0,
        isPlaying: parts[4] == "true",
        artworkURL: nil,
        artworkData: nil
    )
}

// Fetch Apple Music artwork on demand (called only when track changes)
func getAppleMusicArtwork() -> String? {
    var error: NSDictionary?
    guard let script = appleMusicArtworkScript else { return nil }
    guard let result = script.executeAndReturnError(&error).stringValue, !result.isEmpty, error == nil else { return nil }
    return result
}

func getCurrentPlayback() -> PlaybackInfo? {
    // Try Spotify first, then Apple Music
    return getSpotifyPlayback() ?? getAppleMusicPlayback()
}

