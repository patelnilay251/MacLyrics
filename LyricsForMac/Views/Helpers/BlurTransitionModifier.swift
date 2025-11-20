//
//  BlurTransitionModifier.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import SwiftUI

struct BlurTransitionModifier: ViewModifier {
    let radius: CGFloat
    
    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

