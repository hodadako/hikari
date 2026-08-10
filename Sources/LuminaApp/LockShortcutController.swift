import ApplicationServices
import CoreGraphics
import Foundation
import OSLog

private let lockShortcutLogger = Logger(
    subsystem: "com.hodadako.Lumina",
    category: "LockShortcut"
)

final class LockShortcutController {
    var onShortcut: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isActive: Bool {
        eventTap != nil
    }

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Current macOS releases can require Input Monitoring for a global
    /// keyboard event tap.  This value is used to request and explain the
    /// permission; `CGEvent.tapCreate` remains the authoritative runtime
    /// check because TCC's preflight answer can lag behind its UI state.
    static var isInputMonitoringTrusted: Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func requestInputMonitoringPermission() -> Bool {
        CGRequestListenEventAccess()
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }
        guard Self.isAccessibilityTrusted else {
            lockShortcutLogger.error("Accessibility permission is unavailable")
            return false
        }

        let eventMask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        // The standard Control + Command + Q lock shortcut can be consumed
        // before a session tap receives it. Prefer the HID stage so Lumina
        // sees the key before the system handler, while keeping the session
        // tap as a compatibility fallback on systems that reject HID taps.
        let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: lockShortcutEventCallback,
            userInfo: userInfo
        ) ?? CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: lockShortcutEventCallback,
            userInfo: userInfo
        )
        guard let eventTap else {
            lockShortcutLogger.error("Unable to create a global keyboard event tap")
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        ) else {
            CFMachPortInvalidate(eventTap)
            return false
        }

        self.eventTap = eventTap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        lockShortcutLogger.notice("Global keyboard event tap enabled")
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let isLuminaShortcut = event.getIntegerValueField(.keyboardEventKeycode) == 12
            && flags.contains(.maskControl)
            && flags.contains(.maskCommand)
            && !flags.contains(.maskAlternate)
            && !flags.contains(.maskShift)
        guard isLuminaShortcut else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown,
           event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            lockShortcutLogger.notice("Lumina Lock shortcut received")
            DispatchQueue.main.async { [weak self] in
                self?.onShortcut?()
            }
        }
        return nil
    }

    deinit {
        stop()
    }
}

private let lockShortcutEventCallback: CGEventTapCallBack = {
    _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let controller = Unmanaged<LockShortcutController>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return controller.handle(type: type, event: event)
}
