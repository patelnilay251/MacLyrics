//
//  Logger+Extensions.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import Foundation
import OSLog

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier ?? "com.quickflow.LyricsForMac"
    
    static let lyrics = Logger(subsystem: subsystem, category: "lyrics")
    static let playback = Logger(subsystem: subsystem, category: "playback")
    static let artwork = Logger(subsystem: subsystem, category: "artwork")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
}

