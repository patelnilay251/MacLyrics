//
//  LyricLineView.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import SwiftUI

struct LyricLineView: View {
    let line: LyricLine
    let isCurrent: Bool
    let isPast: Bool
    let theme: ThemePalette
    let metrics: ResponsiveMetrics
    
    var body: some View {
        let baseFontSize = metrics.lyricCurrentSize
        let layoutScale = max(metrics.lyricCurrentScale, 0.0001)
        let secondaryScale = metrics.lyricSecondaryScale
        let secondaryFontSize = metrics.lyricSecondarySize
        let baseFontSizeSafe = max(baseFontSize, 0.0001)
        let secondaryTargetScale = (secondaryFontSize * secondaryScale) / baseFontSizeSafe
        let resolvedScale = isCurrent ? layoutScale : secondaryTargetScale
        let lockedTextWidth = metrics.lockedLyricTextWidth
        let containerWidth = metrics.lockedLyricContainerWidth
        let lineContainerWidth: CGFloat? = containerWidth > 0 ? containerWidth : nil
        let textLayoutWidth: CGFloat? = lockedTextWidth > 0 ? lockedTextWidth / layoutScale : nil
        Text(line.text)
            .font(
                .system(
                    size: baseFontSize,
                    weight: .medium,
                    design: .monospaced
                )
            )
            .foregroundColor(isCurrent ? theme.primaryText : theme.primaryText.opacity(isPast ? 0.3 : 0.25))
            .multilineTextAlignment(.center)
            .allowsTightening(false)
            .tracking(0)
            .kerning(0)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: textLayoutWidth, alignment: .center)
            .padding(.vertical, metrics.lyricVerticalPadding)
            .padding(.horizontal, metrics.lyricHorizontalPadding)
            .scaleEffect(resolvedScale)
            .blur(radius: isCurrent ? 0 : metrics.lyricBlurRadius)
            .shadow(
                color: isCurrent ? theme.primaryText.opacity(0.12) : .clear,
                radius: isCurrent ? 12 : 0,
                x: 0,
                y: isCurrent ? 4 : 0
            )
            .animation(
                .spring(response: 0.5, dampingFraction: 0.85, blendDuration: 0.1),
                value: isCurrent
            )
            .animation(
                .spring(response: 0.45, dampingFraction: 0.9, blendDuration: 0.1),
                value: isPast
            )
            .transaction { transaction in
                // Smooth font size transitions
                if transaction.animation != nil {
                    transaction.animation = .spring(response: 0.5, dampingFraction: 0.85, blendDuration: 0.1)
                }
            }
            .frame(width: lineContainerWidth)
            .frame(maxWidth: .infinity)
    }
}

