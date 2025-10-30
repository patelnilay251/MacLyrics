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
        WindowGroup {
            LyricsWidgetView(song: sampleSong)
                .frame(minWidth: 400, idealWidth: 600, maxWidth: 1000, minHeight: 400, idealHeight: 500, maxHeight: 800)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
