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
import CryptoKit
import QuartzCore
import OSLog

// MARK: - Logger

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier ?? "com.quickflow.LyricsForMac"
    
    static let lyrics = Logger(subsystem: subsystem, category: "lyrics")
    static let playback = Logger(subsystem: subsystem, category: "playback")
    static let artwork = Logger(subsystem: subsystem, category: "artwork")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
}

// MARK: - Data Models

struct LyricLine: Identifiable, Codable {
    let id: UUID
    let time: Double
    let text: String
    
    init(id: UUID = UUID(), time: Double, text: String) {
        self.id = id
        self.time = time
        self.text = text
    }
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

struct WindowPresentationAnimator {
    static func animate(window: NSWindow, effect: WindowPresentationEffect) {
        guard effect != .none else { return }
        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        guard let layer = contentView.layer else { return }
        layer.opacity = 1.0
        
        switch effect {
        case .scaleFade:
            performScaleFade(on: layer, in: contentView)
//        case .genie:
//            performGenie(on: layer, in: contentView)
        case .slide:
            performSlide(on: layer)
        case .layered:
            performLayered(on: layer)
        case .none:
            break
        }
    }
    
    static func dismiss(window: NSWindow, effect: WindowPresentationEffect, completion: @escaping () -> Void) {
        guard effect != .none else {
            completion()
            return
        }
        guard let contentView = window.contentView else {
            completion()
            return
        }
        contentView.wantsLayer = true
        guard let layer = contentView.layer else {
            completion()
            return
        }
        layer.removeAllAnimations()
        
        switch effect {
        case .scaleFade:
            performScaleFadeDismiss(on: layer, in: contentView, completion: completion)
//        case .genie:
//            performGenieDismiss(on: layer, in: contentView, completion: completion)
        case .slide:
            performSlideDismiss(on: layer, completion: completion)
        case .layered:
            performLayeredDismiss(on: layer, completion: completion)
        case .none:
            completion()
        }
    }
    
    private static func performScaleFade(on layer: CALayer, in view: NSView) {
        let duration: CFTimeInterval = 0.32
        let anchor = CGPoint(x: 0.5, y: 0.05)
        let originalAnchor = layer.anchorPoint
        let originalPosition = layer.position
        let newPosition = CGPoint(
            x: view.bounds.width * anchor.x,
            y: view.bounds.height * anchor.y
        )
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.anchorPoint = anchor
        layer.position = newPosition
        CATransaction.commit()
        
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)
        
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 0.8
        scaleAnimation.toValue = 1.0
        scaleAnimation.duration = duration
        scaleAnimation.timingFunction = timing
        
        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 0.0
        opacityAnimation.toValue = 1.0
        opacityAnimation.duration = duration
        opacityAnimation.timingFunction = timing
        
        let group = CAAnimationGroup()
        group.duration = duration
        group.timingFunction = timing
        group.animations = [scaleAnimation, opacityAnimation]
        layer.add(group, forKey: "windowScaleFade")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak layer] in
            guard let layer else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.anchorPoint = originalAnchor
            layer.position = originalPosition
            CATransaction.commit()
        }
    }
    
