//
//  ContentView.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import SwiftUI
import AppKit
import Combine
import Carbon

// MARK: - Data Models

struct LyricLine: Identifiable {
    let id = UUID()
    let time: Double
    let text: String
}

extension AppDelegate: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        let adjustedFlag = isProgrammaticWindowChange ? hasUserAdjustedPosition : true
        recordGeometry(of: panel, userAdjusted: adjustedFlag, persist: true)
    }
    
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        let adjustedFlag = isProgrammaticWindowChange ? hasUserAdjustedPosition : true
        recordGeometry(of: panel, userAdjusted: adjustedFlag, persist: true)
    }
    
    func windowDidChangeScreen(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        recordGeometry(of: panel, userAdjusted: hasUserAdjustedPosition, persist: true)
    }
}

struct Song {
    let title: String
    let artist: String
    let lyrics: [LyricLine]
}

struct PlaybackInfo {
    let title: String
    let artist: String
    let position: Double
    let duration: Double
    let isPlaying: Bool
}

// MARK: - LRCLIB API Response

struct LRCLIBResponse: Codable {
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
    let instrumental: Bool?
    let syncedLyrics: String?
    let plainLyrics: String?
}

// MARK: - Lyrics Fetching

class LyricsService {
    static func fetchLyrics(title: String, artist: String, duration: Double) async -> [LyricLine]? {
        // Build URL with query parameters
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "duration", value: String(Int(duration)))
        ]
        
        guard let url = components.url else {
            print("❌ Invalid URL")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("QuickFlow v1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response")
                return nil
            }
            
            if httpResponse.statusCode == 404 {
                print("❌ Lyrics not found in LRCLIB database")
                return nil
            }
            
            guard httpResponse.statusCode == 200 else {
                print("❌ API returned status code: \(httpResponse.statusCode)")
                return nil
            }
            
            let result = try JSONDecoder().decode(LRCLIBResponse.self, from: data)
            
            // Check if instrumental
            if result.instrumental == true {
                print("🎼 Track is instrumental (no lyrics)")
                return []
            }
            
            // Try synced lyrics first (preferred)
            if let syncedLyrics = result.syncedLyrics {
                print("✅ Found synced lyrics!")
                return parseLRC(syncedLyrics)
            }
            
            // Fallback to plain lyrics (no timestamps)
            if let plainLyrics = result.plainLyrics {
                print("⚠️ Found plain lyrics only (no timestamps)")
                return parsePlainLyrics(plainLyrics)
            }
            
            print("❌ No lyrics available")
            return nil
            
        } catch {
            print("❌ Error fetching lyrics: \(error.localizedDescription)")
            return nil
        }
    }
    
    // Parse LRC format: [00:17.12] lyrics text
    static func parseLRC(_ lrcText: String) -> [LyricLine] {
        let lines = lrcText.components(separatedBy: .newlines)
        var parsed: [LyricLine] = []
        
        let pattern = #"\[(\d{2}):(\d{2})\.(\d{2})\]\s*(.*)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        
        for line in lines {
            let nsLine = line as NSString
            if let match = regex?.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) {
                let minutes = Int(nsLine.substring(with: match.range(at: 1))) ?? 0
                let seconds = Int(nsLine.substring(with: match.range(at: 2))) ?? 0
                let centiseconds = Int(nsLine.substring(with: match.range(at: 3))) ?? 0
                let text = nsLine.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces)
                
                let timestamp = Double(minutes * 60) + Double(seconds) + Double(centiseconds) / 100.0
                
                if !text.isEmpty {
                    parsed.append(LyricLine(time: timestamp, text: text))
                }
            }
        }
        
        return parsed.sorted { $0.time < $1.time }
    }
    
    // Parse plain lyrics (split by lines, estimate timestamps)
    static func parsePlainLyrics(_ plainText: String) -> [LyricLine] {
        let lines = plainText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        // Estimate 3 seconds per line (rough approximation)
        return lines.enumerated().map { index, text in
            LyricLine(time: Double(index) * 3.0, text: text)
        }
    }
}

private struct BlurTransitionModifier: ViewModifier {
    let radius: CGFloat
    
    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

private struct VisibleLyricLine: Identifiable {
    let line: LyricLine
    let index: Int
    
