//
//  WindowPresentationAnimator.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import AppKit
import QuartzCore

struct WindowPresentationAnimator {
    static func animate(window: NSWindow, effect: WindowPresentationEffect) {
        guard effect != .none else { return }
        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        guard let layer = contentView.layer else { return }
        layer.opacity = 1.0
        
        switch effect {
        case .scaleFade:
            performScaleFade(on: layer, in: contentView)
        case .slide:
            performSlide(on: layer)
        case .layered:
            performLayered(on: layer)
        case .none:
            break
        }
    }
    
    static func dismiss(window: NSWindow, effect: WindowPresentationEffect, completion: @escaping () -> Void) {
        guard effect != .none else {
            completion()
            return
        }
        guard let contentView = window.contentView else {
            completion()
            return
        }
        contentView.wantsLayer = true
        guard let layer = contentView.layer else {
            completion()
            return
        }
        layer.removeAllAnimations()
        
        switch effect {
        case .scaleFade:
            performScaleFadeDismiss(on: layer, in: contentView, completion: completion)
        case .slide:
            performSlideDismiss(on: layer, completion: completion)
        case .layered:
            performLayeredDismiss(on: layer, completion: completion)
        case .none:
            completion()
        }
    }
    
    private static func performScaleFade(on layer: CALayer, in view: NSView) {
        let duration: CFTimeInterval = 0.32
        let anchor = CGPoint(x: 0.5, y: 0.05)
        let originalAnchor = layer.anchorPoint
        let originalPosition = layer.position
        let newPosition = CGPoint(
            x: view.bounds.width * anchor.x,
            y: view.bounds.height * anchor.y
        )
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.anchorPoint = anchor
        layer.position = newPosition
        CATransaction.commit()
        
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)
        
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 0.8
        scaleAnimation.toValue = 1.0
        scaleAnimation.duration = duration
        scaleAnimation.timingFunction = timing
        
        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 0.0
        opacityAnimation.toValue = 1.0
        opacityAnimation.duration = duration
        opacityAnimation.timingFunction = timing
        
        let group = CAAnimationGroup()
        group.duration = duration
        group.timingFunction = timing
        group.animations = [scaleAnimation, opacityAnimation]
        layer.add(group, forKey: "windowScaleFade")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak layer] in
            guard let layer else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.anchorPoint = originalAnchor
            layer.position = originalPosition
            CATransaction.commit()
        }
    }
    
    private static func performSlide(on layer: CALayer) {
        let duration: CFTimeInterval = 0.3
        let translation = CABasicAnimation(keyPath: "transform.translation.y")
        translation.fromValue = -40.0
        translation.toValue = 0.0
        translation.duration = duration
        translation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.0
        opacity.toValue = 1.0
        opacity.duration = duration * 0.9
        opacity.timingFunction = CAMediaTimingFunction(name: .easeOut)
        
        layer.add(translation, forKey: "slideTranslation")
        layer.add(opacity, forKey: "slideOpacity")
    }
    
    private static func performLayered(on layer: CALayer) {
        let baseDuration: CFTimeInterval = 0.28
        
        let backgroundFade = CABasicAnimation(keyPath: "opacity")
        backgroundFade.fromValue = 0.0
        backgroundFade.toValue = 1.0
        backgroundFade.duration = baseDuration
        backgroundFade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.add(backgroundFade, forKey: "layeredBackgroundFade")
        
        guard let contentLayer = layer.sublayers?.first else { return }
        
        let contentGroup = CAAnimationGroup()
        contentGroup.beginTime = CACurrentMediaTime() + 0.05
        contentGroup.duration = 0.4
        contentGroup.timingFunction = CAMediaTimingFunction(name: .easeOut)
        
        let contentOpacity = CABasicAnimation(keyPath: "opacity")
        contentOpacity.fromValue = 0.0
        contentOpacity.toValue = 1.0
        
        let contentScale = CABasicAnimation(keyPath: "transform.scale")
        contentScale.fromValue = 0.95
        contentScale.toValue = 1.0
        
        contentGroup.animations = [contentOpacity, contentScale]
        contentLayer.add(contentGroup, forKey: "layeredContent")
    }
    
    private static func performScaleFadeDismiss(on layer: CALayer, in view: NSView, completion: @escaping () -> Void) {
        let duration: CFTimeInterval = 0.25
        let anchor = CGPoint(x: 0.5, y: 0.05)
        let originalAnchor = layer.anchorPoint
        let originalPosition = layer.position
        let newPosition = CGPoint(
            x: view.bounds.width * anchor.x,
            y: view.bounds.height * anchor.y
        )
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.anchorPoint = anchor
        layer.position = newPosition
        CATransaction.commit()
        
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)
        
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 1.0
        scaleAnimation.toValue = 0.82
        
        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 1.0
        opacityAnimation.toValue = 0.0
        
        let group = CAAnimationGroup()
        group.duration = duration
        group.timingFunction = timing
        group.animations = [scaleAnimation, opacityAnimation]
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        layer.add(group, forKey: "windowScaleFadeDismiss")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            completion()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.anchorPoint = originalAnchor
            layer.position = originalPosition
            layer.opacity = 1.0
            layer.removeAllAnimations()
            CATransaction.commit()
        }
    }
    
    private static func performSlideDismiss(on layer: CALayer, completion: @escaping () -> Void) {
        let duration: CFTimeInterval = 0.22
        let translation = CABasicAnimation(keyPath: "transform.translation.y")
        translation.fromValue = 0.0
        translation.toValue = -30.0
        translation.duration = duration
        translation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        translation.fillMode = .forwards
        translation.isRemovedOnCompletion = false
        
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 1.0
        opacity.toValue = 0.0
        opacity.duration = duration
        opacity.timingFunction = CAMediaTimingFunction(name: .easeIn)
        opacity.fillMode = .forwards
        opacity.isRemovedOnCompletion = false
        
        layer.add(translation, forKey: "slideTranslationDismiss")
        layer.add(opacity, forKey: "slideOpacityDismiss")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            completion()
            layer.opacity = 1.0
            layer.removeAllAnimations()
        }
    }
    
    private static func performLayeredDismiss(on layer: CALayer, completion: @escaping () -> Void) {
        let duration: CFTimeInterval = 0.25
        let backgroundFade = CABasicAnimation(keyPath: "opacity")
        backgroundFade.fromValue = 1.0
        backgroundFade.toValue = 0.0
        backgroundFade.duration = duration
        backgroundFade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        backgroundFade.fillMode = .forwards
        backgroundFade.isRemovedOnCompletion = false
        layer.add(backgroundFade, forKey: "layeredBackgroundFadeDismiss")
        
        if let contentLayer = layer.sublayers?.first {
            let contentGroup = CAAnimationGroup()
            contentGroup.duration = duration
            contentGroup.timingFunction = CAMediaTimingFunction(name: .easeIn)
            
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 1.0
            opacity.toValue = 0.0
            
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1.0
            scale.toValue = 0.92
            
            contentGroup.animations = [opacity, scale]
            contentGroup.fillMode = .forwards
            contentGroup.isRemovedOnCompletion = false
            contentLayer.add(contentGroup, forKey: "layeredContentDismiss")
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            completion()
            layer.opacity = 1.0
            layer.removeAllAnimations()
            layer.sublayers?.forEach { $0.removeAllAnimations() }
        }
    }
}

