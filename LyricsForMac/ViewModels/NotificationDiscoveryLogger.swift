//
//  NotificationDiscoveryLogger.swift
//  LyricsForMac
//
//  Created by Nilay on 11/21/25.
//

import Foundation
import OSLog

/// Debug utility to discover all distributed notifications from music apps
/// This helps identify what events and data are available for polling optimization
class NotificationDiscoveryLogger {
    private var observer: NSObjectProtocol?
    private var discoveredNotifications: Set<String> = []
    
    // Enable/disable discovery logging (set to false in production)
    static let isEnabled = false
    
    func startDiscovery() {
        guard Self.isEnabled else { return }
        
        // Logging removed
        
        // Listen to ALL distributed notifications
        observer = DistributedNotificationCenter.default().addObserver(
            forName: nil, // nil = listen to everything
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleNotification(notification)
        }
    }
    
    func stopDiscovery() {
        if let observer = observer {
            DistributedNotificationCenter.default().removeObserver(observer)
            self.observer = nil
        }
        // Logging removed
        
        // Print summary of discovered notifications
        if !discoveredNotifications.isEmpty {
            // Logging removed
            for name in discoveredNotifications.sorted() {
                // Logging removed
            }
        }
    }
    
    private func handleNotification(_ notification: Notification) {
        let name = notification.name.rawValue
        
        // DEBUG: Log EVERY notification first to see what we're getting
        // Logging removed
        
        // Filter for music-related notifications
        let isMusicRelated = name.lowercased().contains("spotify") ||
                            name.lowercased().contains("music") ||
                            name.lowercased().contains("itunes") ||
                            name.lowercased().contains("apple") ||
                            name.contains("com.spotify") ||
                            name.contains("com.apple")
        
        // Logging removed
        
        guard isMusicRelated else { return }
        
        // Track unique notifications
        let isNewDiscovery = discoveredNotifications.insert(name).inserted
        
        // Log notification details
        // Logging removed
        
        if let userInfo = notification.userInfo, !userInfo.isEmpty {
            // Logging removed
            
            // Log actual values for important keys
            let importantKeys = ["Name", "Artist", "Album", "Position", "Duration", 
                               "State", "Player State", "Playing", "Track", "kMRMediaRemoteNowPlayingInfo"]
            
            for key in importantKeys {
                if let value = userInfo[key] {
                    // Logging removed
                }
            }
            
            // If there are other keys, list them
            let otherKeys = userInfo.keys.filter { key in
                !importantKeys.contains(String(describing: key))
            }
            if !otherKeys.isEmpty {
                // Logging removed
            }
        } else {
            // Logging removed
        }
        
        if let object = notification.object {
            // Logging removed
        } else {
            // Logging removed
        }
        // Logging removed
    }
    
    deinit {
        stopDiscovery()
    }
}
