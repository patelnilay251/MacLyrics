//
//  BrowserSwipeHandler.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import AppKit
import Combine

final class BrowserSwipeHandler: ObservableObject {
    private enum Constants {
        static let triggerThreshold: CGFloat = 85
    }
    
    private var monitor: Any?
    private var accumulatedDelta: CGFloat = 0
    private var hasActiveGesture = false
    private var trackingHorizontal = false
    
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    
    func configure(onPrevious: @escaping () -> Void, onNext: @escaping () -> Void) {
        self.onPrevious = onPrevious
        self.onNext = onNext
    }
    
    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handleScroll(event)
        }
    }
    
    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        resetGesture()
    }
    
    private func handleScroll(_ event: NSEvent) -> NSEvent? {
        guard shouldHandle(event: event) else { return event }
        
        let (horizontal, vertical) = normalizedFingerDeltas(for: event)
        
        if event.phase == .began || event.phase == .mayBegin {
            beginGesture(horizontal: horizontal, vertical: vertical)
        } else if event.phase.isEmpty && !hasActiveGesture && event.momentumPhase.isEmpty {
            beginGesture(horizontal: horizontal, vertical: vertical)
        }
        
        if (event.phase == .changed || (event.phase.isEmpty && hasActiveGesture)) && trackingHorizontal {
            accumulatedDelta += horizontal
            if accumulatedDelta >= Constants.triggerThreshold {
                onPrevious?()
                resetGesture()
                return nil
            } else if accumulatedDelta <= -Constants.triggerThreshold {
                onNext?()
                resetGesture()
                return nil
            }
        }
        
        if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended || event.momentumPhase == .cancelled {
            resetGesture()
        }
        
        return event
    }
    
    private func beginGesture(horizontal: CGFloat, vertical: CGFloat) {
        hasActiveGesture = true
        trackingHorizontal = abs(horizontal) > abs(vertical)
        accumulatedDelta = 0
        if !trackingHorizontal {
            hasActiveGesture = false
        }
    }
    
    private func resetGesture() {
        hasActiveGesture = false
        trackingHorizontal = false
        accumulatedDelta = 0
    }
    
    private func normalizedFingerDeltas(for event: NSEvent) -> (CGFloat, CGFloat) {
        let factor: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
        let horizontal = event.scrollingDeltaX * factor
        let vertical = event.scrollingDeltaY * factor
        return (horizontal, vertical)
    }
    
    private func shouldHandle(event: NSEvent) -> Bool {
        guard let window = event.window else { return false }
        guard let keyWindow = NSApp.keyWindow else { return false }
        return window == keyWindow
    }
    
    deinit {
        stop()
    }
}