    var id: UUID { line.id }
}

// MARK: - Playback Detection Functions

func runAppleScript(_ script: String) -> String? {
    var error: NSDictionary?
    guard let scriptObject = NSAppleScript(source: script) else { return nil }
    let output = scriptObject.executeAndReturnError(&error)
    return error == nil ? output.stringValue : nil
}

func getSpotifyPlayback() -> PlaybackInfo? {
    let script = """
    tell application "Spotify"
        if it is running then
            if player state is playing or player state is paused then
                set trackName to name of current track
                set artistName to artist of current track
                set playerPos to player position as integer
                set trackDur to (duration of current track) / 1000 as integer
                set isPlaying to (player state is playing)
                return trackName & "||||" & artistName & "||||" & playerPos & "||||" & trackDur & "||||" & isPlaying
            end if
        end if
    end tell
    return ""
    """
    
    guard let result = runAppleScript(script), !result.isEmpty else { return nil }
    let parts = result.components(separatedBy: "||||")
    guard parts.count >= 5 else { return nil }
    
    return PlaybackInfo(
        title: parts[0],
        artist: parts[1],
        position: Double(parts[2]) ?? 0,
        duration: Double(parts[3]) ?? 0,
        isPlaying: parts[4] == "true"
    )
}

func getAppleMusicPlayback() -> PlaybackInfo? {
    let script = """
    tell application "Music"
        if it is running then
            if player state is playing or player state is paused then
                set trackName to name of current track
                set artistName to artist of current track
                set playerPos to player position as integer
                set trackDur to duration of current track as integer
                set isPlaying to (player state is playing)
                return trackName & "||||" & artistName & "||||" & playerPos & "||||" & trackDur & "||||" & isPlaying
            end if
        end if
    end tell
    return ""
    """
    
    guard let result = runAppleScript(script), !result.isEmpty else { return nil }
    let parts = result.components(separatedBy: "||||")
    guard parts.count >= 5 else { return nil }
    
    return PlaybackInfo(
        title: parts[0],
        artist: parts[1],
        position: Double(parts[2]) ?? 0,
        duration: Double(parts[3]) ?? 0,
        isPlaying: parts[4] == "true"
    )
}

func getCurrentPlayback() -> PlaybackInfo? {
    // Try Spotify first, then Apple Music
    return getSpotifyPlayback() ?? getAppleMusicPlayback()
}

// MARK: - Playback Control Functions

func controlSpotify(_ command: String) {
    let script = """
    tell application "Spotify"
        if it is running then
            \(command)
        end if
    end tell
    """
    _ = runAppleScript(script)
}

func controlAppleMusic(_ command: String) {
    let script = """
    tell application "Music"
        if it is running then
            \(command)
        end if
    end tell
    """
    _ = runAppleScript(script)
}

func playPause() {
    controlSpotify("playpause")
    controlAppleMusic("playpause")
}

func nextTrack() {
    controlSpotify("next track")
    controlAppleMusic("next track")
}

func previousTrack() {
    controlSpotify("previous track")
    controlAppleMusic("previous track")
}

// MARK: - Sample Data (Fallback)

let sampleSong = Song(
    title: "Ethereal Dreams",
    artist: "Luna Rivers",
    lyrics: [
        LyricLine(time: 0, text: "In the silence of the night"),
        LyricLine(time: 3, text: "I hear whispers in the wind"),
        LyricLine(time: 6, text: "Dancing shadows paint the walls"),
        LyricLine(time: 9, text: "As the moonlight filters in"),
        LyricLine(time: 13, text: "Every moment feels surreal"),
        LyricLine(time: 16, text: "Lost in echoes of your voice"),
        LyricLine(time: 19, text: "Time stands still when you're near"),
        LyricLine(time: 22, text: "In this dream I have no choice"),
        LyricLine(time: 26, text: "We're floating through the stars"),
        LyricLine(time: 29, text: "Where reality fades away"),
        LyricLine(time: 32, text: "In this ethereal embrace"),
        LyricLine(time: 35, text: "Forever we will stay"),
        LyricLine(time: 39, text: "Colors blend and intertwine"),
        LyricLine(time: 42, text: "Like watercolors in the rain"),
        LyricLine(time: 45, text: "Every heartbeat synchronizes"),
        LyricLine(time: 48, text: "To this sweet melodic chain")
    ]
)

// MARK: - Settings Model

class AppSettings: ObservableObject {
    @Published var windowOpacity: Double = 1.0
    @Published var cornerRadius: Double = 16.0
    @Published var backgroundColor: Color = Color(red: 245/255, green: 241/255, blue: 232/255)
    @Published var headerColor: Color = Color(red: 238/255, green: 234/255, blue: 222/255)
}

// MARK: - Color Extensions

extension Color {
    static let widgetBackground = Color(red: 245/255, green: 241/255, blue: 232/255)
    static let widgetHeader = Color(red: 238/255, green: 234/255, blue: 222/255)
    static let widgetBorder = Color.black
}

// MARK: - Main Content View

struct LyricsWidgetView: View {
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var songDuration: Double = 0
    @State private var currentLineIndex = 0
    @State private var isMinimized = false
    @State private var timer: Timer?
    @State private var song: Song
    @State private var lastTrackTitle: String = ""
    @State private var noPlaybackDetected = false
    @State private var isLoadingLyrics = false
    @State private var lyricsError: String? = nil
    @State private var isHovering = false
    @State private var showSettings = false
    @StateObject private var settings = AppSettings()
    
