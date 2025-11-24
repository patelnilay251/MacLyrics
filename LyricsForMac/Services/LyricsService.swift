//
//  LyricsService.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import Foundation
import OSLog

class LyricsService {
    private nonisolated static let lrcPattern = #"\[(\d{2}):(\d{2})\.(\d{2})\]\s*(.*)"#
    private nonisolated static let lrcRegex = try? NSRegularExpression(pattern: lrcPattern)
    
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
            // Logging removed
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("QuickFlow v1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                // Logging removed
                return nil
            }
            
            if httpResponse.statusCode == 404 {
                // Logging removed
                return nil
            }
            
            guard httpResponse.statusCode == 200 else {
                // Logging removed
                return nil
            }
            
            let result = try JSONDecoder().decode(LRCLIBResponse.self, from: data)
            
            // Check if instrumental
            if result.instrumental == true {
                // Logging removed
                await LyricsCache.shared.store(lyrics: [], title: title, artist: artist, duration: duration)
                return []
            }
            
            // Try synced lyrics first (preferred)
            if let syncedLyrics = result.syncedLyrics {
                // Logging removed
                // Offload parsing to background
                let parsed = await Task.detached(priority: .userInitiated) {
                    return parseLRC(syncedLyrics)
                }.value
                await LyricsCache.shared.store(lyrics: parsed, title: title, artist: artist, duration: duration)
                return parsed
            }
            
            // Fallback to plain lyrics (no timestamps)
            if let plainLyrics = result.plainLyrics {
                // Logging removed
                // Offload parsing to background
                let parsed = await Task.detached(priority: .userInitiated) {
                    return parsePlainLyrics(plainLyrics)
                }.value
                await LyricsCache.shared.store(lyrics: parsed, title: title, artist: artist, duration: duration)
                return parsed
            }
            
            // Logging removed
            return nil
            
        } catch {
            // Logging removed
            return nil
        }
    }
    
    // Parse LRC format: [00:17.12] lyrics text
    nonisolated static func parseLRC(_ lrcText: String) -> [LyricLine] {
        let lines = lrcText.components(separatedBy: .newlines)
        var parsed: [LyricLine] = []
        
        for line in lines {
            let nsLine = line as NSString
            if let match = lrcRegex?.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) {
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
    nonisolated static func parsePlainLyrics(_ plainText: String) -> [LyricLine] {
        let lines = plainText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        // Estimate 3 seconds per line (rough approximation)
        return lines.enumerated().map { index, text in
            LyricLine(time: Double(index) * 3.0, text: text)
        }
    }
}