//    /* Genie Pull window transition temporarily disabled.
//    private static func performGenie(on layer: CALayer, in view: NSView) {
//        let duration: CFTimeInterval = 0.45
//        let bounds = view.bounds
//        let maskLayer = CAShapeLayer()
//        maskLayer.path = genieEndPath(for: bounds)
//        layer.mask = maskLayer
//        
//        let animation = CABasicAnimation(keyPath: "path")
//        animation.fromValue = genieStartPath(for: bounds)
//        animation.toValue = genieEndPath(for: bounds)
//        animation.duration = duration
//        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
//        animation.fillMode = .forwards
//        animation.isRemovedOnCompletion = false
//        maskLayer.add(animation, forKey: "geniePath")
//        
//        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
//        opacityAnimation.fromValue = 0.0
//        opacityAnimation.toValue = 1.0
//        opacityAnimation.duration = duration * 0.75
//        opacityAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
//        layer.add(opacityAnimation, forKey: "genieOpacity")
//        
//        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak layer] in
//            layer?.mask = nil
//        }
//    }
//    
//    private static func genieStartPath(for bounds: CGRect) -> CGPath {
//        let width = max(60.0, bounds.width * 0.2)
//        let height = max(80.0, bounds.height * 0.22)
//        let originX = bounds.midX - width / 2
//        let originY = bounds.height - height * 0.4
//        let rect = CGRect(x: originX, y: originY, width: width, height: height)
//        
//        let path = CGMutablePath()
//        let controlOffset = height * 0.9
//        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
//        path.addQuadCurve(
//            to: CGPoint(x: rect.maxX, y: rect.minY),
//            control: CGPoint(x: rect.midX, y: rect.minY - controlOffset)
//        )
//        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
//        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
//        path.closeSubpath()
//        return path
//    }
//    
//    private static func genieEndPath(for bounds: CGRect) -> CGPath {
//        let radius = min(24.0, min(bounds.width, bounds.height) * 0.12)
//        return CGPath(
//            roundedRect: bounds,
//            cornerWidth: radius,
//            cornerHeight: radius,
//            transform: nil
//        )
//    }
//    */
    
    private static func performSlide(on layer: CALayer) {
        let duration: CFTimeInterval = 0.3
        let translation = CABasicAnimation(keyPath: "transform.translation.y")
        translation.fromValue = -40.0
        translation.toValue = 0.0
        translation.duration = duration
        translation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.0
        opacity.toValue = 1.0
        opacity.duration = duration * 0.9
        opacity.timingFunction = CAMediaTimingFunction(name: .easeOut)
        
        layer.add(translation, forKey: "slideTranslation")
        layer.add(opacity, forKey: "slideOpacity")
    }
    
    private static func performLayered(on layer: CALayer) {
        let baseDuration: CFTimeInterval = 0.28
        
        let backgroundFade = CABasicAnimation(keyPath: "opacity")
        backgroundFade.fromValue = 0.0
        backgroundFade.toValue = 1.0
        backgroundFade.duration = baseDuration
        backgroundFade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.add(backgroundFade, forKey: "layeredBackgroundFade")
        
        guard let contentLayer = layer.sublayers?.first else { return }
        
        let contentGroup = CAAnimationGroup()
        contentGroup.beginTime = CACurrentMediaTime() + 0.05
        contentGroup.duration = 0.4
        contentGroup.timingFunction = CAMediaTimingFunction(name: .easeOut)
        
        let contentOpacity = CABasicAnimation(keyPath: "opacity")
        contentOpacity.fromValue = 0.0
        contentOpacity.toValue = 1.0
        
        let contentScale = CABasicAnimation(keyPath: "transform.scale")
        contentScale.fromValue = 0.95
        contentScale.toValue = 1.0
        
        contentGroup.animations = [contentOpacity, contentScale]
        contentLayer.add(contentGroup, forKey: "layeredContent")
    }
    
    private static func performScaleFadeDismiss(on layer: CALayer, in view: NSView, completion: @escaping () -> Void) {
        let duration: CFTimeInterval = 0.25
        let anchor = CGPoint(x: 0.5, y: 0.05)
        let originalAnchor = layer.anchorPoint
        let originalPosition = layer.position
        let newPosition = CGPoint(
            x: view.bounds.width * anchor.x,
            y: view.bounds.height * anchor.y
        )
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.anchorPoint = anchor
        layer.position = newPosition
        CATransaction.commit()
        
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)
        
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 1.0
        scaleAnimation.toValue = 0.82
        
        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 1.0
        opacityAnimation.toValue = 0.0
        
        let group = CAAnimationGroup()
        group.duration = duration
        group.timingFunction = timing
        group.animations = [scaleAnimation, opacityAnimation]
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        layer.add(group, forKey: "windowScaleFadeDismiss")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            completion()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.anchorPoint = originalAnchor
            layer.position = originalPosition
            layer.opacity = 1.0
            layer.removeAllAnimations()
            CATransaction.commit()
        }
    }
    
//    private static func performGenieDismiss(on layer: CALayer, in view: NSView, completion: @escaping () -> Void) {
//        let duration: CFTimeInterval = 0.4
//        let bounds = view.bounds
//        let maskLayer = CAShapeLayer()
//        maskLayer.path = genieStartPath(for: bounds)
//        layer.mask = maskLayer
//        
//        let animation = CABasicAnimation(keyPath: "path")
//        animation.fromValue = genieEndPath(for: bounds)
//        animation.toValue = genieStartPath(for: bounds)
//        animation.duration = duration
//        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
//        animation.fillMode = .forwards
//        animation.isRemovedOnCompletion = false
//        maskLayer.add(animation, forKey: "genieCollapse")
//        
//        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
//        opacityAnimation.fromValue = 1.0
//        opacityAnimation.toValue = 0.0
//        opacityAnimation.duration = duration * 0.9
//        opacityAnimation.timingFunction = CAMediaTimingFunction(name: .easeIn)
//        layer.add(opacityAnimation, forKey: "genieOpacityDismiss")
//        
//        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
//            completion()
//            layer.mask = nil
//            layer.opacity = 1.0
//            layer.removeAllAnimations()
//        }
//    }
    
    private static func performSlideDismiss(on layer: CALayer, completion: @escaping () -> Void) {
        let duration: CFTimeInterval = 0.22
        let translation = CABasicAnimation(keyPath: "transform.translation.y")
        translation.fromValue = 0.0
        translation.toValue = -30.0
        translation.duration = duration
        translation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        translation.fillMode = .forwards
        translation.isRemovedOnCompletion = false
        
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 1.0
        opacity.toValue = 0.0
        opacity.duration = duration
        opacity.timingFunction = CAMediaTimingFunction(name: .easeIn)
        opacity.fillMode = .forwards
        opacity.isRemovedOnCompletion = false
        
        layer.add(translation, forKey: "slideTranslationDismiss")
        layer.add(opacity, forKey: "slideOpacityDismiss")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            completion()
            layer.opacity = 1.0
            layer.removeAllAnimations()
        }
    }
    
    private static func performLayeredDismiss(on layer: CALayer, completion: @escaping () -> Void) {
        let duration: CFTimeInterval = 0.25
        let backgroundFade = CABasicAnimation(keyPath: "opacity")
        backgroundFade.fromValue = 1.0
        backgroundFade.toValue = 0.0
        backgroundFade.duration = duration
        backgroundFade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        backgroundFade.fillMode = .forwards
        backgroundFade.isRemovedOnCompletion = false
        layer.add(backgroundFade, forKey: "layeredBackgroundFadeDismiss")
        
        if let contentLayer = layer.sublayers?.first {
            let contentGroup = CAAnimationGroup()
            contentGroup.duration = duration
            contentGroup.timingFunction = CAMediaTimingFunction(name: .easeIn)
            
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 1.0
            opacity.toValue = 0.0
            
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1.0
            scale.toValue = 0.92
            
            contentGroup.animations = [opacity, scale]
            contentGroup.fillMode = .forwards
            contentGroup.isRemovedOnCompletion = false
            contentLayer.add(contentGroup, forKey: "layeredContentDismiss")
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            completion()
            layer.opacity = 1.0
            layer.removeAllAnimations()
            layer.sublayers?.forEach { $0.removeAllAnimations() }
        }
    }
}

