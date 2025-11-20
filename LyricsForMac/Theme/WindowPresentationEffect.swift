//
//  WindowPresentationEffect.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import Foundation

enum WindowPresentationEffect: String, CaseIterable, Identifiable {
    case none
    case scaleFade
    case slide
    case layered
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .scaleFade: return "Scale & Fade"
        case .slide: return "Slide & Fade"
        case .layered: return "Layered Reveal"
        }
    }
    
    static let storageKey = "WindowPresentationEffectPreference"
    
    static func persistedValue() -> WindowPresentationEffect {
        guard let saved = UserDefaults.standard.string(forKey: storageKey),
              let effect = WindowPresentationEffect(rawValue: saved) else {
            return .scaleFade
        }
        return effect
    }
    
    static func persist(_ effect: WindowPresentationEffect) {
        UserDefaults.standard.set(effect.rawValue, forKey: storageKey)
    }
}

