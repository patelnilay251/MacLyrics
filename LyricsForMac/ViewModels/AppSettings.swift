//
//  AppSettings.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import SwiftUI
import Combine

class AppSettings: ObservableObject {
    private let cachingEnabledKey = "LyricsCacheEnabled"
    private let presentationEffectKey = WindowPresentationEffect.storageKey
    
    @Published var windowOpacity: Double = 1.0
    @Published var cornerRadius: Double = 16.0
    @Published var themeMode: ThemeMode = .matchSystem
    @Published var manualTheme: ThemePreset = .midnight
    @Published var fontScale: Double = 0.8
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
        let stored = UserDefaults.standard.object(forKey: cachingEnabledKey) as? Bool ?? true
        _cachingEnabled = Published(initialValue: stored)
        let storedEffect = WindowPresentationEffect.persistedValue()
        _presentationEffect = Published(initialValue: storedEffect)
        
        Task {
            await LyricsCache.shared.setEnabled(stored)
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

