//
//  VisibleLyricLine.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import Foundation

struct VisibleLyricLine: Identifiable, Equatable {
    let line: LyricLine
    let index: Int
    
    var id: UUID { line.id }
}

