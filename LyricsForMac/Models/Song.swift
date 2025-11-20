//
//  Song.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import AppKit

struct Song: Identifiable {
    let id: String
    let title: String
    let artist: String
    let lyrics: [LyricLine]
    let artwork: NSImage?
    
    init(title: String, artist: String, lyrics: [LyricLine], artwork: NSImage? = nil) {
        self.id = "\(title)|\(artist)"
        self.title = title
        self.artist = artist
        self.lyrics = lyrics
        self.artwork = artwork
    }
}

