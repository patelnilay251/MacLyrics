//
//  Logger+Extensions.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import Foundation
import OSLog

extension Logger {
    // Route all logger instances to the disabled OSLog sink to silence logging globally.
    private static let disabledLogger = Logger(OSLog.disabled)

    static let lyrics = disabledLogger
    static let playback = disabledLogger
    static let artwork = disabledLogger
    static let hotkey = disabledLogger
}
