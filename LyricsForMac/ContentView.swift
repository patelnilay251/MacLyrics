//
//  ContentView.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import SwiftUI
import AppKit
import Combine

// MARK: - Data Models

struct LyricLine: Identifiable {
    let id = UUID()
    let time: Double
    let text: String
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
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            
            // Settings Panel (slides from right)
            if showSettings {
                HStack {
                    Spacer()
                    settingsPanel
                        .transition(.move(edge: .trailing))
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
            withAnimation(.easeInOut(duration: 0.2)) {
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
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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
                    withAnimation(.easeInOut(duration: 0.25)) {
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
                ForEach(getVisibleLines()) { item in
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
                        .animation(.linear(duration: 0.1), value: currentTime)
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
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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
        .opacity
            .combined(with: .offset(y: 20))
            .combined(with: blurTransition)
    }
    
    private var lineRemovalTransition: AnyTransition {
        .opacity
            .combined(with: .offset(y: -20))
            .combined(with: blurTransition)
    }
    
    private var blurTransition: AnyTransition {
        .modifier(
            active: BlurTransitionModifier(radius: 4),
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
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
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
            .scaleEffect(isCurrent ? 1.0 : 0.95)
            .blur(radius: isCurrent ? 0 : 2.5)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isCurrent)
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Make window floating and movable - transparent so only inner content is visible
        if let window = NSApplication.shared.windows.first {
            window.level = .floating
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.titlebarAppearsTransparent = true
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
