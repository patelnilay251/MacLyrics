//
//  ThemePreset.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import SwiftUI

enum ThemePreset: String, CaseIterable, Identifiable {
    case desert
    case glacier
    case coral
    case midnight
    case forest
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .desert: return "Desert Sand"
        case .glacier: return "Glacier"
        case .coral: return "Coral Bloom"
        case .midnight: return "Midnight"
        case .forest: return "Forest Night"
        }
    }
    
    var palette: ThemePalette {
        switch self {
        case .desert:
            return ThemePalette(
                background: Color(red: 245/255, green: 241/255, blue: 232/255),
                header: Color(red: 238/255, green: 234/255, blue: 222/255),
                primaryText: .black,
                secondaryText: Color.black.opacity(0.65),
                accent: Color(red: 96/255, green: 78/255, blue: 60/255),
                border: Color.black.opacity(0.16)
            )
        case .glacier:
            return ThemePalette(
                background: Color(red: 236/255, green: 244/255, blue: 252/255),
                header: Color(red: 224/255, green: 236/255, blue: 248/255),
                primaryText: .black,
                secondaryText: Color.black.opacity(0.62),
                accent: Color(red: 50/255, green: 96/255, blue: 182/255),
                border: Color.black.opacity(0.12)
            )
        case .coral:
            return ThemePalette(
                background: Color(red: 255/255, green: 240/255, blue: 239/255),
                header: Color(red: 255/255, green: 226/255, blue: 224/255),
                primaryText: .black,
                secondaryText: Color.black.opacity(0.6),
                accent: Color(red: 204/255, green: 78/255, blue: 92/255),
                border: Color.black.opacity(0.14)
            )
        case .midnight:
            return ThemePalette(
                background: Color(red: 24/255, green: 25/255, blue: 30/255),
                header: Color(red: 36/255, green: 37/255, blue: 45/255),
                primaryText: .white,
                secondaryText: Color.white.opacity(0.75),
                accent: Color(red: 138/255, green: 180/255, blue: 255/255),
                border: Color.white.opacity(0.18)
            )
        case .forest:
            return ThemePalette(
                background: Color(red: 26/255, green: 37/255, blue: 32/255),
                header: Color(red: 34/255, green: 48/255, blue: 42/255),
                primaryText: .white,
                secondaryText: Color.white.opacity(0.78),
                accent: Color(red: 120/255, green: 200/255, blue: 160/255),
                border: Color.white.opacity(0.16)
            )
        }
    }
}