    init(song: Song) {
        _song = State(initialValue: song)
    }
    
    var body: some View {
        ZStack {
            // Main Content
            VStack(spacing: 0) {
                // Spacer for header area
                Color.clear
                    .frame(height: 60)
                
                // Lyrics Display
                lyricsView
                
                // Embedded Progress Bar
                progressBarView
            }
            
            // Floating Header (visible on hover)
            VStack {
                if isHovering {
                    headerView
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                                removal: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.95))
                            )
                        )
                }
                Spacer()
            }
            
            // Settings Panel (slides from right)
            if showSettings {
                HStack {
                    Spacer()
                    settingsPanel
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            )
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(settings.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: settings.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: settings.cornerRadius)
                .stroke(Color.black.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
        .opacity(settings.windowOpacity)
        .onHover { hovering in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isHovering = hovering
            }
        }
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack(spacing: 12) {
            // Song Icon
            Image(systemName: "music.note")
                .font(.system(size: 20))
                .foregroundColor(.black.opacity(0.7))
                .frame(width: 40, height: 40)
                .background(Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            
            // Song Info
            VStack(alignment: .leading, spacing: 2) {
                if noPlaybackDetected {
                    Text("No Playback")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                    Text("Play music to see lyrics")
                        .font(.system(size: 12))
                        .foregroundColor(.black.opacity(0.5))
                } else {
                    Text(song.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.system(size: 12))
                        .foregroundColor(.black.opacity(0.5))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Control Buttons
            HStack(spacing: 8) {
                // Settings Button
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showSettings.toggle()
                    }
                }) {
                    Image(systemName: showSettings ? "gearshape.fill" : "gearshape")
                        .font(.system(size: 16))
                        .foregroundColor(.black.opacity(0.6))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { _ in NSCursor.arrow.set() }
                
                // Minimize/Fullscreen Button
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isMinimized.toggle()
                    }
                }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 16))
                        .foregroundColor(.black.opacity(0.6))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { _ in NSCursor.arrow.set() }
                
                // Close Button
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16))
                        .foregroundColor(.black.opacity(0.6))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { _ in NSCursor.arrow.set() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            settings.headerColor.opacity(0.95)
                .blur(radius: 10)
        )
        .background(settings.headerColor)
    }
    
    
    // MARK: - Lyrics View
    
    private var lyricsView: some View {
        VStack(spacing: 0) {
            if isLoadingLyrics {
                // Loading state
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Fetching lyrics...")
                        .font(.system(size: 14))
                        .foregroundColor(.black.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = lyricsError {
                // Error state
                VStack(spacing: 12) {
                    Image(systemName: error == "Instrumental track" ? "music.note" : "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundColor(.black.opacity(0.2))
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundColor(.black.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if song.lyrics.isEmpty {
                // No lyrics state
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 36))
                        .foregroundColor(.black.opacity(0.2))
                    Text("No lyrics available")
                        .font(.system(size: 14))
                        .foregroundColor(.black.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Normal lyrics display
                Spacer()
                ForEach(Array(getVisibleLines().enumerated()), id: \.element.id) { offset, item in
                    LyricLineView(
                        line: item.line,
                        isCurrent: item.index == currentLineIndex,
                        isPast: item.index < currentLineIndex
                    )
                    .transition(
                        .asymmetric(
                            insertion: lineInsertionTransition,
                            removal: lineRemovalTransition
                        )
                    )
                    .animation(
                        .spring(response: 0.6, dampingFraction: 0.82)
                            .delay(Double(offset) * 0.05),
                        value: item.index == currentLineIndex
                    )
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
        .background(settings.backgroundColor)
    }
    
    // MARK: - Progress Bar View
    
    private var progressBarView: some View {
        VStack(spacing: 8) {
            // Progress Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .frame(height: 3)
                    
                    // Progress
                    Rectangle()
                        .fill(Color.black.opacity(0.8))
                        .frame(width: geometry.size.width * CGFloat(songDuration > 0 ? currentTime / songDuration : 0), height: 3)
                        .animation(.easeOut(duration: 0.2), value: currentTime)
                }
            }
            .frame(height: 3)
            
            // Time Display
            HStack {
                Text(formatTime(currentTime))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.black.opacity(0.4))
                
                Spacer()
                
                Text(formatTime(songDuration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.black.opacity(0.4))
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 16)
    }
    
    // MARK: - Settings Panel
    
    private var settingsPanel: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text("Settings")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showSettings = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14))
                            .foregroundColor(.black.opacity(0.6))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { _ in NSCursor.arrow.set() }
                }
            
            Divider()
                .background(Color.black.opacity(0.1))
            
            // Window Opacity
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Window Opacity")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.black.opacity(0.7))
                    Spacer()
                    Text("\(Int(settings.windowOpacity * 100))%")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.black.opacity(0.5))
                }
                
                Slider(value: $settings.windowOpacity, in: 0.3...1.0, step: 0.05)
                    .accentColor(.black)
            }
            
            // Corner Radius
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Corner Radius")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.black.opacity(0.7))
                    Spacer()
                    Text("\(Int(settings.cornerRadius))px")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.black.opacity(0.5))
                }
                
                Slider(value: $settings.cornerRadius, in: 0...40, step: 2)
                    .accentColor(.black)
            }
            
            Divider()
                .background(Color.black.opacity(0.1))
            
            // Background Color Presets
            VStack(alignment: .leading, spacing: 10) {
                Text("Background Color")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.black.opacity(0.7))
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 45))], spacing: 8) {
                    // Beige (default)
                    ColorPresetButton(
                        color: Color(red: 245/255, green: 241/255, blue: 232/255),
                        isSelected: settings.backgroundColor.isClose(to: Color(red: 245/255, green: 241/255, blue: 232/255))
                    ) {
                        settings.backgroundColor = Color(red: 245/255, green: 241/255, blue: 232/255)
                        settings.headerColor = Color(red: 238/255, green: 234/255, blue: 222/255)
                    }
                    
                    // White
                    ColorPresetButton(
                        color: .white,
                        isSelected: settings.backgroundColor.isClose(to: .white)
                    ) {
                        settings.backgroundColor = .white
                        settings.headerColor = Color(white: 0.95)
                    }
                    
                    // Light Gray
                    ColorPresetButton(
                        color: Color(white: 0.92),
                        isSelected: settings.backgroundColor.isClose(to: Color(white: 0.92))
                    ) {
                        settings.backgroundColor = Color(white: 0.92)
                        settings.headerColor = Color(white: 0.88)
                    }
                    
                    // Light Blue
                    ColorPresetButton(
                        color: Color(red: 230/255, green: 240/255, blue: 250/255),
                        isSelected: settings.backgroundColor.isClose(to: Color(red: 230/255, green: 240/255, blue: 250/255))
                    ) {
                        settings.backgroundColor = Color(red: 230/255, green: 240/255, blue: 250/255)
                        settings.headerColor = Color(red: 220/255, green: 235/255, blue: 245/255)
                    }
                    
                    // Light Pink
                    ColorPresetButton(
                        color: Color(red: 250/255, green: 235/255, blue: 240/255),
                        isSelected: settings.backgroundColor.isClose(to: Color(red: 250/255, green: 235/255, blue: 240/255))
                    ) {
                        settings.backgroundColor = Color(red: 250/255, green: 235/255, blue: 240/255)
                        settings.headerColor = Color(red: 245/255, green: 225/255, blue: 235/255)
                    }
                    
                    // Light Green
                    ColorPresetButton(
                        color: Color(red: 235/255, green: 245/255, blue: 235/255),
                        isSelected: settings.backgroundColor.isClose(to: Color(red: 235/255, green: 245/255, blue: 235/255))
                    ) {
                        settings.backgroundColor = Color(red: 235/255, green: 245/255, blue: 235/255)
                        settings.headerColor = Color(red: 225/255, green: 240/255, blue: 225/255)
                    }
                }
            }
            
            Spacer()
            
            // Reset Button
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    settings.windowOpacity = 1.0
                    settings.cornerRadius = 16.0
                    settings.backgroundColor = Color(red: 245/255, green: 241/255, blue: 232/255)
                    settings.headerColor = Color(red: 238/255, green: 234/255, blue: 222/255)
                }
            }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12))
                    Text("Reset to Defaults")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
                .foregroundColor(.black.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { _ in NSCursor.arrow.set() }
            }
            .padding(20)
            .frame(width: min(280, geometry.size.width * 0.45))
            .frame(maxHeight: .infinity)
            .background(settings.headerColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 15, x: -5, y: 0)
            .padding(.trailing, 8)
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
                .combined(with: .offset(y: 30))
                .combined(with: .scale(scale: 0.92))
                .combined(with: blurTransition),
            removal: .identity
        )
    }
    
    private var lineRemovalTransition: AnyTransition {
        .asymmetric(
            insertion: .identity,
            removal: .opacity
                .combined(with: .offset(y: -30))
                .combined(with: .scale(scale: 0.92))
                .combined(with: blurTransition)
        )
    }
    
    private var blurTransition: AnyTransition {
        .modifier(
            active: BlurTransitionModifier(radius: 8),
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
    
    
    private func startTimer() {
        timer?.invalidate()
        
        // Real playback monitoring - check every 300ms
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            updateFromRealPlayback()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateCurrentLine() {
        if let newIndex = song.lyrics.firstIndex(where: { line in
            let nextIndex = song.lyrics.firstIndex(where: { $0.time > line.time })
            let nextTime = nextIndex.map { song.lyrics[$0].time } ?? Double.infinity
            return currentTime >= line.time && currentTime < nextTime
        }) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                currentLineIndex = newIndex
            }
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Real Playback Integration
    
    private func updateFromRealPlayback() {
        guard let playback = getCurrentPlayback() else {
            // No playback detected
            noPlaybackDetected = true
            isPlaying = false
            return
        }
        
        noPlaybackDetected = false
        
        // Update play state, position, and duration
        isPlaying = playback.isPlaying
        currentTime = playback.position
        songDuration = playback.duration
        
        // Track change detection
        if playback.title != lastTrackTitle && !playback.title.isEmpty {
            lastTrackTitle = playback.title
            
            print("🎵 Track changed to: \(playback.title) by \(playback.artist)")
            
            // Reset current line index when track changes
            currentLineIndex = 0
            
            // Update song info and fetch lyrics
            isLoadingLyrics = true
            lyricsError = nil
            
            // Update song with empty lyrics while fetching
            song = Song(
                title: playback.title,
                artist: playback.artist,
                lyrics: []
            )
            
            // Fetch lyrics asynchronously
            Task {
                if let fetchedLyrics = await LyricsService.fetchLyrics(
                    title: playback.title,
                    artist: playback.artist,
                    duration: playback.duration
                ) {
                    // Successfully fetched lyrics
                    await MainActor.run {
                        if fetchedLyrics.isEmpty {
                            lyricsError = "Instrumental track"
                        }
                        song = Song(
                            title: playback.title,
                            artist: playback.artist,
                            lyrics: fetchedLyrics
                        )
                        isLoadingLyrics = false
                    }
                } else {
                    // Failed to fetch lyrics
                    await MainActor.run {
                        lyricsError = "Lyrics not found"
                        isLoadingLyrics = false
                    }
                }
            }
        }
        
        // Update current line based on real position
        updateCurrentLine()
    }
}

// MARK: - Color Preset Button

struct ColorPresetButton: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 8)
                .fill(color)
                .frame(width: 45, height: 45)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black.opacity(isSelected ? 0.4 : 0.15), lineWidth: isSelected ? 2 : 1)
                )
                .overlay(
                    isSelected ? Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black.opacity(0.6))
                    : nil
                )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { _ in NSCursor.arrow.set() }
    }
}

