//
//  LyricsWidgetView.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import SwiftUI
import AppKit
import OSLog

struct LyricsWidgetView: View {
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var songDuration: Double = 0
    @State private var currentLineIndex = 0
    @State private var isMinimized = false
    @State private var playbackPollTimer: Timer?
    @State private var progressTimer: Timer?
    @State private var lastSyncedPosition: Double = 0
    @State private var lastSyncDate: Date?
    @State private var song: Song
    @State private var lastTrackTitle: String = ""
    @State private var noPlaybackDetected = false
    @State private var isLoadingLyrics = false
    @State private var lyricsError: String? = nil
    @State private var pendingSongTitle: String? = nil
    @State private var pendingSongArtist: String? = nil
    @State private var isHovering = false
    @State private var isPointerInside = false
    @State private var showSettings = false
    @State private var showArtworkBackdrop = false
    @State private var dominantColor: Color? = nil
    @State private var isPinned = false
    @State private var isResizing = false
    @State private var previousSize: CGSize = .zero
    @StateObject private var settings = AppSettings()
    @StateObject private var swipeHandler = BrowserSwipeHandler()
    @StateObject private var notificationHandler = PlaybackNotificationHandler()
    @Environment(\.colorScheme) private var colorScheme
    
    private let activePollInterval: TimeInterval = 5.0
    private let idlePollInterval: TimeInterval = 12.0
    private let progressTickInterval: TimeInterval = 0.5
    
    init(song: Song) {
        _song = State(initialValue: song)
    }
    
    private var theme: ThemePalette {
        settings.palette(for: colorScheme)
    }
    
    private var effectiveWindowOpacity: Double {
        // Dim the entire window more when no playback is detected
        let base = settings.windowOpacity
        return noPlaybackDetected ? base * 0.55 : base
    }

    private var windowFocusBlurRadius: CGFloat {
        noPlaybackDetected ? 3.0 : 0.0
    }
    
    private var focusTransitionAnimation: Animation {
        .easeInOut(duration: 0.65)
    }
    
