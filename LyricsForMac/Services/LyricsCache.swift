//
//  LyricsCache.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import Foundation
import CryptoKit

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

