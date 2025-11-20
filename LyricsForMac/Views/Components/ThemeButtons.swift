//
//  ThemeButtons.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import SwiftUI
import AppKit

struct ThemePresetButton: View {
    let preset: ThemePreset
    let isSelected: Bool
    let highlightColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [preset.palette.background, preset.palette.header],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? highlightColor : preset.palette.border.opacity(0.8), lineWidth: isSelected ? 2 : 1)
                    )
                    .overlay(
                        Group {
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(highlightColor)
                                    .padding(6)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            }
                        }
                    )
                
                Text(preset.displayName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(preset.palette.primaryText.opacity(isSelected ? 0.85 : 0.7))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(preset.palette.background.opacity(0.15))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .focusable(false)
        .onHover { _ in NSCursor.arrow.set() }
    }
}

struct CompactThemeButton: View {
    let preset: ThemePreset
    let isSelected: Bool
    let highlightColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [preset.palette.background, preset.palette.header],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? highlightColor : preset.palette.border.opacity(0.6), lineWidth: isSelected ? 1.5 : 0.5)
                    )
                    .overlay(
                        Group {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(highlightColor)
                            }
                        }
                    )
                
                Text(preset.displayName)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(preset.palette.primaryText.opacity(isSelected ? 0.9 : 0.6))
                    .lineLimit(1)
            }
            .frame(width: 36)
        }
        .buttonStyle(PlainButtonStyle())
        .focusable(false)
        .onHover { _ in NSCursor.arrow.set() }
    }
}