    private var borderColor: Color {
        theme.border
    }
    
    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.45) : Color.black.opacity(0.15)
    }
    
    private var dividerColor: Color {
        theme.border.opacity(0.8)
    }
    
    private var cacheSummary: String {
        let stats = settings.cacheStats
        guard stats.entries > 0 else { return "Empty" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        let sizeString = formatter.string(fromByteCount: Int64(stats.diskBytes))
        return "\(stats.entries) · \(sizeString)"
    }
    
    private var hasCacheContent: Bool {
        settings.cacheStats.entries > 0 || settings.cacheStats.diskBytes > 0
    }
    
    private func uiFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        Font.system(size: size, weight: weight, design: design)
    }
    
    var body: some View {
        GeometryReader { proxy in
            let metrics = ResponsiveMetrics(
                size: proxy.size,
                fontScale: settings.fontScale,
                isMinimized: isMinimized
            )
            
            // Detect resize
            let currentSize = proxy.size
            
            ZStack {
                // Artwork backdrop (behind everything)
                if showArtworkBackdrop, let artwork = song.artwork {
                    artworkBackdropView(artwork: artwork, metrics: metrics)
                        .id("backdrop-\(song.id)")
                        .zIndex(0)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
                
                // Main content fills entire window
                lyricsView(metrics: metrics, isResizing: isResizing)
                    .id("lyrics-\(song.id)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(1)
            }
            .ignoresSafeArea(.all) // Extend content into title bar area
            .overlay(alignment: .top) {
                // Header floats on top
                headerView(metrics: metrics, isResizing: isResizing)
                    .opacity(isHovering || isPinned ? 1.0 : 0.0)
                    .offset(y: isHovering || isPinned ? 0 : -20)
                    .allowsHitTesting(isHovering || isPinned) // Don't block hover when hidden
                    .animation(.spring(response: 0.4, dampingFraction: 0.88, blendDuration: 0.1), value: isHovering)
                    .animation(.spring(response: 0.4, dampingFraction: 0.88, blendDuration: 0.1), value: isPinned)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle()) // Ensure entire ZStack area is hoverable
            // Fixed border rendering: single background modifier with rounded rectangle + stroke
            .background(
                RoundedRectangle(cornerRadius: settings.cornerRadius)
                    .fill(showArtworkBackdrop ? Color.clear : theme.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: settings.cornerRadius)
                            .stroke(borderColor, lineWidth: 0.5)
                    )
            )
            // Clip to rounded corners to prevent sharp edges during resize
            .clipShape(RoundedRectangle(cornerRadius: settings.cornerRadius))
            // Optimized shadow: reduced radius during resize, use layer effect if available
            .shadow(
                color: shadowColor,
                radius: isResizing ? 12 : 18,
                x: 0,
                y: isResizing ? 6 : 10
            )
            .blur(radius: windowFocusBlurRadius)
            .opacity(effectiveWindowOpacity)
            .animation(focusTransitionAnimation, value: noPlaybackDetected)
            .onHover { hovering in
                isPointerInside = hovering
                if isPinned {
                    // When pinned, always show
                    isHovering = true
                } else if !isResizing {
                    // Update hover state with animation
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.88, blendDuration: 0.1)) {
                        isHovering = hovering || showSettings
                    }
                }
            }
            .onChange(of: currentSize) { oldSize, newSize in
                if oldSize != .zero && oldSize != newSize {
                    isResizing = true
                    // Reset resize state after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        isResizing = false
                    }
                }
                previousSize = newSize
            }
            .onChange(of: song.artwork, initial: false) { _, newArtwork in
                if let artwork = newArtwork {
                    extractDominantColor(from: artwork)
                    // Show backdrop by default when artwork is available
                    if !showArtworkBackdrop {
                        let animation = isResizing ? nil : Animation.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.15)
                        withAnimation(animation) {
                            showArtworkBackdrop = true
                        }
                    }
                }
            }
            .animation(isResizing ? nil : .spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.15), value: song.artwork)
        .onChange(of: showSettings, initial: false) { _, newValue in
            if !isPinned && !isResizing {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.88, blendDuration: 0.1)) {
                    isHovering = newValue || isPointerInside
                }
            }
        }
            .onAppear {
                // Start notification-based track change detection (instant response, zero CPU when idle)
                notificationHandler.startListening {
                    // Immediately update when track changes
                    updateFromRealPlayback(forceResync: true)
                }
                
                // Prime state and let the playback update schedule polling cadence
                updateFromRealPlayback(forceResync: true)
                
                Task { await refreshCacheStats() }
                // Show backdrop by default if artwork is available
                if song.artwork != nil {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85, blendDuration: 0.1)) {
                    showArtworkBackdrop = true
                }
            }
            swipeHandler.configure(
                onPrevious: { previousTrack() },
                onNext: { nextTrack() }
            )
            swipeHandler.start()
        }
        .onDisappear {
            stopPollingTimer()
            stopProgressTimer()
            notificationHandler.stopListening()
            swipeHandler.stop()
        }
    }
    }
    
    // MARK: - Header View
    
    @ViewBuilder
    private func headerView(metrics: ResponsiveMetrics, isResizing: Bool) -> some View {
        let buttonSide: CGFloat = metrics.isCompactWidth ? 30 : 34
        VStack(spacing: 0) {
            // Top row: Artwork, Title/Artist, Controls
            HStack(spacing: metrics.isCompactWidth ? 10 : 14) {
                // Artwork with circular progress ring and gestures
                Group {
                    if let artwork = song.artwork {
                        artworkWithProgressRing(artwork: artwork, size: buttonSide, metrics: metrics, isResizing: isResizing)
                    } else {
                        Image(systemName: "music.note")
                            .font(uiFont(size: metrics.headerIconSize))
                            .foregroundColor(theme.iconColor)
                            .frame(width: buttonSide, height: buttonSide)
                            .background(theme.controlSurface.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                
                VStack(alignment: .leading, spacing: metrics.isCompactWidth ? 1 : 2) {
                    // When no playback is detected, avoid showing "No Playback" text;
                    // keep the header quiet and only show real track metadata when available.
                        Text(song.title)
                            .font(uiFont(size: metrics.headerTitleSize, weight: .semibold))
                            .foregroundColor(theme.primaryText)
                            .lineLimit(1)
                            .id("title-\(song.id)")
                            .transition(.opacity.combined(with: .offset(y: -5)))
                        Text(song.artist)
                            .font(uiFont(size: metrics.headerSubtitleSize))
                            .foregroundColor(theme.mutedText(0.5))
                            .lineLimit(1)
                            .id("artist-\(song.id)")
                            .transition(.opacity.combined(with: .offset(y: -5)))
                }
                .animation(isResizing ? nil : .spring(response: 0.5, dampingFraction: 0.85, blendDuration: 0.1), value: song.id)
                .animation(isResizing ? nil : .spring(response: 0.5, dampingFraction: 0.85, blendDuration: 0.1), value: noPlaybackDetected)
                
                Spacer()
                
                HStack(spacing: metrics.isCompactWidth ? 6 : 8) {
                    settingsButton(metrics: metrics, isResizing: isResizing)
                    
                    controlButton(
                        systemImage: isPinned ? "pin.fill" : "pin",
                        size: metrics.headerButtonSize
                    ) {
                        let animation = isResizing ? nil : Animation.spring(response: 0.4, dampingFraction: 0.88, blendDuration: 0.1)
                        withAnimation(animation) {
                            isPinned.toggle()
                            if isPinned {
                                // When pinning, ensure bars are visible
                                isHovering = true
                            } else {
                                // When unpinning, restore hover state
                                isHovering = isPointerInside || showSettings
                            }
                        }
                    }
                    
                    controlButton(systemImage: "xmark", size: metrics.headerButtonSize) {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
            .padding(.horizontal, metrics.headerHorizontalPadding)
            .padding(.top, metrics.headerVerticalPadding)
            .padding(.bottom, metrics.isCompactWidth ? 8 : 10)
            
            // Progress bar integrated into header
            /* Temporarily commented out for Figma design work
            if !noPlaybackDetected {
                VStack(spacing: metrics.isCompactWidth ? 4 : 6) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(theme.progressTrack)
                                .frame(height: metrics.progressHeight)
                            
                            Rectangle()
                                .fill(theme.accent.opacity(0.8))
                                .frame(
                                    width: geometry.size.width * CGFloat(songDuration > 0 ? currentTime / songDuration : 0),
                                    height: metrics.progressHeight
                                )
                                .animation(.interpolatingSpring(stiffness: 120, damping: 20), value: currentTime)
                        }
                    }
                    .frame(height: metrics.progressHeight)
                    .padding(.horizontal, metrics.headerHorizontalPadding)
                    
                    HStack {
                        Text(formatTime(currentTime))
                            .font(uiFont(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(theme.mutedText(0.5))
                        
                        Spacer()
                        
                        Text(formatTime(songDuration))
                            .font(uiFont(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(theme.mutedText(0.5))
                    }
                    .padding(.horizontal, metrics.headerHorizontalPadding)
                }
                .padding(.bottom, metrics.headerVerticalPadding)
                .opacity(isHovering || isPinned ? 1.0 : 0.0)
                .offset(y: isHovering || isPinned ? 0 : -10)
                .animation(.spring(response: 0.4, dampingFraction: 0.88, blendDuration: 0.1), value: isHovering)
                .animation(.spring(response: 0.4, dampingFraction: 0.88, blendDuration: 0.1), value: isPinned)
            }
            */
        }
        .frame(maxWidth: metrics.isWideWidth ? min(metrics.width * 0.75, 760) : .infinity)
        .frame(maxWidth: .infinity)
        .background(
            // Header background with rounded top corners - fully transparent
            UnevenRoundedRectangle(
                topLeadingRadius: settings.cornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: settings.cornerRadius
            )
            .fill(Color.clear)
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: settings.cornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: settings.cornerRadius
            )
        )
    }
    
    private func settingsButton(metrics: ResponsiveMetrics, isResizing: Bool) -> some View {
        Button(action: {
            let animation = isResizing ? nil : Animation.spring(response: 0.4, dampingFraction: 0.88, blendDuration: 0.1)
            withAnimation(animation) {
                showSettings.toggle()
            }
        }) {
            Image(systemName: showSettings ? "gearshape.fill" : "gearshape")
                .font(uiFont(size: metrics.headerButtonSize))
                .foregroundColor(theme.iconColor)
                .frame(width: metrics.headerButtonSize + 12, height: metrics.headerButtonSize + 12)
        }
        .buttonStyle(PlainButtonStyle())
        .focusable(false)
        .onHover { _ in NSCursor.arrow.set() }
        .popover(isPresented: $showSettings, arrowEdge: .top) {
            settingsPopoverContent(metrics: metrics)
        }
    }
    
    private func controlButton(systemImage: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(uiFont(size: size))
                .foregroundColor(theme.iconColor)
                .frame(width: size + 12, height: size + 12)
        }
        .buttonStyle(PlainButtonStyle())
        .focusable(false)
        .onHover { _ in NSCursor.arrow.set() }
    }
    
    // MARK: - Artwork with Progress Ring
    
    @ViewBuilder
    private func artworkWithProgressRing(artwork: NSImage, size: CGFloat, metrics: ResponsiveMetrics, isResizing: Bool) -> some View {
        let progress = songDuration > 0 ? currentTime / songDuration : 0.0
        let ringWidth: CGFloat = 2.5
        
        ZStack {
            // Background ring (track)
            Circle()
                .stroke(theme.progressTrack, lineWidth: ringWidth)
                .frame(width: size, height: size)
            
            // Progress ring (animated)
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    Color.white,
                    style: StrokeStyle(
                        lineWidth: ringWidth,
                        lineCap: .round
                    )
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90)) // Start from top
                .animation(.linear(duration: 0.2), value: progress)
            
            // Artwork image
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size - ringWidth * 2, height: size - ringWidth * 2)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(theme.border.opacity(0.15), lineWidth: 0.5)
                )
                .overlay(
                    Circle()
                        .fill(Color.black.opacity(isPlaying ? 0 : 0.2))
                )
                .overlay(
                    Group {
                        if !isPlaying && !noPlaybackDetected {
                            Image(systemName: "play.fill")
                                .font(uiFont(size: size * 0.3, weight: .bold))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                        }
                    }
                )
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onTapGesture {
            playPause()
        }
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.arrow.set()
            }
        }
        .id("artwork-\(song.id)")
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
    
    
    // MARK: - Lyrics View
    
    @ViewBuilder
    private func lyricsView(metrics: ResponsiveMetrics, isResizing: Bool) -> some View {
        ZStack {
            lyricsContent(metrics: metrics, isResizing: isResizing)
                .padding(.horizontal, metrics.contentHorizontalPadding)
            lyricsStatusOverlay(metrics: metrics)
        }
        .frame(maxWidth: metrics.isWideWidth ? min(metrics.width * 0.75, 760) : .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(isResizing ? nil : .spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.15), value: song.title)
        .animation(isResizing ? nil : .spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.15), value: lyricsStatusKey)
    }

    @ViewBuilder
    private func lyricsContent(metrics: ResponsiveMetrics, isResizing: Bool) -> some View {
        VStack(spacing: metrics.lyricsVerticalSpacing) {
            Spacer(minLength: metrics.lyricsVerticalGutter)
            ForEach(Array(getVisibleLines().enumerated()), id: \.element.id) { offset, item in
                LyricLineView(
                    line: item.line,
                    isCurrent: item.index == currentLineIndex,
                    isPast: item.index < currentLineIndex,
                    theme: theme,
                    metrics: metrics
                )
                .id(item.index)
                .transition(
                    .asymmetric(
                        insertion: lineInsertionTransition,
                        removal: lineRemovalTransition
                    )
                )
            }
            .animation(isResizing ? nil : .spring(response: 0.5, dampingFraction: 0.85, blendDuration: 0.1), value: currentLineIndex)
            Spacer(minLength: metrics.lyricsVerticalGutter)
        }
    }

    private var lyricsStatusKey: String {
        if isLoadingLyrics { return "loading" }
        if let error = lyricsError { return "error-\(error)" }
        if song.lyrics.isEmpty {
            return noPlaybackDetected ? "empty-noplayback" : "empty"
        }
        return "ready"
    }
    
    @ViewBuilder
    private func lyricsStatusOverlay(metrics: ResponsiveMetrics) -> some View {
        if isLoadingLyrics {
            overlayContainer(metrics: metrics, blocksInteraction: true, hasCard: false) {
                loadingView(metrics: metrics)
            }
            .transition(statusOverlayTransition)
        } else if let error = lyricsError {
            overlayContainer(metrics: metrics, blocksInteraction: false) {
                placeholderView(
                    systemImage: error == "Instrumental track" ? "music.note" : "exclamationmark.triangle",
                    message: error,
                    metrics: metrics
                )
            }
            .transition(statusOverlayTransition)
        } else if song.lyrics.isEmpty {
            // Temporarily disable the "No lyrics available" overlay to avoid brief flashes
            // on startup or during track changes. Keeping the implementation below commented
            // for future reuse if needed.
            /*
            if noPlaybackDetected {
                // On startup / when no music app is active, keep the window softly visible
                // without showing "Play music to see lyrics" or "No lyrics" messaging.
                EmptyView()
            } else {
                let icon = "music.note.list"
                let message = "No lyrics available"
            overlayContainer(metrics: metrics, blocksInteraction: false) {
                placeholderView(systemImage: icon, message: message, metrics: metrics)
            }
            .transition(statusOverlayTransition)
            }
            */
            EmptyView()
        }
    }
    
    private var statusOverlayTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.98))
    }
    
    @ViewBuilder
    private func overlayContainer<Content: View>(
        metrics: ResponsiveMetrics,
        blocksInteraction: Bool,
        hasCard: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            theme.background.opacity(0.55)
                .blendMode(.multiply)
                .ignoresSafeArea()
            Group {
                if hasCard {
            content()
                .padding(.horizontal, metrics.isCompactWidth ? 18 : 24)
                .padding(.vertical, metrics.isCompactWidth ? 20 : 26)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: shadowColor.opacity(0.4), radius: 22, x: 0, y: 12)
                } else {
                    content()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(blocksInteraction)
    }
    
    // MARK: - Loading View
    
    @ViewBuilder
    private func loadingView(metrics: ResponsiveMetrics) -> some View {
        // Temporarily disabled spinning vinyl; keeping only dimmed overlay.
        // Original implementation kept here for reference:
        /*
        TimelineView(.periodic(from: .now, by: 1.0 / 60.0)) { context in
            let rotation = vinylRotationAngle(for: context.date)
            let pulseScale = vinylPulseScale(for: context.date)
            let shimmer = vinylShimmerOpacity(for: context.date)
            let vinylSize: CGFloat = metrics.isCompactWidth ? 96 : 118
            let labelSize = vinylSize * 0.34
            let spindleSize = vinylSize * 0.12
            
            ZStack {
                        Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                theme.accent.opacity(0.95),
                                theme.accent.opacity(0.45),
                                theme.background.opacity(0.75)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: vinylSize / 2
                        )
                    )
                    .shadow(color: theme.accent.opacity(0.35), radius: 14, x: 0, y: 8)
                
                Circle()
                    .stroke(theme.primaryText.opacity(0.18 + shimmer * 0.15), lineWidth: vinylSize * 0.08)
                    .blur(radius: 12)
                    .opacity(0.5)
                
                ForEach(0..<6, id: \.self) { groove in
                    let inset = CGFloat(groove) * (vinylSize * 0.08)
                    Circle()
                        .stroke(theme.primaryText.opacity(0.08), lineWidth: 0.8)
                        .frame(width: vinylSize - inset, height: vinylSize - inset)
                }
                
                Circle()
                    .fill(theme.header.opacity(0.92))
                    .frame(width: labelSize, height: labelSize)
                    .overlay(
                        Circle()
                            .stroke(theme.border.opacity(0.4), lineWidth: 1)
                    )
                    .overlay(
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.accent.opacity(0.85))
                                .frame(width: labelSize * 0.45, height: 3)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.accent.opacity(0.65))
                                .frame(width: labelSize * 0.3, height: 2)
                        }
                    )
                
                Circle()
                    .fill(theme.background.opacity(0.9))
                    .frame(width: spindleSize, height: spindleSize)
                    .overlay(
                        Circle()
                            .stroke(theme.primaryText.opacity(0.15), lineWidth: 1)
                    )
            }
            .frame(width: vinylSize, height: vinylSize)
            .rotationEffect(rotation)
            .scaleEffect(pulseScale)
            .shadow(color: shadowColor.opacity(0.45), radius: 24, x: 0, y: 14)
        }
        */
        EmptyView()
    }
    
    // MARK: - Loading Animation Helpers
    
    private func vinylRotationAngle(for date: Date) -> Angle {
        let speed = 90.0 // degrees per second
        let progress = date.timeIntervalSinceReferenceDate * speed
        return .degrees(progress.truncatingRemainder(dividingBy: 360))
    }
    
    private func vinylPulseScale(for date: Date) -> CGFloat {
        let time = date.timeIntervalSinceReferenceDate
        return 1.0 + CGFloat(sin(time * 2.2)) * 0.025
    }
    
    private func vinylShimmerOpacity(for date: Date) -> Double {
        let time = date.timeIntervalSinceReferenceDate
        return 0.4 + (sin(time * 1.6) + 1.0) * 0.25
    }
    
    private func sanitizedDisplayString(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
    
    private func placeholderView(systemImage: String, message: String, metrics: ResponsiveMetrics) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(uiFont(size: metrics.isCompactWidth ? 30 : 36))
                .foregroundColor(theme.mutedText(0.25))
            Text(message)
                .font(uiFont(size: metrics.isCompactWidth ? 13 : 14))
                .foregroundColor(theme.mutedText(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Progress Bar View (now integrated into header)
    
    // MARK: - Settings Popover
    
    @ViewBuilder
    private func settingsPopoverContent(metrics: ResponsiveMetrics) -> some View {
        let sectionSpacing = metrics.settingsSectionSpacing
        let rowSpacing = metrics.settingsRowSpacing
        let popoverWidth = max(300, min(metrics.settingsWidth, 340))
        
        let content = VStack(alignment: .leading, spacing: sectionSpacing) {
            // Header
            HStack(spacing: 8) {
                Text("Settings")
                    .font(uiFont(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(theme.primaryText)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.88, blendDuration: 0.1)) {
                        showSettings = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(uiFont(size: 11, weight: .medium))
                        .foregroundColor(theme.iconColor)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .focusable(false)
                .onHover { _ in NSCursor.arrow.set() }
            }
            .padding(.bottom, 2)
            
            // Settings Panel
            VStack(alignment: .leading, spacing: rowSpacing) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ThemePreset.allCases) { preset in
                            CompactThemeButton(
                                preset: preset,
                                isSelected: preset == settings.manualTheme,
                                highlightColor: theme.accent
                            ) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)) {
                                    settings.manualTheme = preset
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                
                SettingRow(
                    label: "Opacity",
                    value: "\(Int(settings.windowOpacity * 100))%",
                    theme: theme
                ) {
                    Slider(value: $settings.windowOpacity, in: 0.3...1.0, step: 0.05)
                        .accentColor(theme.accent)
                        .frame(height: 4)
                }
                
                /* Temporarily commented out - border radius slider removed
                SettingRow(
                    label: "Corner Radius",
                    value: "\(Int(settings.cornerRadius))px",
                    theme: theme
                ) {
                    Slider(value: $settings.cornerRadius, in: 0...40, step: 2)
                        .accentColor(theme.accent)
                        .frame(height: 4)
                }
                */
                
                SettingRow(
                    label: "Font Size",
                    value: "\(Int(settings.fontScale * 100))%",
                    theme: theme
                ) {
                    Slider(value: $settings.fontScale, in: 0.8...1.4, step: 0.05)
                        .accentColor(theme.accent)
                        .frame(height: 4)
                }
                
                SettingRow(
                    label: "Window Transition",
                    value: settings.presentationEffect.displayName,
                    theme: theme
                ) {
                    Picker("Window Transition", selection: $settings.presentationEffect) {
                        ForEach(WindowPresentationEffect.allCases) { effect in
                            Text(effect.displayName).tag(effect)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(MenuPickerStyle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            
            // Cache Section
            VStack(alignment: .leading, spacing: rowSpacing) {
                HStack {
                    Text("Cache")
                        .font(uiFont(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.mutedText(0.7))
                    Spacer()
                    Text(cacheSummary)
                        .font(uiFont(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.mutedText(0.5))
                }
                
                HStack(spacing: 8) {
                    Toggle("", isOn: $settings.cachingEnabled)
                        .toggleStyle(SwitchToggleStyle(tint: theme.accent))
                        .labelsHidden()
                        .onChange(of: settings.cachingEnabled, initial: false) { _, _ in
                            Task { await refreshCacheStats() }
                        }
                    
                    Text("Enable caching")
                        .font(uiFont(size: 11, design: .monospaced))
                        .foregroundColor(theme.primaryText)
                    
                    Spacer()
                    
                    if hasCacheContent {
                        Button(action: {
                            Task {
                                await LyricsCache.shared.clear()
                                await refreshCacheStats()
                            }
                        }) {
                            Image(systemName: "trash")
                                .font(uiFont(size: 10, weight: .medium))
                                .foregroundColor(theme.mutedText(0.6))
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .focusable(false)
                        .onHover { _ in NSCursor.arrow.set() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        
        ScrollView {
            content
                .padding(.vertical, metrics.settingsEdgePadding)
                .padding(.horizontal, metrics.settingsEdgePadding)
        }
        .frame(width: popoverWidth)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(theme.header.opacity(0.3))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor.opacity(0.4), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: shadowColor.opacity(0.3), radius: 16, x: 0, y: 8)
    }
    
    // MARK: - Setting Row Component
    
    @ViewBuilder
    private func SettingRow<Content: View>(
        label: String,
        value: String,
        theme: ThemePalette,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(uiFont(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.mutedText(0.7))
                Spacer()
                Text(value)
                    .font(uiFont(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.mutedText(0.5))
            }
            content()
        }
    }
    
    
    // MARK: - Playback Controls (Commented Out)
    /*
    private var controlsView: some View {
        VStack(spacing: 12) {
            // Playback buttons
            HStack(spacing: 12) {
                // Previous Button
                Button(action: {
                    previousTrack()
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.black)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(ScaleButtonStyle())
                
                // Play/Pause Button
                Button(action: {
                    playPause()
                }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                        .background(Color.black)
                }
                .buttonStyle(ScaleButtonStyle())
                
                // Next Button
                Button(action: {
                    nextTrack()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.black)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    */
    
    // MARK: - Helper Functions
    
    private var lineInsertionTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .offset(y: 20))
                .combined(with: blurTransition),
            removal: .opacity
        )
    }
    
    private var lineRemovalTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity,
            removal: .opacity
                .combined(with: .offset(y: -20))
                .combined(with: blurTransition)
        )
    }
    
    private var blurTransition: AnyTransition {
        .modifier(
            active: BlurTransitionModifier(radius: 6),
            identity: BlurTransitionModifier(radius: 0)
        )
    }
    
    private func getVisibleLines() -> [VisibleLyricLine] {
        // Guard against empty lyrics
        guard !song.lyrics.isEmpty else { return [] }
        
        // Ensure currentLineIndex is within bounds
        let safeCurrentIndex = min(currentLineIndex, song.lyrics.count - 1)
        
        let startIndex = max(0, safeCurrentIndex - 1)
        let endIndex = min(song.lyrics.count, safeCurrentIndex + 3)
        
        // Additional safety check to ensure startIndex <= endIndex
        guard startIndex < endIndex else { return [] }
        
        return song.lyrics[startIndex..<endIndex].enumerated().map { offset, line in
            VisibleLyricLine(line: line, index: startIndex + offset)
        }
    }
    
    
    private func startPollingTimer(interval: TimeInterval) {
        // Avoid rebuilding the timer if the cadence matches
        if let timer = playbackPollTimer, abs(timer.timeInterval - interval) < 0.001 {
            return
        }
        
        stopPollingTimer()
        
        playbackPollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            updateFromRealPlayback()
        }
        // Add timer to common run loop modes to prevent stuttering during scrolling/interaction
        if let timer = playbackPollTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }
    
    private func stopPollingTimer() {
        playbackPollTimer?.invalidate()
        playbackPollTimer = nil
    }
    
    private func startProgressTimer() {
        guard progressTimer == nil else { return }
        
        progressTimer = Timer.scheduledTimer(withTimeInterval: progressTickInterval, repeats: true) { _ in
            guard isPlaying, let syncDate = lastSyncDate else { return }
            
            let elapsed = Date().timeIntervalSince(syncDate)
            let projectedTime = min(songDuration, lastSyncedPosition + elapsed)
            
            if currentTime != projectedTime {
                currentTime = projectedTime
                updateCurrentLine()
            }
        }
        
        if let progressTimer = progressTimer {
            RunLoop.current.add(progressTimer, forMode: .common)
        }
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    private func refreshCacheStats() async {
        let stats = await LyricsCache.shared.currentStats()
        await MainActor.run {
            settings.cacheStats = stats
        }
    }
    
    private func updateCurrentLine() {
        // Optimized O(n) algorithm instead of O(n²)
        // Start from the end and find the first line where currentTime >= line.time
        guard !song.lyrics.isEmpty else { return }
        
        var newIndex = 0
        for i in stride(from: song.lyrics.count - 1, through: 0, by: -1) {
            if currentTime >= song.lyrics[i].time {
                newIndex = i
                break
            }
        }
        
        if newIndex != currentLineIndex {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85, blendDuration: 0.1)) {
                currentLineIndex = newIndex
            }
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Artwork Backdrop
    
    @ViewBuilder
    private func artworkBackdropView(artwork: NSImage, metrics: ResponsiveMetrics) -> some View {
        GeometryReader { geometry in
            ZStack {
                // Blurred artwork background - optimized blur and edge handling
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    // Extend beyond bounds to prevent edge artifacts
                    .frame(
                        width: geometry.size.width + 100,
                        height: geometry.size.height + 100
                    )
                    .blur(radius: 28) // Reduced from 40 for better performance
                    .scaleEffect(1.15) // Increased slightly for better edge coverage
                    .offset(x: 0, y: 0) // Center the extended image
                    .clipped()
                
                // Color overlay
                if let dominantColor = dominantColor {
                    dominantColor
                        .opacity(0.6)
                        .blendMode(.overlay)
                } else {
                    Color.black.opacity(0.3)
                }
                
                // Gradient overlay for better text readability
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.2),
                        Color.clear,
                        Color.clear,
                        Color.black.opacity(0.2)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped() // Ensure content doesn't overflow
        }
        .onAppear {
            extractDominantColor(from: artwork)
        }
    }
    
    private func extractDominantColor(from image: NSImage) {
        Task {
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return
            }
            
            // Resize image for faster processing
            let width = min(100, cgImage.width)
            let height = min(100, cgImage.height)
            
            guard let resizedCGImage = resizeCGImage(cgImage, width: width, height: height) else {
                return
            }
            
            // Extract pixel data
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bytesPerPixel = 4
            let bytesPerRow = bytesPerPixel * width
            let bitsPerComponent = 8
            
            var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
            
            guard let context = CGContext(
                data: &pixelData,
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else {
                return
            }
            
            context.draw(resizedCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            // Calculate average color
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var count: CGFloat = 0
            
            for i in stride(from: 0, to: pixelData.count, by: bytesPerPixel) {
                let red = CGFloat(pixelData[i]) / 255.0
                let green = CGFloat(pixelData[i + 1]) / 255.0
                let blue = CGFloat(pixelData[i + 2]) / 255.0
                
                // Skip very dark or very light pixels
                let brightness = (red + green + blue) / 3.0
                if brightness > 0.1 && brightness < 0.9 {
                    r += red
                    g += green
                    b += blue
                    count += 1
                }
            }
            
            guard count > 0 else { return }
            
            r /= count
            g /= count
            b /= count
            
            // Enhance saturation slightly
            let saturationBoost: CGFloat = 1.2
            let maxComponent = max(r, g, b)
            if maxComponent > 0 {
                r = min(1.0, r * saturationBoost)
                g = min(1.0, g * saturationBoost)
                b = min(1.0, b * saturationBoost)
            }
            
            await MainActor.run {
                dominantColor = Color(red: Double(r), green: Double(g), blue: Double(b))
            }
        }
    }
    
    private func resizeCGImage(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        
        context?.interpolationQuality = .low
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return context?.makeImage()
    }
    
    // MARK: - Artwork Loading
    
    private func loadArtwork(from playback: PlaybackInfo) async -> NSImage? {
        // Check cache first
        if let cached = ArtworkCache.shared.get(title: playback.title, artist: playback.artist) {
            return cached
        }
        
        // Try Apple Music artwork data
        if let artworkData = playback.artworkData, !artworkData.isEmpty {
            if let image = convertAppleMusicArtwork(artworkData) {
                ArtworkCache.shared.set(image, title: playback.title, artist: playback.artist)
                return image
            }
        }
        
        // Try Spotify artwork URL
        if let artworkURL = playback.artworkURL, !artworkURL.isEmpty,
           let url = URL(string: artworkURL) {
            if let image = await downloadArtwork(from: url) {
                ArtworkCache.shared.set(image, title: playback.title, artist: playback.artist)
                return image
            }
        }
        
        return nil
    }
    
    private func convertAppleMusicArtwork(_ filePath: String) -> NSImage? {
        // AppleScript saves artwork to a temporary file and returns the path
        // Clean up the path (remove "Macintosh HD:" prefix if present, handle file://)
        var cleanPath = filePath
            .replacingOccurrences(of: "Macintosh HD:", with: "")
            .replacingOccurrences(of: "file://", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove trailing colon if present
        if cleanPath.hasSuffix(":") {
            cleanPath = String(cleanPath.dropLast())
        }
        
        // Try to load the image from the file path
        if let image = NSImage(contentsOfFile: cleanPath) {
            // Clean up the temporary file after loading
            try? FileManager.default.removeItem(atPath: cleanPath)
            return image
        }
        
        return nil
    }
    
    private func downloadArtwork(from url: URL) async -> NSImage? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return NSImage(data: data)
        } catch {
            Logger.artwork.error("Failed to download artwork: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Real Playback Integration
    
    private func updateFromRealPlayback(forceResync: Bool = false) {
        guard let playback = getCurrentPlayback() else {
            // No playback detected
            if !noPlaybackDetected {
                noPlaybackDetected = true
            }
            if isPlaying {
                isPlaying = false
            }
            lastSyncDate = nil
            lastSyncedPosition = 0
            stopProgressTimer()
            startPollingTimer(interval: idlePollInterval)
            return
        }
        
        if noPlaybackDetected {
            noPlaybackDetected = false
        }
        
        lastSyncDate = Date()
        lastSyncedPosition = playback.position
        
        // Conditional updates to avoid unnecessary view re-renders
        if isPlaying != playback.isPlaying || forceResync {
            isPlaying = playback.isPlaying
        }
        if currentTime != playback.position || forceResync {
            currentTime = playback.position
        }
        if songDuration != playback.duration || forceResync {
            songDuration = playback.duration
        }
        
        // Track change detection
        if playback.title != lastTrackTitle && !playback.title.isEmpty {
            lastTrackTitle = playback.title
            
            Logger.playback.info("Track changed to: \(playback.title) by \(playback.artist)")
            
            // Reset current line index when track changes
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.15)) {
                currentLineIndex = 0
            }
            
            // Update song info and fetch lyrics
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.15)) {
                isLoadingLyrics = true
                lyricsError = nil
                pendingSongTitle = playback.title
                pendingSongArtist = playback.artist
            }
            
            // Load artwork asynchronously
            Task {
                let artwork = await loadArtwork(from: playback)
                
                // Fetch lyrics asynchronously
                let fetchedLyrics = await LyricsService.fetchLyrics(
                    title: playback.title,
                    artist: playback.artist,
                    duration: playback.duration
                )
                
                await MainActor.run {
                    // Smooth transition when song changes
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.15)) {
                        if let lyrics = fetchedLyrics {
                            if lyrics.isEmpty {
                                lyricsError = "Instrumental track"
                            } else {
                                lyricsError = nil
                            }
                            song = Song(
                                title: playback.title,
                                artist: playback.artist,
                                lyrics: lyrics,
                                artwork: artwork
                            )
                        } else {
                            lyricsError = "Lyrics not found"
                            song = Song(
                                title: playback.title,
                                artist: playback.artist,
                                lyrics: [],
                                artwork: artwork
                            )
                        }
                        isLoadingLyrics = false
                        pendingSongTitle = nil
                        pendingSongArtist = nil
                    }
                }
                await refreshCacheStats()
            }
        }
        
        // Update current line based on real position
        updateCurrentLine()
        
        // Keep polling at a slower cadence and rely on local timer for smooth progress
        if playback.isPlaying {
            startProgressTimer()
        } else {
            stopProgressTimer()
        }
        let targetInterval = playback.isPlaying ? activePollInterval : idlePollInterval
        startPollingTimer(interval: targetInterval)
    }
}
