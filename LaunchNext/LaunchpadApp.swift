import SwiftUI
import AppKit
import SwiftData
import Combine
import QuartzCore
import Carbon
import Carbon.HIToolbox

extension Notification.Name {
    static let launchpadWindowShown = Notification.Name("LaunchpadWindowShown")
    static let launchpadWindowHidden = Notification.Name("LaunchpadWindowHidden")
}

class BorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@main
struct LaunchpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene { Settings {} }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSGestureRecognizerDelegate {
    static var shared: AppDelegate?
    
    private var window: NSWindow?
    private let minimumContentSize = NSSize(width: 800, height: 600)
    private var lastShowAt: Date?
    private var cancellables = Set<AnyCancellable>()
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyEventHandler: EventHandlerRef?
    
    let appStore = AppStore()
    var modelContainer: ModelContainer?
    private var isTerminating = false
    private var windowIsVisible = false
    private var isAnimatingWindow = false
    private var pendingShow = false
    private var pendingHide = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        appStore.syncGlobalHotKeyRegistration()

        SoundManager.shared.bind(appStore: appStore)
        VoiceManager.shared.bind(appStore: appStore)
        setupWindow()
        appStore.performInitialScanIfNeeded()
        appStore.startAutoRescan()

        bindAppearancePreference()
        bindControllerPreference()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyAppearancePreference(self.appStore.appearancePreference)
        }

        if appStore.isFullscreenMode { updateWindowMode(isFullscreen: true) }
    }

    // MARK: - Global Hotkey

    func updateGlobalHotKey(configuration: AppStore.HotKeyConfiguration?) {
        unregisterGlobalHotKey()
        guard let configuration else { return }
        registerGlobalHotKey(configuration)
    }

    private func registerGlobalHotKey(_ configuration: AppStore.HotKeyConfiguration) {
        ensureHotKeyEventHandler()
        var hotKeyID = EventHotKeyID(signature: fourCharCode("LNXK"), id: 1)
        let status = RegisterEventHotKey(configuration.keyCodeUInt32,
                                         configuration.carbonModifierFlags,
                                         hotKeyID,
                                         GetEventDispatcherTarget(),
                                         0,
                                         &hotKeyRef)
        if status != noErr {
            NSLog("LaunchNext: Failed to register hotkey (status %d)", status)
        }
    }

    private func unregisterGlobalHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handler = hotKeyEventHandler, hotKeyRef == nil {
            RemoveEventHandler(handler)
            hotKeyEventHandler = nil
        }
    }

    private func ensureHotKeyEventHandler() {
        guard hotKeyEventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetEventDispatcherTarget(), hotKeyEventCallback, 1, &eventType, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &hotKeyEventHandler)
        if status != noErr {
            NSLog("LaunchNext: Failed to install hotkey handler (status %d)", status)
        }
    }

    fileprivate func handleHotKeyEvent() {
        DispatchQueue.main.async { [weak self] in
            self?.toggleWindow()
        }
    }

    private func setupWindow() {
        guard let screen = NSScreen.main else { return }
        let rect = calculateContentRect(for: screen)
        
        window = BorderlessWindow(contentRect: rect, styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        window?.delegate = self
        window?.isMovable = false
        window?.level = .floating
        window?.collectionBehavior = [.transient, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle]
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.hasShadow = true
        window?.contentAspectRatio = NSSize(width: 4, height: 3)
        window?.contentMinSize = minimumContentSize
        window?.minSize = window?.frameRect(forContentRect: NSRect(origin: .zero, size: minimumContentSize)).size ?? minimumContentSize
        
        // SwiftData 支持（固定到 Application Support 目录，避免替换应用后数据丢失）
        do {
            let fm = FileManager.default
            let appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let storeDir = appSupport.appendingPathComponent("LaunchNext", isDirectory: true)
            if !fm.fileExists(atPath: storeDir.path) {
                try fm.createDirectory(at: storeDir, withIntermediateDirectories: true)
            }
            let storeURL = storeDir.appendingPathComponent("Data.store")

            let configuration = ModelConfiguration(url: storeURL)
            let container = try ModelContainer(for: TopItemData.self, PageEntryData.self, configurations: configuration)
            modelContainer = container
            appStore.configure(modelContext: container.mainContext)
            window?.contentView = NSHostingView(rootView: LaunchpadView(appStore: appStore).modelContainer(container))
        } catch {
            // 回退到默认容器，保证功能可用
            if let container = try? ModelContainer(for: TopItemData.self, PageEntryData.self) {
                modelContainer = container
                appStore.configure(modelContext: container.mainContext)
                window?.contentView = NSHostingView(rootView: LaunchpadView(appStore: appStore).modelContainer(container))
            } else {
                window?.contentView = NSHostingView(rootView: LaunchpadView(appStore: appStore))
            }
        }
        
        applyCornerRadius()
        window?.alphaValue = 0
        window?.contentView?.alphaValue = 0
        windowIsVisible = false

        // 初始化完成后执行首个淡入
        showWindow()

        // 背景点击关闭逻辑改为 SwiftUI 内部实现，避免与输入控件冲突
    }

    private func bindAppearancePreference() {
        appStore.$appearancePreference
            .receive(on: RunLoop.main)
            .sink { [weak self] preference in
                DispatchQueue.main.async {
                    self?.applyAppearancePreference(preference)
                }
            }
            .store(in: &cancellables)
    }

    private func bindControllerPreference() {
        appStore.$gameControllerEnabled
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { enabled in
                if enabled {
                    ControllerInputManager.shared.start()
                } else {
                    ControllerInputManager.shared.stop()
                }
            }
            .store(in: &cancellables)
    }

    private func applyAppearancePreference(_ preference: AppearancePreference) {
        let appearance = preference.nsAppearance.flatMap { NSAppearance(named: $0) }
        window?.appearance = appearance
        NSApp.appearance = appearance
    }
    
    func showWindow() {
        pendingShow = true
        pendingHide = false
        startPendingWindowTransition()
    }
    
    func hideWindow() {
        pendingHide = true
        pendingShow = false
        startPendingWindowTransition()
    }

    func toggleWindow() {
        if windowIsVisible {
            hideWindow()
        } else {
            showWindow()
        }
    }

    // MARK: - Quit with fade
    func quitWithFade() {
        guard !isTerminating else { NSApp.terminate(nil); return }
        isTerminating = true
        if let window = window {
            pendingShow = false
            pendingHide = false
            animateWindow(to: 0, resumePending: false) {
                window.orderOut(nil)
                window.alphaValue = 1
                window.contentView?.alphaValue = 1
                NSApp.terminate(nil)
            }
        } else {
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateNow }
        quitWithFade()
        return .terminateLater
    }

    deinit {
        unregisterGlobalHotKey()
    }
    
    func updateWindowMode(isFullscreen: Bool) {
        guard let window = window else { return }
        let screen = getCurrentActiveScreen() ?? NSScreen.main!
        window.setFrame(isFullscreen ? screen.frame : calculateContentRect(for: screen), display: true)
        window.hasShadow = !isFullscreen
        window.contentAspectRatio = isFullscreen ? NSSize(width: 0, height: 0) : NSSize(width: 4, height: 3)
        applyCornerRadius()
    }
    
    private func applyCornerRadius() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = appStore.isFullscreenMode ? 0 : 30
        contentView.layer?.masksToBounds = true
    }
    
    private func calculateContentRect(for screen: NSScreen) -> NSRect {
        let frame = screen.visibleFrame
        let width = max(frame.width * 0.4, minimumContentSize.width, minimumContentSize.height * 4/3)
        let height = width * 3/4
        return NSRect(x: frame.midX - width/2, y: frame.midY - height/2, width: width, height: height)
    }
    
    private func getCurrentActiveScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
    }

    // MARK: - Window animation helpers

    private func startPendingWindowTransition() {
        guard !isAnimatingWindow else { return }
        if pendingShow {
            performShowWindow()
        } else if pendingHide {
            performHideWindow()
        }
    }

    private func performShowWindow() {
        pendingShow = false
        guard let window = window else { return }

        if windowIsVisible && !isAnimatingWindow && window.alphaValue >= 0.99 {
            return
        }

        let screen = getCurrentActiveScreen() ?? NSScreen.main!
        let rect = appStore.isFullscreenMode ? screen.frame : calculateContentRect(for: screen)
        window.setFrame(rect, display: true)
        applyCornerRadius()

        if window.alphaValue <= 0.01 || !windowIsVisible {
            window.alphaValue = 0
            window.contentView?.alphaValue = 0
        }

        window.makeKeyAndOrderFront(nil)
        window.collectionBehavior = [.transient, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle]
        window.orderFrontRegardless()
        
        // Force window to become key and main window for proper focus
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
        window.makeMain()

        lastShowAt = Date()
        windowIsVisible = true
        SoundManager.shared.play(.launchpadOpen)
        NotificationCenter.default.post(name: .launchpadWindowShown, object: nil)

        animateWindow(to: 1) {
            self.windowIsVisible = true
            // Ensure focus after animation completes
            DispatchQueue.main.async {
                self.window?.makeKey()
                self.window?.makeMain()
            }
        }
    }

    private func performHideWindow() {
        pendingHide = false
        guard let window = window else { return }

        let shouldPlaySound = windowIsVisible && !isTerminating

        let finalize: () -> Void = {
            self.windowIsVisible = false
            window.orderOut(nil)
            window.alphaValue = 1
            window.contentView?.alphaValue = 1
            self.appStore.isSetting = false
            if self.appStore.rememberLastPage {
                self.appStore.persistCurrentPageIfNeeded()
            } else {
                self.appStore.currentPage = 0
            }
            self.appStore.searchText = ""
            self.appStore.openFolder = nil
            self.appStore.saveAllOrder()
            NotificationCenter.default.post(name: .launchpadWindowHidden, object: nil)
        }

        if (!windowIsVisible && window.alphaValue <= 0.01) || isTerminating {
            if shouldPlaySound {
                SoundManager.shared.play(.launchpadClose)
            }
            finalize()
            return
        }

        if shouldPlaySound {
            SoundManager.shared.play(.launchpadClose)
        }

        animateWindow(to: 0) {
            finalize()
        }
    }

    private func animateWindow(to targetAlpha: CGFloat, resumePending: Bool = true, completion: (() -> Void)? = nil) {
        guard let window = window else {
            completion?()
            return
        }

        isAnimatingWindow = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = targetAlpha
            window.contentView?.animator().alphaValue = targetAlpha
        }, completionHandler: {
            window.alphaValue = targetAlpha
            window.contentView?.alphaValue = targetAlpha
            self.isAnimatingWindow = false
            completion?()
            if resumePending {
                self.startPendingWindowTransition()
            }
        })
    }
    
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let minSize = minimumContentSize
        let contentSize = sender.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize)).size
        let clamped = NSSize(width: max(contentSize.width, minSize.width), height: max(contentSize.height, minSize.height))
        return sender.frameRect(forContentRect: NSRect(origin: .zero, size: clamped)).size
    }
    
    func windowDidResignKey(_ notification: Notification) { autoHideIfNeeded() }
    func windowDidResignMain(_ notification: Notification) { autoHideIfNeeded() }
    private func autoHideIfNeeded() {
        guard !appStore.isSetting else { return }
        hideWindow()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if window?.isVisible == true {
            hideWindow()
        } else {
            showWindow()
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        ControllerInputManager.shared.stop()
    }
    
    private func isInteractiveView(_ view: NSView?) -> Bool {
        var v = view
        while let cur = v {
            if cur is NSControl || cur is NSTextView || cur is NSScrollView || cur is NSVisualEffectView { return true }
            v = cur.superview
        }
        return false
    }

    @objc private func handleBackgroundClick(_ sender: NSClickGestureRecognizer) {
        guard appStore.openFolder == nil && !appStore.isFolderNameEditing else { return }
        guard let view = sender.view else { return }
        let p = sender.location(in: view)
        if let hit = view.hitTest(p), isInteractiveView(hit) { return }
        hideWindow()
    }

    // MARK: - NSGestureRecognizerDelegate
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        guard let contentView = window?.contentView else { return true }
        let point = contentView.convert(event.locationInWindow, from: nil)
        if let hit = contentView.hitTest(point), isInteractiveView(hit) {
            return false
        }
        return true
    }
}

private func hotKeyEventCallback(eventHandlerCallRef: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return noErr }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
    delegate.handleHotKeyEvent()
    return noErr
}

private func fourCharCode(_ string: String) -> FourCharCode {
    var result: UInt32 = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) | (scalar.value & 0xFF)
    }
    return result
}
