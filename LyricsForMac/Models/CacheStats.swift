//
//  CacheStats.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import Foundation

struct CacheStats {
    static let empty = CacheStats(entries: 0, diskBytes: 0)
    let entries: Int
    let diskBytes: UInt64
}

