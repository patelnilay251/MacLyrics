//
//  LRCLIBResponse.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import Foundation

struct LRCLIBResponse: Codable {
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
    let instrumental: Bool?
    let syncedLyrics: String?
    let plainLyrics: String?
}

