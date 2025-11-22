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
    static let isEnabled = true
    
    func startDiscovery() {
        guard Self.isEnabled else { return }
        
        print("🔍 Started notification discovery logger")
        
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
        print("🔍 Stopped notification discovery logger")
        
        // Print summary of discovered notifications
        if !discoveredNotifications.isEmpty {
            print("📊 Discovery Summary: Found \(self.discoveredNotifications.count) unique music notifications")
            for name in discoveredNotifications.sorted() {
                print("   - \(name)")
            }
        }
    }
    
    private func handleNotification(_ notification: Notification) {
        let name = notification.name.rawValue
        
        // DEBUG: Log EVERY notification first to see what we're getting
        print("🔔 DEBUG: Received notification: \(name)")
        
        // Filter for music-related notifications
        let isMusicRelated = name.lowercased().contains("spotify") ||
                            name.lowercased().contains("music") ||
                            name.lowercased().contains("itunes") ||
                            name.lowercased().contains("apple") ||
                            name.contains("com.spotify") ||
                            name.contains("com.apple")
        
        print("🔔 DEBUG: isMusicRelated = \(isMusicRelated)")
        
        guard isMusicRelated else { return }
        
        // Track unique notifications
        let isNewDiscovery = discoveredNotifications.insert(name).inserted
        
        // Log notification details
        print("📻 \(isNewDiscovery ? "[NEW] " : "")\(name)")
        
        if let userInfo = notification.userInfo, !userInfo.isEmpty {
            print("   UserInfo keys: \(userInfo.keys.map { String(describing: $0) }.joined(separator: ", "))")
            
            // Log actual values for important keys
            let importantKeys = ["Name", "Artist", "Album", "Position", "Duration", 
                               "State", "Player State", "Playing", "Track", "kMRMediaRemoteNowPlayingInfo"]
            
            for key in importantKeys {
                if let value = userInfo[key] {
                    print("   \(key): \(String(describing: value))")
                }
            }
            
            // If there are other keys, list them
            let otherKeys = userInfo.keys.filter { key in
                !importantKeys.contains(String(describing: key))
            }
            if !otherKeys.isEmpty {
                print("   Other keys: \(otherKeys.map { String(describing: $0) }.joined(separator: ", "))")
            }
        } else {
            print("   UserInfo: (empty)")
        }
        
        if let object = notification.object {
            print("   Object: \(String(describing: object))")
        } else {
            print("   Object: (nil)")
        }
        print("---")
    }
    
    deinit {
        stopDiscovery()
    }
}
