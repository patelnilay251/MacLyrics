//
//  AppDelegate.swift
//  LyricsForMac
//
//  Created by Nilay on 10/28/25.
//

import AppKit
import SwiftUI
import Carbon
import OSLog

extension AppDelegate: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        let adjustedFlag = isProgrammaticWindowChange ? hasUserAdjustedPosition : true
        recordGeometry(of: panel, userAdjusted: adjustedFlag, persist: true)
    }
    
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        let adjustedFlag = isProgrammaticWindowChange ? hasUserAdjustedPosition : true
        recordGeometry(of: panel, userAdjusted: adjustedFlag, persist: true)
    }
    
    func windowDidChangeScreen(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel else { return }
        recordGeometry(of: panel, userAdjusted: hasUserAdjustedPosition, persist: true)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var lyricsWindow: NSPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var lastKnownFrame: NSRect?
    private var lastKnownScreenFrame: NSRect?
    private var lastKnownScreenID: CGDirectDisplayID?
    private var hasUserAdjustedPosition: Bool = false
    private var isProgrammaticWindowChange = false
    private var storedFramesByDisplay: [CGDirectDisplayID: NSRect] = [:]
    private var storedScreenFramesByDisplay: [CGDirectDisplayID: NSRect] = [:]
    
    private let frameDefaultsKey = "LyricsWindowFrame"
    private let screenFrameDefaultsKey = "LyricsWindowScreenFrame"
    private let userAdjustedDefaultsKey = "LyricsWindowUserAdjusted"
    private let framesByDisplayDefaultsKey = "LyricsWindowFramesByDisplay"
    private let screenFramesByDisplayDefaultsKey = "LyricsWindowScreenFramesByDisplay"
    private let lastScreenIDDefaultsKey = "LyricsWindowLastScreenID"
    
    private static let hotKeySignature: OSType = 0x4C595243 // 'LYRC'
    private static let hotKeyCallback: EventHandlerUPP = { (_, eventRef, userData) -> OSStatus in
        guard
            let userData,
            let eventRef
        else {
            return noErr
        }
        
        let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
        delegate.handleHotKeyEvent(eventRef)
        return noErr
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        configureStatusItem()
        loadSavedWindowGeometry()
        registerGlobalHotKey()
        
        // Prepare the window lazily without showing it; users can toggle it via shortcut or menu bar.
        _ = ensureLyricsWindow()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        unregisterGlobalHotKey()
        saveWindowGeometry()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    // MARK: - Status Item
    
    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem?.button else { return }
        
        button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Lyrics")
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
    
    private var statusMenu: NSMenu {
        let menu = NSMenu()
        
        let showItem = NSMenuItem(title: "Show Lyrics", action: #selector(showWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit Lyrics", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        
        return menu
    }
    
    @objc private func handleStatusItemClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            toggleWindowVisibility()
            return
        }
        
        let isRightClick = event.type == .rightMouseUp
        let isControlClick = event.modifierFlags.contains(.control) && event.type == .leftMouseUp
        
        if (isRightClick || isControlClick), let button = statusItem?.button {
            statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
            return
        }
        
        toggleWindowVisibility()
    }
    
    // MARK: - Window Management
    
    @discardableResult
    private func ensureLyricsWindow() -> NSPanel? {
        if let window = lyricsWindow {
            return window
        }
        
        let rootView = LyricsWidgetView(song: Song(title: "", artist: "", lyrics: []))
            .ignoresSafeArea(.all) // Critical: extend content into title bar area
            .frame(
                minWidth: 400,
                idealWidth: 600,
                maxWidth: 1000,
                minHeight: 400,
                idealHeight: 500,
                maxHeight: 800
            )
        
        let controller = NSHostingController(rootView: AnyView(rootView))
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .documentWindow
        panel.contentMinSize = NSSize(width: 400, height: 400)
        panel.contentMaxSize = NSSize(width: 1000, height: 800)
        panel.setContentSize(NSSize(width: 600, height: 500))
        
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        
        let containerView = NSView(frame: panel.contentView?.bounds ?? .zero)
        panel.contentView = containerView
        containerView.autoresizingMask = [.width, .height]
        containerView.wantsLayer = true
        containerView.layer?.masksToBounds = true
        
        let hostingView = controller.view
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        panel.delegate = self
        
        if let savedFrame = lastKnownFrame {
            performProgrammaticWindowChange {
                panel.setFrame(savedFrame, display: false)
            }
        } else if let screen = preferredScreen(for: panel) {
            let defaultFrame = defaultFrame(for: screen, windowSize: panel.frame.size)
            performProgrammaticWindowChange {
                panel.setFrame(defaultFrame, display: false)
            }
            recordGeometry(frame: defaultFrame, screen: screen, userAdjusted: false, persist: false)
        }
        
        hostingController = controller
        lyricsWindow = panel
        
        return panel
    }
    
    private func toggleWindowVisibility() {
        guard let window = ensureLyricsWindow() else { return }
        let effect = WindowPresentationEffect.persistedValue()
        
        if window.isVisible {
            WindowPresentationAnimator.dismiss(window: window, effect: effect) {
                window.orderOut(nil)
            }
        } else {
            present(window: window, activateApp: true)
        }
    }
    
    @objc private func showWindow() {
        guard let window = ensureLyricsWindow() else { return }
        present(window: window, activateApp: true)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    private func present(window: NSPanel, activateApp: Bool) {
        if activateApp {
            NSApp.activate(ignoringOtherApps: true)
        }
        prepareWindowForDisplay(window)
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        let effect = WindowPresentationEffect.persistedValue()
        WindowPresentationAnimator.animate(window: window, effect: effect)
    }
    
    // MARK: - Hot Keys
    
    private func registerGlobalHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(), AppDelegate.hotKeyCallback, 1, &eventType, selfPointer, &eventHandlerRef)
        
        let hotKeyID = EventHotKeyID(signature: AppDelegate.hotKeySignature, id: UInt32(1))
        let modifiers = UInt32(shiftKey) | UInt32(optionKey)
        
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_L), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            Logger.hotkey.error("Failed to register global hot key: \(status)")
        }
    }
    
    private func unregisterGlobalHotKey() {
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
    
    private func handleHotKeyEvent(_ eventRef: EventRef) {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        
        guard status == noErr else { return }
        guard hotKeyID.signature == AppDelegate.hotKeySignature else { return }
        
        toggleWindowVisibility()
    }
    
    private func prepareWindowForDisplay(_ window: NSPanel) {
        guard let targetScreen = preferredScreen(for: window) else { return }
        
        let windowSize = window.frame.size
        
        if !hasUserAdjustedPosition {
            let defaultFrame = defaultFrame(for: targetScreen, windowSize: windowSize)
            performProgrammaticWindowChange {
                window.setFrame(defaultFrame, display: false)
            }
            recordGeometry(frame: defaultFrame, screen: targetScreen, userAdjusted: false, persist: true)
            return
        }
        
        if let targetID = displayID(for: targetScreen),
           let storedFrameForScreen = storedFramesByDisplay[targetID] {
            let referenceScreenFrame = storedScreenFramesByDisplay[targetID] ?? targetScreen.visibleFrame
            let adjustedFrame = adaptFrame(storedFrameForScreen, from: referenceScreenFrame, to: targetScreen.visibleFrame, windowSize: windowSize)
            
            performProgrammaticWindowChange {
                window.setFrame(adjustedFrame, display: false)
            }
            recordGeometry(frame: adjustedFrame, screen: targetScreen, userAdjusted: true, persist: true)
            return
        }
        
        if let storedFrame = lastKnownFrame,
           let storedScreenFrame = lastKnownScreenFrame {
            let adjustedFrame: NSRect = adaptFrame(storedFrame, from: storedScreenFrame, to: targetScreen.visibleFrame, windowSize: windowSize)
            
            performProgrammaticWindowChange {
                window.setFrame(adjustedFrame, display: false)
            }
            recordGeometry(frame: adjustedFrame, screen: targetScreen, userAdjusted: true, persist: true)
        } else {
            let defaultFrame = defaultFrame(for: targetScreen, windowSize: windowSize)
            performProgrammaticWindowChange {
                window.setFrame(defaultFrame, display: false)
            }
            recordGeometry(frame: defaultFrame, screen: targetScreen, userAdjusted: false, persist: true)
        }
    }
    
    private func preferredScreen(for window: NSPanel? = nil) -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screen
        }
        if let windowScreen = window?.screen {
            return windowScreen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }
    
    private func defaultFrame(for screen: NSScreen, windowSize: NSSize) -> NSRect {
        let visible = screen.visibleFrame
        var origin = NSPoint(
            x: visible.midX - windowSize.width / 2,
            y: visible.maxY - windowSize.height - 80
        )
        
        origin.x = clamp(origin.x, min: visible.minX, max: visible.maxX - windowSize.width)
        origin.y = clamp(origin.y, min: visible.minY, max: visible.maxY - windowSize.height)
        
        return NSRect(origin: origin, size: NSSize(width: min(windowSize.width, visible.width),
                                                   height: min(windowSize.height, visible.height)))
    }
    
    private func clampFrame(_ frame: NSRect, to visible: NSRect, windowSize: NSSize) -> NSRect {
        let size = NSSize(width: min(windowSize.width, visible.width), height: min(windowSize.height, visible.height))
        var origin = frame.origin
        
        origin.x = clamp(origin.x, min: visible.minX, max: visible.maxX - size.width)
        origin.y = clamp(origin.y, min: visible.minY, max: visible.maxY - size.height)
        
        return NSRect(origin: origin, size: size)
    }
    
    private func adaptFrame(_ frame: NSRect, from source: NSRect, to target: NSRect, windowSize: NSSize) -> NSRect {
        guard source.width > 0, source.height > 0 else {
            let origin = NSPoint(
                x: target.midX - windowSize.width / 2,
                y: target.midY - windowSize.height / 2
            )
            return clampFrame(NSRect(origin: origin, size: windowSize), to: target, windowSize: windowSize)
        }
        
        let centerXRatio = clamp((frame.midX - source.minX) / source.width, min: 0, max: 1)
        let centerYRatio = clamp((frame.midY - source.minY) / source.height, min: 0, max: 1)
        
        let newCenterX = target.minX + centerXRatio * target.width
        let newCenterY = target.minY + centerYRatio * target.height
        
        let origin = NSPoint(x: newCenterX - windowSize.width / 2,
                             y: newCenterY - windowSize.height / 2)
        
        return clampFrame(NSRect(origin: origin, size: windowSize), to: target, windowSize: windowSize)
    }
    
    private func recordGeometry(frame: NSRect, screen: NSScreen?, userAdjusted: Bool?, persist: Bool) {
        lastKnownFrame = frame
        
        let resolvedScreen = screen ?? screenContaining(frame: frame)
        if let screen = resolvedScreen {
            lastKnownScreenFrame = screen.visibleFrame
            lastKnownScreenID = displayID(for: screen)
        } else {
            lastKnownScreenFrame = nil
            lastKnownScreenID = nil
        }
        
        if let userAdjusted = userAdjusted, userAdjusted {
            hasUserAdjustedPosition = true
            if let screen = resolvedScreen,
               let screenID = displayID(for: screen) {
                storedFramesByDisplay[screenID] = frame
                storedScreenFramesByDisplay[screenID] = screen.visibleFrame
            }
        }
        
        if persist {
            saveWindowGeometry()
        }
    }
    
    private func screenContaining(frame: NSRect) -> NSScreen? {
        return NSScreen.screens.first(where: { frame.intersects($0.frame) })
    }
    
    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return CGDirectDisplayID(screenNumber.uint32Value)
        }
        return nil
    }
    
    private func recordGeometry(of window: NSPanel, userAdjusted: Bool?, persist: Bool) {
        recordGeometry(frame: window.frame, screen: window.screen, userAdjusted: userAdjusted, persist: persist)
    }
    
    private func loadSavedWindowGeometry() {
        let defaults = UserDefaults.standard
        if let frameString = defaults.string(forKey: frameDefaultsKey) {
            lastKnownFrame = NSRectFromString(frameString)
        }
        if let screenFrameString = defaults.string(forKey: screenFrameDefaultsKey) {
            lastKnownScreenFrame = NSRectFromString(screenFrameString)
        }
        if defaults.object(forKey: lastScreenIDDefaultsKey) != nil {
            lastKnownScreenID = CGDirectDisplayID(defaults.integer(forKey: lastScreenIDDefaultsKey))
        }
        if defaults.object(forKey: userAdjustedDefaultsKey) != nil {
            hasUserAdjustedPosition = defaults.bool(forKey: userAdjustedDefaultsKey)
        }
        if let framesDict = defaults.dictionary(forKey: framesByDisplayDefaultsKey) as? [String: String] {
            storedFramesByDisplay = framesDict.reduce(into: [:]) { result, element in
                if let idValue = UInt32(element.key) {
                    result[CGDirectDisplayID(idValue)] = NSRectFromString(element.value)
                }
            }
        }
        if let screenFramesDict = defaults.dictionary(forKey: screenFramesByDisplayDefaultsKey) as? [String: String] {
            storedScreenFramesByDisplay = screenFramesDict.reduce(into: [:]) { result, element in
                if let idValue = UInt32(element.key) {
                    result[CGDirectDisplayID(idValue)] = NSRectFromString(element.value)
                }
            }
        }
        if !storedFramesByDisplay.isEmpty {
            hasUserAdjustedPosition = true
        }
    }
    
    private func saveWindowGeometry() {
        let defaults = UserDefaults.standard
        if let frame = lastKnownFrame {
            defaults.set(NSStringFromRect(frame), forKey: frameDefaultsKey)
        } else {
            defaults.removeObject(forKey: frameDefaultsKey)
        }
        if let screenFrame = lastKnownScreenFrame {
            defaults.set(NSStringFromRect(screenFrame), forKey: screenFrameDefaultsKey)
        } else {
            defaults.removeObject(forKey: screenFrameDefaultsKey)
        }
        if let lastScreenID = lastKnownScreenID {
            defaults.set(Int(lastScreenID), forKey: lastScreenIDDefaultsKey)
        } else {
            defaults.removeObject(forKey: lastScreenIDDefaultsKey)
        }
        
        if storedFramesByDisplay.isEmpty {
            defaults.removeObject(forKey: framesByDisplayDefaultsKey)
        } else {
            let serializedFrames = storedFramesByDisplay.reduce(into: [String: String]()) { result, entry in
                result[String(entry.key)] = NSStringFromRect(entry.value)
            }
            defaults.set(serializedFrames, forKey: framesByDisplayDefaultsKey)
        }
        
        if storedScreenFramesByDisplay.isEmpty {
            defaults.removeObject(forKey: screenFramesByDisplayDefaultsKey)
        } else {
            let serializedScreens = storedScreenFramesByDisplay.reduce(into: [String: String]()) { result, entry in
                result[String(entry.key)] = NSStringFromRect(entry.value)
            }
            defaults.set(serializedScreens, forKey: screenFramesByDisplayDefaultsKey)
        }
        
        defaults.set(hasUserAdjustedPosition, forKey: userAdjustedDefaultsKey)
    }
    
    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        return Swift.max(min, Swift.min(max, value))
    }
    
    private func performProgrammaticWindowChange(_ work: () -> Void) {
        let previousState = isProgrammaticWindowChange
        isProgrammaticWindowChange = true
        defer { isProgrammaticWindowChange = previousState }
        work()
    }
}

