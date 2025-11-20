//
//  ResponsiveMetrics.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import SwiftUI
import AppKit

struct ResponsiveMetrics {
    let size: CGSize
    let fontScale: Double
    let isMinimized: Bool
    
    var width: CGFloat { size.width }
    var height: CGFloat { size.height }
    
    private var screenScale: CGFloat {
        let factor = NSScreen.main?.backingScaleFactor ?? 2.0
        return factor > 0 ? factor : 2.0
    }
    
    private func pixelAligned(_ value: CGFloat) -> CGFloat {
        let scale = screenScale
        return (value * scale).rounded(.down) / scale
    }
    
    // Enhanced breakpoints with smooth transitions
    var isVeryCompactWidth: Bool { width < 400 }
    var isCompactWidth: Bool { width < 520 }
    var isMediumWidth: Bool { width >= 520 && width <= 720 }
    var isWideWidth: Bool { width > 960 }
    var isShortHeight: Bool { height < 560 }
    var isTallHeight: Bool { height > 700 }
    
    // Smooth interpolation helper
    private func interpolate(compact: CGFloat, medium: CGFloat, wide: CGFloat) -> CGFloat {
        if isVeryCompactWidth {
            return compact * 0.9
        } else if isCompactWidth {
            return compact
        } else if isMediumWidth {
            let ratio = (width - 520) / (720 - 520)
            return compact + (medium - compact) * ratio
        } else if isWideWidth {
            return wide
        } else {
            let ratio = min(1.0, (width - 720) / (960 - 720))
            return medium + (wide - medium) * ratio
        }
    }
    
    // Constrained font scale per breakpoint
    var effectiveFontScale: Double {
        let baseScale = fontScale
        if isVeryCompactWidth {
            return max(0.85, min(1.0, baseScale))
        } else if isCompactWidth {
            return max(0.85, min(1.1, baseScale))
        } else if isWideWidth {
            return max(0.9, min(1.4, baseScale))
        } else {
            return max(0.9, min(1.3, baseScale))
        }
    }
    
    var headerReservedHeight: CGFloat {
        // Don't reserve any space - header will overlay content
        return 0
    }
    
    var headerHeight: CGFloat {
        if isMinimized { return 48 }
        // Actual header height for overlay positioning
        return interpolate(compact: 56, medium: 60, wide: 64)
    }
    
    var headerHorizontalPadding: CGFloat {
        // Percentage-based with minimum
        max(12, width * 0.033)
    }
    
    var headerVerticalPadding: CGFloat {
        interpolate(compact: 12, medium: 14, wide: 16)
    }
    
    var headerIconSize: CGFloat {
        interpolate(compact: 16, medium: 18, wide: 20)
    }
    
    var headerButtonSize: CGFloat {
        interpolate(compact: 14, medium: 15, wide: 16)
    }
    
    var headerTitleSize: CGFloat {
        interpolate(compact: 13, medium: 14, wide: 15)
    }
    
    var headerSubtitleSize: CGFloat {
        interpolate(compact: 11, medium: 11.5, wide: 12)
    }
    
    var contentHorizontalPadding: CGFloat {
        if isMinimized { return 18 }
        // Percentage-based with breakpoint adjustments
        let basePadding = width * 0.04
        if isVeryCompactWidth {
            return max(20, basePadding)
        } else if isCompactWidth {
            return max(24, basePadding)
        } else if isWideWidth {
            return min(56, basePadding * 1.4)
        } else {
            return max(32, min(48, basePadding))
        }
    }
    
    var lyricsVerticalSpacing: CGFloat {
        // Scale based on available height
        let baseSpacing = interpolate(compact: 8, medium: 10, wide: 12)
        if isTallHeight {
            return baseSpacing * 1.2
        } else if isShortHeight {
            return baseSpacing * 0.9
        }
        return baseSpacing
    }
    
    var lyricsVerticalGutter: CGFloat {
        // Dynamic based on content height vs available space
        let baseGutter: CGFloat = isShortHeight ? 12 : 20
        if isTallHeight && !isShortHeight {
            return min(30, baseGutter * 1.3)
        }
        return baseGutter
    }
    
    var lyricCurrentSize: CGFloat {
        let base: CGFloat
        if isMinimized { base = 26 }
        else if isVeryCompactWidth { base = 26 }
        else if isCompactWidth { base = 28 }
        else if isWideWidth { base = 36 }
        else { base = 32 }
        return base * effectiveFontScale
    }
    
    var lyricSecondarySize: CGFloat {
        let base: CGFloat
        if isMinimized { base = 16 }
        else if isVeryCompactWidth { base = 16 }
        else if isCompactWidth { base = 18 }
        else { base = 20 }
        return base * effectiveFontScale
    }
    
    var lyricVerticalPadding: CGFloat {
        if isMinimized { return 10 }
        return interpolate(compact: 12, medium: 14, wide: 16)
    }
    
    var lyricHorizontalPadding: CGFloat {
        // Percentage-based
        max(12, width * 0.027)
    }
    
    private var lyricStackMaxWidth: CGFloat {
        if isWideWidth {
            return min(width * 0.75, 760)
        }
        return width
    }
    
    private var lyricSafetyBuffer: CGFloat { 6 }
    
    var lockedLyricContainerWidth: CGFloat {
        let paddedWidth = lyricStackMaxWidth - (contentHorizontalPadding * 2)
        let safeWidth = max(0, paddedWidth - lyricSafetyBuffer)
        return pixelAligned(safeWidth)
    }
    
    var lockedLyricTextWidth: CGFloat {
        let available = lockedLyricContainerWidth - (lyricHorizontalPadding * 2)
        return pixelAligned(max(0, available))
    }
    
    var lyricCurrentScale: CGFloat {
        isMinimized ? 1.03 : 1.05
    }
    
    var lyricSecondaryScale: CGFloat {
        isMinimized ? 0.96 : 0.92
    }
    
    var lyricBlurRadius: CGFloat {
        interpolate(compact: 2.5, medium: 3.0, wide: 3.5)
    }
    
    var progressHeight: CGFloat {
        interpolate(compact: 3, medium: 3.5, wide: 4)
    }
    
    var progressBottomPadding: CGFloat {
        if isShortHeight { return 12 }
        if isTallHeight { return 20 }
        return 18
    }
    
    var settingsWidth: CGFloat {
        // Relative to window width with constraints
        let relativeWidth = min(width * 0.4, 340)
        if width < 400 {
            return min(width * 0.9, 300)
        } else if width < 720 {
            return min(width * 0.9, 320)
        } else if width < 1024 {
            return 320
        }
        return max(320, relativeWidth)
    }
    
    var settingsShouldScroll: Bool {
        height < 600
    }
    
    var settingsSectionSpacing: CGFloat {
        interpolate(compact: 10, medium: 11, wide: 12)
    }
    
    var settingsControlSpacing: CGFloat {
        interpolate(compact: 8, medium: 9, wide: 10)
    }
    
    var settingsEdgePadding: CGFloat {
        interpolate(compact: 14, medium: 15, wide: 16)
    }
    
    var settingsRowSpacing: CGFloat {
        interpolate(compact: 6, medium: 7, wide: 8)
    }
}

