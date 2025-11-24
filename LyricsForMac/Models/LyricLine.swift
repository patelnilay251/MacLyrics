//
//  LyricLine.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import Foundation

struct LyricLine: Identifiable, Codable, Equatable {
    let id: UUID
    let time: Double
    let text: String
    
    nonisolated init(id: UUID = UUID(), time: Double, text: String) {
        self.id = id
        self.time = time
        self.text = text
    }
}
