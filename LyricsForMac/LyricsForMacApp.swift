//
//  LyricsForMacApp.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import SwiftUI

@main
struct LyricsForMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