// MARK: - Color Extension

extension Color {
    func isClose(to otherColor: Color) -> Bool {
        // Simple comparison for color presets
        let selfComponents = self.cgColor?.components ?? []
        let otherComponents = otherColor.cgColor?.components ?? []
        
        guard selfComponents.count >= 3, otherComponents.count >= 3 else {
            return false
        }
        
        let threshold: CGFloat = 0.01
        return abs(selfComponents[0] - otherComponents[0]) < threshold &&
               abs(selfComponents[1] - otherComponents[1]) < threshold &&
               abs(selfComponents[2] - otherComponents[2]) < threshold
    }
    
    var cgColor: CGColor? {
        #if canImport(AppKit)
        return NSColor(self).cgColor
        #else
        return nil
        #endif
    }
}

// MARK: - Lyric Line View

struct LyricLineView: View {
    let line: LyricLine
    let isCurrent: Bool
    let isPast: Bool
    
    var body: some View {
        Text(line.text)
            .font(.system(
                size: isCurrent ? 32 : 20,
                weight: isCurrent ? .bold : .regular,
                design: .monospaced
            ))
            .foregroundColor(isCurrent ? .black : .black.opacity(isPast ? 0.3 : 0.25))
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, isCurrent ? 16 : 12)
            .padding(.horizontal, 20)
            .scaleEffect(isCurrent ? 1.05 : 0.92)
            .blur(radius: isCurrent ? 0 : 3.5)
            .shadow(
                color: isCurrent ? .black.opacity(0.08) : .clear,
                radius: isCurrent ? 12 : 0,
                x: 0,
                y: isCurrent ? 4 : 0
            )
            .animation(
                .spring(response: 0.55, dampingFraction: 0.78)
                    .speed(0.9),
                value: isCurrent
            )
            .animation(
                .easeInOut(duration: 0.4),
                value: isPast
            )
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var lyricsWindow: NSPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var lastKnownFrame: NSRect?
    private var lastKnownScreenFrame: NSRect?
    private var lastKnownScreenID: CGDirectDisplayID?
    private var hasUserAdjustedPosition: Bool = false
    private var isProgrammaticWindowChange = false
    private var storedFramesByDisplay: [CGDirectDisplayID: NSRect] = [:]
    private var storedScreenFramesByDisplay: [CGDirectDisplayID: NSRect] = [:]
    
