//
//  ArtworkCache.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import AppKit

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

