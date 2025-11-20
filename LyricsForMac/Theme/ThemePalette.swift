//
//  ThemePalette.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import SwiftUI

struct ThemePalette {
    let background: Color
    let header: Color
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
    let border: Color
    
    func mutedText(_ opacity: Double) -> Color {
        primaryText.opacity(opacity)
    }
    
    var iconColor: Color {
        primaryText.opacity(0.7)
    }
    
    var controlSurface: Color {
        header.opacity(0.8)
    }
    
    var progressTrack: Color {
        primaryText.opacity(0.12)
    }
    
    var progressFill: Color {
        accent
    }
}