    private let frameDefaultsKey = "LyricsWindowFrame"
    private let screenFrameDefaultsKey = "LyricsWindowScreenFrame"
    private let userAdjustedDefaultsKey = "LyricsWindowUserAdjusted"
    private let framesByDisplayDefaultsKey = "LyricsWindowFramesByDisplay"
    private let screenFramesByDisplayDefaultsKey = "LyricsWindowScreenFramesByDisplay"
    private let lastScreenIDDefaultsKey = "LyricsWindowLastScreenID"
    
    private static let hotKeySignature: OSType = 0x4C595243 // 'LYRC'
    private static let hotKeyCallback: EventHandlerUPP = { (_, eventRef, userData) -> OSStatus in
        guard
            let userData,
            let eventRef
        else {
            return noErr
        }
        
        let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
        delegate.handleHotKeyEvent(eventRef)
        return noErr
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        configureStatusItem()
        loadSavedWindowGeometry()
        registerGlobalHotKey()
        
        if let window = ensureLyricsWindow() {
            NSApp.activate(ignoringOtherApps: true)
            prepareWindowForDisplay(window)
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        unregisterGlobalHotKey()
        saveWindowGeometry()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    // MARK: - Status Item
    
    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem?.button else { return }
        
        button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Lyrics")
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
    
    private var statusMenu: NSMenu {
        let menu = NSMenu()
        
        let showItem = NSMenuItem(title: "Show Lyrics", action: #selector(showWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit Lyrics", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        
        return menu
    }
    
    @objc private func handleStatusItemClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            toggleWindowVisibility()
            return
        }
        
        let isRightClick = event.type == .rightMouseUp
        let isControlClick = event.modifierFlags.contains(.control) && event.type == .leftMouseUp
        
        if (isRightClick || isControlClick), let button = statusItem?.button {
            statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
            return
        }
        
        toggleWindowVisibility()
    }
    
    // MARK: - Window Management
    
    @discardableResult
    private func ensureLyricsWindow() -> NSPanel? {
        if let window = lyricsWindow {
            return window
        }
        
        let rootView = LyricsWidgetView(song: sampleSong)
            .frame(
                minWidth: 400,
                idealWidth: 600,
                maxWidth: 1000,
                minHeight: 400,
                idealHeight: 500,
                maxHeight: 800
            )
        
        let controller = NSHostingController(rootView: AnyView(rootView))
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .documentWindow
        panel.contentMinSize = NSSize(width: 400, height: 400)
        panel.contentMaxSize = NSSize(width: 1000, height: 800)
        panel.setContentSize(NSSize(width: 600, height: 500))
        
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        
        let containerView = NSView(frame: panel.contentView?.bounds ?? .zero)
        panel.contentView = containerView
        containerView.autoresizingMask = [.width, .height]
        containerView.wantsLayer = true
        
        let hostingView = controller.view
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        panel.delegate = self
        
        if let savedFrame = lastKnownFrame {
            performProgrammaticWindowChange {
                panel.setFrame(savedFrame, display: false)
            }
        } else if let screen = preferredScreen(for: panel) {
            let defaultFrame = defaultFrame(for: screen, windowSize: panel.frame.size)
            performProgrammaticWindowChange {
                panel.setFrame(defaultFrame, display: false)
            }
            recordGeometry(frame: defaultFrame, screen: screen, userAdjusted: false, persist: false)
        }
        
        hostingController = controller
        lyricsWindow = panel
        
        return panel
    }
    
    private func toggleWindowVisibility() {
        guard let window = ensureLyricsWindow() else { return }
        
        if window.isVisible {
            window.orderOut(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            prepareWindowForDisplay(window)
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    @objc private func showWindow() {
        guard let window = ensureLyricsWindow() else { return }
        NSApp.activate(ignoringOtherApps: true)
        prepareWindowForDisplay(window)
        window.makeKeyAndOrderFront(nil)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - Hot Keys
    
    private func registerGlobalHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(), AppDelegate.hotKeyCallback, 1, &eventType, selfPointer, &eventHandlerRef)
        
        let hotKeyID = EventHotKeyID(signature: AppDelegate.hotKeySignature, id: UInt32(1))
        let modifiers = UInt32(shiftKey) | UInt32(optionKey)
        
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_L), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            print("❌ Failed to register global hot key: \(status)")
        }
    }
    
    private func unregisterGlobalHotKey() {
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
    
    private func handleHotKeyEvent(_ eventRef: EventRef) {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        
        guard status == noErr else { return }
        guard hotKeyID.signature == AppDelegate.hotKeySignature else { return }
        
        toggleWindowVisibility()
    }
    
    private func prepareWindowForDisplay(_ window: NSPanel) {
        guard let targetScreen = preferredScreen(for: window) else { return }
        
        let windowSize = window.frame.size
        
        if !hasUserAdjustedPosition {
            let defaultFrame = defaultFrame(for: targetScreen, windowSize: windowSize)
            performProgrammaticWindowChange {
                window.setFrame(defaultFrame, display: false)
            }
            recordGeometry(frame: defaultFrame, screen: targetScreen, userAdjusted: false, persist: true)
            return
        }
        
        if let targetID = displayID(for: targetScreen),
           let storedFrameForScreen = storedFramesByDisplay[targetID] {
            let referenceScreenFrame = storedScreenFramesByDisplay[targetID] ?? targetScreen.visibleFrame
            let adjustedFrame = adaptFrame(storedFrameForScreen, from: referenceScreenFrame, to: targetScreen.visibleFrame, windowSize: windowSize)
            
            performProgrammaticWindowChange {
                window.setFrame(adjustedFrame, display: false)
            }
            recordGeometry(frame: adjustedFrame, screen: targetScreen, userAdjusted: true, persist: true)
            return
        }
        
        if let storedFrame = lastKnownFrame,
           let storedScreenFrame = lastKnownScreenFrame {
            let adjustedFrame: NSRect = adaptFrame(storedFrame, from: storedScreenFrame, to: targetScreen.visibleFrame, windowSize: windowSize)
            
            performProgrammaticWindowChange {
                window.setFrame(adjustedFrame, display: false)
            }
            recordGeometry(frame: adjustedFrame, screen: targetScreen, userAdjusted: true, persist: true)
        } else {
            let defaultFrame = defaultFrame(for: targetScreen, windowSize: windowSize)
            performProgrammaticWindowChange {
                window.setFrame(defaultFrame, display: false)
            }
            recordGeometry(frame: defaultFrame, screen: targetScreen, userAdjusted: false, persist: true)
        }
    }
    
    private func preferredScreen(for window: NSPanel? = nil) -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screen
        }
        if let windowScreen = window?.screen {
            return windowScreen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }
    
    private func defaultFrame(for screen: NSScreen, windowSize: NSSize) -> NSRect {
        let visible = screen.visibleFrame
        var origin = NSPoint(
            x: visible.midX - windowSize.width / 2,
            y: visible.maxY - windowSize.height - 80
        )
        
        origin.x = clamp(origin.x, min: visible.minX, max: visible.maxX - windowSize.width)
        origin.y = clamp(origin.y, min: visible.minY, max: visible.maxY - windowSize.height)
        
        return NSRect(origin: origin, size: NSSize(width: min(windowSize.width, visible.width),
                                                   height: min(windowSize.height, visible.height)))
    }
    
    private func clampFrame(_ frame: NSRect, to visible: NSRect, windowSize: NSSize) -> NSRect {
        var size = NSSize(width: min(windowSize.width, visible.width), height: min(windowSize.height, visible.height))
        var origin = frame.origin
        
        origin.x = clamp(origin.x, min: visible.minX, max: visible.maxX - size.width)
        origin.y = clamp(origin.y, min: visible.minY, max: visible.maxY - size.height)
        
        return NSRect(origin: origin, size: size)
    }
    
    private func adaptFrame(_ frame: NSRect, from source: NSRect, to target: NSRect, windowSize: NSSize) -> NSRect {
        guard source.width > 0, source.height > 0 else {
            let origin = NSPoint(
                x: target.midX - windowSize.width / 2,
                y: target.midY - windowSize.height / 2
            )
            return clampFrame(NSRect(origin: origin, size: windowSize), to: target, windowSize: windowSize)
        }
        
        let centerXRatio = clamp((frame.midX - source.minX) / source.width, min: 0, max: 1)
        let centerYRatio = clamp((frame.midY - source.minY) / source.height, min: 0, max: 1)
        
        let newCenterX = target.minX + centerXRatio * target.width
        let newCenterY = target.minY + centerYRatio * target.height
        
        let origin = NSPoint(x: newCenterX - windowSize.width / 2,
                             y: newCenterY - windowSize.height / 2)
        
        return clampFrame(NSRect(origin: origin, size: windowSize), to: target, windowSize: windowSize)
    }
    
    private func recordGeometry(frame: NSRect, screen: NSScreen?, userAdjusted: Bool?, persist: Bool) {
        lastKnownFrame = frame
        
        let resolvedScreen = screen ?? screenContaining(frame: frame)
        if let screen = resolvedScreen {
            lastKnownScreenFrame = screen.visibleFrame
            lastKnownScreenID = displayID(for: screen)
        } else {
            lastKnownScreenFrame = nil
            lastKnownScreenID = nil
        }
        
        if let userAdjusted = userAdjusted, userAdjusted {
            hasUserAdjustedPosition = true
            if let screen = resolvedScreen,
               let screenID = displayID(for: screen) {
                storedFramesByDisplay[screenID] = frame
                storedScreenFramesByDisplay[screenID] = screen.visibleFrame
            }
        }
        
        if persist {
            saveWindowGeometry()
        }
    }
    
    private func screenContaining(frame: NSRect) -> NSScreen? {
        return NSScreen.screens.first(where: { frame.intersects($0.frame) })
    }
    
    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return CGDirectDisplayID(screenNumber.uint32Value)
        }
        return nil
    }
    
    private func recordGeometry(of window: NSPanel, userAdjusted: Bool?, persist: Bool) {
        recordGeometry(frame: window.frame, screen: window.screen, userAdjusted: userAdjusted, persist: persist)
    }
    
    private func loadSavedWindowGeometry() {
        let defaults = UserDefaults.standard
        if let frameString = defaults.string(forKey: frameDefaultsKey) {
            lastKnownFrame = NSRectFromString(frameString)
        }
        if let screenFrameString = defaults.string(forKey: screenFrameDefaultsKey) {
            lastKnownScreenFrame = NSRectFromString(screenFrameString)
        }
        if defaults.object(forKey: lastScreenIDDefaultsKey) != nil {
            lastKnownScreenID = CGDirectDisplayID(defaults.integer(forKey: lastScreenIDDefaultsKey))
        }
        if defaults.object(forKey: userAdjustedDefaultsKey) != nil {
            hasUserAdjustedPosition = defaults.bool(forKey: userAdjustedDefaultsKey)
        }
        if let framesDict = defaults.dictionary(forKey: framesByDisplayDefaultsKey) as? [String: String] {
            storedFramesByDisplay = framesDict.reduce(into: [:]) { result, element in
                if let idValue = UInt32(element.key) {
                    result[CGDirectDisplayID(idValue)] = NSRectFromString(element.value)
                }
            }
        }
        if let screenFramesDict = defaults.dictionary(forKey: screenFramesByDisplayDefaultsKey) as? [String: String] {
            storedScreenFramesByDisplay = screenFramesDict.reduce(into: [:]) { result, element in
                if let idValue = UInt32(element.key) {
                    result[CGDirectDisplayID(idValue)] = NSRectFromString(element.value)
                }
            }
        }
        if !storedFramesByDisplay.isEmpty {
            hasUserAdjustedPosition = true
        }
    }
    
    private func saveWindowGeometry() {
        let defaults = UserDefaults.standard
        if let frame = lastKnownFrame {
            defaults.set(NSStringFromRect(frame), forKey: frameDefaultsKey)
        } else {
            defaults.removeObject(forKey: frameDefaultsKey)
        }
        if let screenFrame = lastKnownScreenFrame {
            defaults.set(NSStringFromRect(screenFrame), forKey: screenFrameDefaultsKey)
        } else {
            defaults.removeObject(forKey: screenFrameDefaultsKey)
        }
        if let lastScreenID = lastKnownScreenID {
            defaults.set(Int(lastScreenID), forKey: lastScreenIDDefaultsKey)
        } else {
            defaults.removeObject(forKey: lastScreenIDDefaultsKey)
        }
        
        if storedFramesByDisplay.isEmpty {
            defaults.removeObject(forKey: framesByDisplayDefaultsKey)
        } else {
            let serializedFrames = storedFramesByDisplay.reduce(into: [String: String]()) { result, entry in
                result[String(entry.key)] = NSStringFromRect(entry.value)
            }
            defaults.set(serializedFrames, forKey: framesByDisplayDefaultsKey)
        }
        
        if storedScreenFramesByDisplay.isEmpty {
            defaults.removeObject(forKey: screenFramesByDisplayDefaultsKey)
        } else {
            let serializedScreens = storedScreenFramesByDisplay.reduce(into: [String: String]()) { result, entry in
                result[String(entry.key)] = NSStringFromRect(entry.value)
            }
            defaults.set(serializedScreens, forKey: screenFramesByDisplayDefaultsKey)
        }
        
        defaults.set(hasUserAdjustedPosition, forKey: userAdjustedDefaultsKey)
    }
    
    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        return Swift.max(min, Swift.min(max, value))
    }
    
    private func performProgrammaticWindowChange(_ work: () -> Void) {
        let previousState = isProgrammaticWindowChange
        isProgrammaticWindowChange = true
        defer { isProgrammaticWindowChange = previousState }
        work()
    }
}