struct Song: Identifiable {
    let id: String
    let title: String
    let artist: String
    let lyrics: [LyricLine]
    let artwork: NSImage?
    
    init(title: String, artist: String, lyrics: [LyricLine], artwork: NSImage? = nil) {
        self.id = "\(title)|\(artist)"
        self.title = title
        self.artist = artist
        self.lyrics = lyrics
        self.artwork = artwork
    }
}

struct PlaybackInfo {
    let title: String
    let artist: String
    let position: Double
    let duration: Double
    let isPlaying: Bool
    let artworkURL: String?  // For Spotify
    let artworkData: String? // For Apple Music (base64 encoded)
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
        if let cached = await LyricsCache.shared.cachedLyrics(title: title, artist: artist, duration: duration) {
            return cached
        }
        
        // Build URL with query parameters
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "duration", value: String(Int(duration)))
        ]
        
        guard let url = components.url else {
            Logger.lyrics.error("Invalid URL for lyrics request")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("QuickFlow v1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.lyrics.error("Invalid HTTP response")
                return nil
            }
            
            if httpResponse.statusCode == 404 {
                Logger.lyrics.info("Lyrics not found in LRCLIB database for \(title) by \(artist)")
                return nil
            }
            
            guard httpResponse.statusCode == 200 else {
                Logger.lyrics.error("API returned status code: \(httpResponse.statusCode)")
                return nil
            }
            
            let result = try JSONDecoder().decode(LRCLIBResponse.self, from: data)
            
            // Check if instrumental
            if result.instrumental == true {
                Logger.lyrics.info("Track is instrumental (no lyrics): \(title) by \(artist)")
                await LyricsCache.shared.store(lyrics: [], title: title, artist: artist, duration: duration)
                return []
            }
            
            // Try synced lyrics first (preferred)
            if let syncedLyrics = result.syncedLyrics {
                Logger.lyrics.info("Found synced lyrics for \(title) by \(artist)")
                let parsed = parseLRC(syncedLyrics)
                await LyricsCache.shared.store(lyrics: parsed, title: title, artist: artist, duration: duration)
                return parsed
            }
            
            // Fallback to plain lyrics (no timestamps)
            if let plainLyrics = result.plainLyrics {
                Logger.lyrics.info("Found plain lyrics (no timestamps) for \(title) by \(artist)")
                let parsed = parsePlainLyrics(plainLyrics)
                await LyricsCache.shared.store(lyrics: parsed, title: title, artist: artist, duration: duration)
                return parsed
            }
            
            Logger.lyrics.info("No lyrics available for \(title) by \(artist)")
            return nil
            
        } catch {
            Logger.lyrics.error("Error fetching lyrics: \(error.localizedDescription)")
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

struct CacheStats {
    static let empty = CacheStats(entries: 0, diskBytes: 0)
    let entries: Int
    let diskBytes: UInt64
}

actor LyricsCache {
    static let shared = LyricsCache()
    
    private let memoryCache: NSCache<NSString, CacheEntry>
    private let fileManager: FileManager
    private let cacheDirectory: URL
    private let maxDiskEntries = 200
    private var isEnabled: Bool
    private static let cachingEnabledKey = "LyricsCacheEnabled"
    
    private init() {
        let cache = NSCache<NSString, CacheEntry>()
        cache.countLimit = 150
        
        let fm = FileManager.default
        let baseURL = fm.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let directoryName = (Bundle.main.bundleIdentifier ?? "LyricsForMac") + ".lyrics"
        let directory = baseURL.appendingPathComponent(directoryName, isDirectory: true)
        
        if !fm.fileExists(atPath: directory.path) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        
        let storedValue = UserDefaults.standard.object(forKey: Self.cachingEnabledKey) as? Bool
        if storedValue == nil {
            UserDefaults.standard.set(true, forKey: Self.cachingEnabledKey)
        }
        let enabled = storedValue ?? true
        
        self.memoryCache = cache
        self.fileManager = fm
        self.cacheDirectory = directory
        self.isEnabled = enabled
    }
    
    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.cachingEnabledKey)
        if !enabled {
            memoryCache.removeAllObjects()
        }
    }
    
    func isCachingEnabled() -> Bool {
        isEnabled
    }
    
    func cachedLyrics(title: String, artist: String, duration: Double) -> [LyricLine]? {
        guard isEnabled else { return nil }
        let key = cacheKey(title: title, artist: artist, duration: duration)
        
        if let entry = memoryCache.object(forKey: key as NSString) {
            return entry.lyrics
        }
        
        let url = fileURL(forKey: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        
        do {
            let payload = try JSONDecoder().decode(CachePayload.self, from: data)
            memoryCache.setObject(CacheEntry(lyrics: payload.lyrics), forKey: key as NSString)
            return payload.lyrics
        } catch {
            try? fileManager.removeItem(at: url)
            return nil
        }
    }
    
    func store(lyrics: [LyricLine], title: String, artist: String, duration: Double) {
        guard isEnabled else { return }
        let key = cacheKey(title: title, artist: artist, duration: duration)
        memoryCache.setObject(CacheEntry(lyrics: lyrics), forKey: key as NSString)
        
        let payload = CachePayload(lyrics: lyrics, storedAt: Date())
        do {
            let data = try JSONEncoder().encode(payload)
            let url = fileURL(forKey: key)
            try data.write(to: url, options: .atomic)
            try pruneIfNeeded()
        } catch {
            // Ignore disk failures silently
        }
    }
    
    func clear() async {
        memoryCache.removeAllObjects()
        let urls = (try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in urls {
            try? fileManager.removeItem(at: url)
        }
    }
    
    func currentStats() -> CacheStats {
        let urls = (try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        var total: UInt64 = 0
        for url in urls {
            if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                total += UInt64(size)
            }
        }
        return CacheStats(entries: urls.count, diskBytes: total)
    }
    
    private func cacheKey(title: String, artist: String, duration: Double) -> String {
        let normalizedTitle = normalize(string: title)
        let normalizedArtist = normalize(string: artist)
        let roundedDuration = Int(duration.rounded())
        return "\(normalizedArtist)|\(normalizedTitle)|\(roundedDuration)"
    }
    
    private func normalize(string: String) -> String {
        string
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
    
    private func fileURL(forKey key: String) -> URL {
        cacheDirectory.appendingPathComponent(Self.hash(key)).appendingPathExtension("json")
    }
    
    private static func hash(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    private func pruneIfNeeded() throws {
        let urls = try fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        
        guard urls.count > maxDiskEntries else { return }
        
        let sorted = urls.compactMap { url -> (URL, Date) in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            return (url, values?.contentModificationDate ?? .distantPast)
        }.sorted { $0.1 < $1.1 }
        
        let excess = sorted.count - maxDiskEntries
        guard excess > 0 else { return }
        
        for index in 0..<excess {
            try? fileManager.removeItem(at: sorted[index].0)
        }
    }
    
    private final class CacheEntry: NSObject {
        let lyrics: [LyricLine]
        
        init(lyrics: [LyricLine]) {
            self.lyrics = lyrics
        }
    }
    
    private struct CachePayload: Codable {
        let lyrics: [LyricLine]
        let storedAt: Date
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

// MARK: - Playback Monitor (Precompiled AppleScripts)

/// Singleton that precompiles AppleScripts once at init to avoid the overhead of
/// creating and compiling new NSAppleScript objects on every polling cycle.
/// 
/// IMPORTANT: Artwork fetching is separated from playback polling to avoid
/// writing to disk on every 200ms poll. Artwork scripts are only executed
/// on track changes.
final class PlaybackMonitor {
    static let shared = PlaybackMonitor()
    
    /// Tracks which player was last active, to know which artwork script to call
    enum ActivePlayer {
        case spotify
        case appleMusic
        case none
    }
    
    private(set) var lastActivePlayer: ActivePlayer = .none
    
    // MARK: - Precompiled Scripts
    
    // Playback state scripts (lightweight, no disk I/O)
    private let spotifyPlaybackScript: NSAppleScript?
    private let appleMusicPlaybackScript: NSAppleScript?
    
    // Artwork scripts (only called on track changes)
    private let spotifyArtworkScript: NSAppleScript?
    private let appleMusicArtworkScript: NSAppleScript?
    
    // Control scripts
    private let spotifyPlayPauseScript: NSAppleScript?
    private let spotifyNextScript: NSAppleScript?
    private let spotifyPreviousScript: NSAppleScript?
    private let appleMusicPlayPauseScript: NSAppleScript?
    private let appleMusicNextScript: NSAppleScript?
    private let appleMusicPreviousScript: NSAppleScript?
    
    private init() {
        // Spotify playback query (includes artwork URL since it's just a string, no disk I/O)
        let spotifySource = """
        tell application "Spotify"
            if it is running then
                if player state is playing or player state is paused then
                    set trackName to name of current track
                    set artistName to artist of current track
                    set playerPos to player position as integer
                    set trackDur to (duration of current track) / 1000 as integer
                    set isPlaying to (player state is playing)
                    try
                        set artworkURL to artwork url of current track
                    on error
                        set artworkURL to ""
                    end try
                    return trackName & "||||" & artistName & "||||" & playerPos & "||||" & trackDur & "||||" & isPlaying & "||||" & artworkURL
                end if
            end if
        end tell
        return ""
        """
        spotifyPlaybackScript = Self.compile(spotifySource)
        
        // Spotify doesn't need separate artwork script - URL is in playback response
        spotifyArtworkScript = nil
        
        // Apple Music playback query - LIGHTWEIGHT, NO ARTWORK (no disk I/O)
        let appleMusicSource = """
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
        appleMusicPlaybackScript = Self.compile(appleMusicSource)
        
        // Apple Music artwork fetch - ONLY called on track changes
        let appleMusicArtworkSource = """
        tell application "Music"
            if it is running then
                if player state is playing or player state is paused then
                    try
                        if exists artwork 1 of current track then
                            set artworkPath to (path to temporary items folder as string) & "lyrics_artwork_" & (random number from 1000 to 9999) & ".jpg"
                            set artworkFile to open for access file artworkPath with write permission
                            write (data of artwork 1 of current track) to artworkFile
                            close access artworkFile
                            return artworkPath
                        end if
                    on error
                        return ""
                    end try
                end if
            end if
        end tell
        return ""
        """
        appleMusicArtworkScript = Self.compile(appleMusicArtworkSource)
        
        // Spotify control scripts
        spotifyPlayPauseScript = Self.compile("""
        tell application "Spotify"
            if it is running then playpause
        end tell
        """)
        
        spotifyNextScript = Self.compile("""
        tell application "Spotify"
            if it is running then next track
        end tell
        """)
        
        spotifyPreviousScript = Self.compile("""
        tell application "Spotify"
            if it is running then previous track
        end tell
        """)
        
        // Apple Music control scripts
        appleMusicPlayPauseScript = Self.compile("""
        tell application "Music"
            if it is running then playpause
        end tell
        """)
        
        appleMusicNextScript = Self.compile("""
        tell application "Music"
            if it is running then next track
        end tell
        """)
        
        appleMusicPreviousScript = Self.compile("""
        tell application "Music"
            if it is running then previous track
        end tell
        """)
        
        Logger.playback.info("PlaybackMonitor initialized with precompiled AppleScripts (artwork fetch separated)")
    }
    
    /// Compiles an AppleScript source string, returning nil on failure
    private static func compile(_ source: String) -> NSAppleScript? {
        guard let script = NSAppleScript(source: source) else {
            Logger.playback.error("Failed to create AppleScript from source")
            return nil
        }
        var error: NSDictionary?
        script.compileAndReturnError(&error)
        if let error = error {
            Logger.playback.error("Failed to compile AppleScript: \(error)")
            return nil
        }
        return script
    }
    
    /// Executes a precompiled script and returns the string result
    @discardableResult
    private func execute(_ script: NSAppleScript?) -> String? {
        guard let script = script else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return result.stringValue
    }
    
    // MARK: - Playback Detection (Lightweight, no disk I/O)
    
    func getSpotifyPlayback() -> PlaybackInfo? {
        guard let result = execute(spotifyPlaybackScript), !result.isEmpty else { return nil }
        lastActivePlayer = .spotify
        return parsePlaybackResult(result, isSpotify: true)
    }
    
    func getAppleMusicPlayback() -> PlaybackInfo? {
        guard let result = execute(appleMusicPlaybackScript), !result.isEmpty else { return nil }
        lastActivePlayer = .appleMusic
        return parsePlaybackResult(result, isSpotify: false)
    }
    
    func getCurrentPlayback() -> PlaybackInfo? {
        // Try Spotify first, then Apple Music
        if let spotify = getSpotifyPlayback() {
            return spotify
        }
        if let appleMusic = getAppleMusicPlayback() {
            return appleMusic
        }
        lastActivePlayer = .none
        return nil
    }
    
    private func parsePlaybackResult(_ result: String, isSpotify: Bool) -> PlaybackInfo? {
        let parts = result.components(separatedBy: "||||")
        guard parts.count >= 5 else { return nil }
        
        // Spotify includes artwork URL, Apple Music does not (fetched separately)
        let artworkURL: String?
        if isSpotify && parts.count >= 6 && !parts[5].isEmpty {
            artworkURL = parts[5]
        } else {
            artworkURL = nil
        }
        
        return PlaybackInfo(
            title: parts[0],
            artist: parts[1],
            position: Double(parts[2]) ?? 0,
            duration: Double(parts[3]) ?? 0,
            isPlaying: parts[4] == "true",
            artworkURL: artworkURL,
            artworkData: nil  // Apple Music artwork fetched separately on track change
        )
    }
    
    // MARK: - Artwork Fetching (Only called on track changes!)
    
    /// Fetches Apple Music artwork. ONLY call this on track changes, not every poll!
    func getAppleMusicArtwork() -> String? {
        guard let result = execute(appleMusicArtworkScript), !result.isEmpty else { return nil }
        return result
    }
    
    // MARK: - Playback Controls
    
    func playPause() {
        execute(spotifyPlayPauseScript)
        execute(appleMusicPlayPauseScript)
    }
    
    func nextTrack() {
        execute(spotifyNextScript)
        execute(appleMusicNextScript)
    }
    
    func previousTrack() {
        execute(spotifyPreviousScript)
        execute(appleMusicPreviousScript)
    }
}

// MARK: - Global Convenience Functions (delegate to PlaybackMonitor)

func getCurrentPlayback() -> PlaybackInfo? {
    PlaybackMonitor.shared.getCurrentPlayback()
}

func playPause() {
    PlaybackMonitor.shared.playPause()
}

func nextTrack() {
    PlaybackMonitor.shared.nextTrack()
}

func previousTrack() {
    PlaybackMonitor.shared.previousTrack()
}

// MARK: - Sample Data (Fallback)

// MARK: - Artwork Cache

class ArtworkCache {
    static let shared = ArtworkCache()
    private let cache = NSCache<NSString, NSImage>()
    
    private init() {
        cache.countLimit = 50
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }
    
    func cacheKey(title: String, artist: String) -> String {
        return "\(title)|\(artist)"
    }
    
    func get(title: String, artist: String) -> NSImage? {
        let key = cacheKey(title: title, artist: artist)
        return cache.object(forKey: key as NSString)
    }
    
    func set(_ image: NSImage, title: String, artist: String) {
        let key = cacheKey(title: title, artist: artist)
        cache.setObject(image, forKey: key as NSString)
    }
}

// Sample song removed - app now starts with empty state

// MARK: - Theme Definitions

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

enum WindowPresentationEffect: String, CaseIterable, Identifiable {
    case none
    case scaleFade
//    case genie
    case slide
    case layered
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .scaleFade: return "Scale & Fade"
//        case .genie: return "Genie Pull"
        case .slide: return "Slide & Fade"
        case .layered: return "Layered Reveal"
        }
    }
    
    static let storageKey = "WindowPresentationEffectPreference"
    
    static func persistedValue() -> WindowPresentationEffect {
        guard let saved = UserDefaults.standard.string(forKey: storageKey),
              let effect = WindowPresentationEffect(rawValue: saved) else {
            return .scaleFade
        }
        return effect
    }
    
    static func persist(_ effect: WindowPresentationEffect) {
        UserDefaults.standard.set(effect.rawValue, forKey: storageKey)
    }
}

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

// MARK: - Settings Model

class AppSettings: ObservableObject {
    private let cachingEnabledKey = "LyricsCacheEnabled"
    private let presentationEffectKey = WindowPresentationEffect.storageKey
    private let windowOpacityKey = "LyricsWindowOpacity"
    private let cornerRadiusKey = "LyricsCornerRadius"
    private let manualThemeKey = "LyricsManualTheme"
    private let fontScaleKey = "LyricsFontScale"
    
    @Published var windowOpacity: Double {
        didSet {
            UserDefaults.standard.set(windowOpacity, forKey: windowOpacityKey)
        }
    }
    @Published var cornerRadius: Double {
        didSet {
            UserDefaults.standard.set(cornerRadius, forKey: cornerRadiusKey)
        }
    }
    @Published var themeMode: ThemeMode = .matchSystem
    @Published var manualTheme: ThemePreset {
        didSet {
            UserDefaults.standard.set(manualTheme.rawValue, forKey: manualThemeKey)
        }
    }
    @Published var fontScale: Double {
        didSet {
            UserDefaults.standard.set(fontScale, forKey: fontScaleKey)
        }
    }
    @Published var presentationEffect: WindowPresentationEffect {
        didSet {
            WindowPresentationEffect.persist(presentationEffect)
        }
    }
    @Published var cachingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(cachingEnabled, forKey: cachingEnabledKey)
            Task {
                await LyricsCache.shared.setEnabled(cachingEnabled)
            }
        }
    }
    @Published var cacheStats: CacheStats = .empty
    
    init() {
        // Load persisted values with defaults
        let storedOpacity = UserDefaults.standard.object(forKey: windowOpacityKey) as? Double ?? 1.0
        _windowOpacity = Published(initialValue: storedOpacity)
        
        let storedCornerRadius = UserDefaults.standard.object(forKey: cornerRadiusKey) as? Double ?? 16.0
        _cornerRadius = Published(initialValue: storedCornerRadius)
        
        let storedThemeRaw = UserDefaults.standard.string(forKey: manualThemeKey) ?? ThemePreset.midnight.rawValue
        let storedTheme = ThemePreset(rawValue: storedThemeRaw) ?? .midnight
        _manualTheme = Published(initialValue: storedTheme)
        
        let storedFontScale = UserDefaults.standard.object(forKey: fontScaleKey) as? Double ?? 0.8
        _fontScale = Published(initialValue: storedFontScale)
        
        let storedCaching = UserDefaults.standard.object(forKey: cachingEnabledKey) as? Bool ?? true
        _cachingEnabled = Published(initialValue: storedCaching)
        
        let storedEffect = WindowPresentationEffect.persistedValue()
        _presentationEffect = Published(initialValue: storedEffect)
        
        Task {
            await LyricsCache.shared.setEnabled(storedCaching)
        }
    }
    
    func palette(for colorScheme: ColorScheme) -> ThemePalette {
        return manualTheme.palette
    }
    
    func reset() {
        windowOpacity = 1.0
        cornerRadius = 16.0
        themeMode = .matchSystem
        manualTheme = .midnight
        fontScale = 0.8
        presentationEffect = .scaleFade
        cachingEnabled = true
        cacheStats = .empty
    }
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
    @State private var lastTrackID: String = ""  // "title|artist" for robust track detection
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
    @StateObject private var swipeHandler = BrowserSwipeHandler.shared
    @Environment(\.colorScheme) private var colorScheme
    
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
            startTimer()
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
            // Note: swipeHandler.start() is called by AppDelegate when window is shown
        }
        .onDisappear {
            stopTimer()
            // Note: swipeHandler.stop() is called by AppDelegate when window is hidden
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
    
    
    // MARK: - Timer Management
    
    /// Adaptive polling: 500ms during playback, 2s when idle to save CPU
    private func startTimer(interval: TimeInterval = 0.5) {
        timer?.invalidate()
        
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            updateFromRealPlayback()
        }
        
        if let timer = timer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func refreshCacheStats() async {
        let stats = await LyricsCache.shared.currentStats()
        await MainActor.run {
            settings.cacheStats = stats
        }
    }
    
    /// Finds the current lyric line using binary search.
    /// O(log n) instead of O(n²) - critical since this runs at 60fps.
    private func updateCurrentLine() {
        guard !song.lyrics.isEmpty else { return }
        
        // Binary search: find the first line with time > currentTime
        // The current line is the one before that
        var low = 0
        var high = song.lyrics.count
        
        while low < high {
            let mid = (low + high) / 2
            if song.lyrics[mid].time <= currentTime {
                low = mid + 1
            } else {
                high = mid
            }
        }
        
        // low is now the index of the first line with time > currentTime
        // So current line is low - 1, but ensure it's at least 0
        let newIndex = max(0, low - 1)
        
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
        
        // Try Spotify artwork URL (already in playback info, no extra fetch needed)
        if let artworkURL = playback.artworkURL, !artworkURL.isEmpty,
           let url = URL(string: artworkURL) {
            if let image = await downloadArtwork(from: url) {
                ArtworkCache.shared.set(image, title: playback.title, artist: playback.artist)
                return image
            }
        }
        
        // For Apple Music, fetch artwork on-demand (only called on track changes!)
        if PlaybackMonitor.shared.lastActivePlayer == .appleMusic {
            if let artworkPath = PlaybackMonitor.shared.getAppleMusicArtwork() {
                if let image = convertAppleMusicArtwork(artworkPath) {
                    ArtworkCache.shared.set(image, title: playback.title, artist: playback.artist)
                    return image
                }
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
    
    private func updateFromRealPlayback() {
        guard let playback = getCurrentPlayback() else {
            if !noPlaybackDetected {
                noPlaybackDetected = true
                isPlaying = false
                // Switch to slow polling when idle (2s)
                startTimer(interval: 2.0)
            }
            return
        }
        
        if noPlaybackDetected {
            noPlaybackDetected = false
            // Switch back to fast polling when playback detected (500ms)
            startTimer(interval: 0.5)
        }
        
        // Update play state only if changed
        if isPlaying != playback.isPlaying {
            isPlaying = playback.isPlaying
        }
        
        // Update duration only if changed significantly
        if abs(songDuration - playback.duration) > 1.0 {
            songDuration = playback.duration
        }
        
        // Update time only if changed by at least 0.5 seconds
        // This prevents flickering from tiny changes
        if abs(currentTime - playback.position) > 0.5 {
            currentTime = playback.position
            
            // Only check line changes when time actually updated
            updateCurrentLine()
        }
        
        // Track change detection using "title|artist" for robustness
        let trackID = "\(playback.title)|\(playback.artist)"
        if trackID != lastTrackID && !playback.title.isEmpty {
            handleTrackChange(playback: playback, trackID: trackID)
        }
    }
    
    // Separate function to keep updateFromRealPlayback clean
    private func handleTrackChange(playback: PlaybackInfo, trackID: String) {
        lastTrackID = trackID
        Logger.playback.info("Track changed to: \(playback.title) by \(playback.artist)")
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.15)) {
            currentLineIndex = 0
            isLoadingLyrics = true
            lyricsError = nil
        }
        
        Task {
            let artwork = await loadArtwork(from: playback)
            let fetchedLyrics = await LyricsService.fetchLyrics(
                title: playback.title,
                artist: playback.artist,
                duration: playback.duration
            )
            
            await MainActor.run {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0.15)) {
                    if let lyrics = fetchedLyrics {
                        lyricsError = lyrics.isEmpty ? "Instrumental track" : nil
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
                }
            }
            await refreshCacheStats()
        }
    }
}

// MARK: - Theme Preset Button

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

// MARK: - Compact Theme Button

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

// MARK: - Lyric Line View

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

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Browser-Style Swipe Handler

final class BrowserSwipeHandler: ObservableObject {
    static let shared = BrowserSwipeHandler()
    
    private enum Constants {
        static let triggerThreshold: CGFloat = 85
    }
    
    private var monitor: Any?
    private var accumulatedDelta: CGFloat = 0
    private var hasActiveGesture = false
    private var trackingHorizontal = false
    
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    
    func configure(onPrevious: @escaping () -> Void, onNext: @escaping () -> Void) {
        self.onPrevious = onPrevious
        self.onNext = onNext
    }
    
    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handleScroll(event)
        }
    }
    
    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        resetGesture()
    }
    
    private func handleScroll(_ event: NSEvent) -> NSEvent? {
        guard shouldHandle(event: event) else { return event }
        
        let (horizontal, vertical) = normalizedFingerDeltas(for: event)
        
        if event.phase == .began || event.phase == .mayBegin {
            beginGesture(horizontal: horizontal, vertical: vertical)
        } else if event.phase.isEmpty && !hasActiveGesture && event.momentumPhase.isEmpty {
            beginGesture(horizontal: horizontal, vertical: vertical)
        }
        
        if (event.phase == .changed || (event.phase.isEmpty && hasActiveGesture)) && trackingHorizontal {
            accumulatedDelta += horizontal
            if accumulatedDelta >= Constants.triggerThreshold {
                onPrevious?()
                resetGesture()
                return nil
            } else if accumulatedDelta <= -Constants.triggerThreshold {
                onNext?()
                resetGesture()
                return nil
            }
        }
        
        if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended || event.momentumPhase == .cancelled {
            resetGesture()
        }
        
        return event
    }
    
    private func beginGesture(horizontal: CGFloat, vertical: CGFloat) {
        hasActiveGesture = true
        trackingHorizontal = abs(horizontal) > abs(vertical)
        accumulatedDelta = 0
        if !trackingHorizontal {
            hasActiveGesture = false
        }
    }
    
    private func resetGesture() {
        hasActiveGesture = false
        trackingHorizontal = false
        accumulatedDelta = 0
    }
    
    private func normalizedFingerDeltas(for event: NSEvent) -> (CGFloat, CGFloat) {
        let factor: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
        let horizontal = event.scrollingDeltaX * factor
        let vertical = event.scrollingDeltaY * factor
        return (horizontal, vertical)
    }
    
    private func shouldHandle(event: NSEvent) -> Bool {
        guard let window = event.window else { return false }
        guard let keyWindow = NSApp.keyWindow else { return false }
        return window == keyWindow
    }
    
    deinit {
        stop()
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
        
        // Prepare the window lazily without showing it; users can toggle it via shortcut or menu bar.
        _ = ensureLyricsWindow()
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
        
        let rootView = LyricsWidgetView(song: Song(title: "", artist: "", lyrics: []))
            .ignoresSafeArea(.all) // Critical: extend content into title bar area
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
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
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
        containerView.layer?.masksToBounds = true
        
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
        let effect = WindowPresentationEffect.persistedValue()
        
        if window.isVisible {
            BrowserSwipeHandler.shared.stop()
            WindowPresentationAnimator.dismiss(window: window, effect: effect) {
                window.orderOut(nil)
            }
        } else {
            present(window: window, activateApp: true)
        }
    }
    
    @objc private func showWindow() {
        guard let window = ensureLyricsWindow() else { return }
        present(window: window, activateApp: true)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    private func present(window: NSPanel, activateApp: Bool) {
        if activateApp {
            NSApp.activate(ignoringOtherApps: true)
        }
        prepareWindowForDisplay(window)
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        let effect = WindowPresentationEffect.persistedValue()
        WindowPresentationAnimator.animate(window: window, effect: effect)
        BrowserSwipeHandler.shared.start()
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
            Logger.hotkey.error("Failed to register global hot key: \(status)")
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
        let size = NSSize(width: min(windowSize.width, visible.width), height: min(windowSize.height, visible.height))
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
