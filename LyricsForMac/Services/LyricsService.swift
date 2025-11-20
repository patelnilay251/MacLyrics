//
//  LyricsService.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import Foundation
import OSLog

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

