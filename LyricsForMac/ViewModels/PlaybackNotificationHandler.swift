//
//  PlaybackNotificationHandler.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import Foundation
import Combine
import OSLog

class PlaybackNotificationHandler: ObservableObject {
    private var observers: [NSObjectProtocol] = []
    var onTrackChange: (() -> Void)?
    
    func startListening(onTrackChange: @escaping () -> Void) {
        self.onTrackChange = onTrackChange
        
        // Listen for Spotify track changes
        let spotifyObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Logger.playback.info("Spotify track change notification received")
            self?.onTrackChange?()
        }
        observers.append(spotifyObserver)
        
        // Listen for Apple Music track changes
        let appleMusicObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Logger.playback.info("Apple Music track change notification received")
            self?.onTrackChange?()
        }
        observers.append(appleMusicObserver)
        
        Logger.playback.info("Started listening for playback notifications")
    }
    
    func stopListening() {
        for observer in observers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observers.removeAll()
        Logger.playback.info("Stopped listening for playback notifications")
    }
    
    deinit {
        stopListening()
    }
}

