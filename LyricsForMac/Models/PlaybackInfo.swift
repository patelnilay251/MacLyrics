//
//  PlaybackInfo.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import Foundation

struct PlaybackInfo {
    let title: String
    let artist: String
    let position: Double
    let duration: Double
    let isPlaying: Bool
    let artworkURL: String?  // For Spotify
    let artworkData: String? // For Apple Music (base64 encoded)
}

