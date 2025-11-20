//
//  ThemeMode.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import Foundation

enum ThemeMode: String, CaseIterable, Identifiable {
    case matchSystem
    case manual
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .matchSystem: return "Match System"
        case .manual: return "Manual"
        }
    }
}

