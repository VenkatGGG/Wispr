@preconcurrency import AppKit
import Foundation

final class HotkeyMonitor {
    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?
    private var optionDown = false
    private var captureCancelled = false
    private var lastReleaseAt = Date.distantPast
    private let cooldown: TimeInterval = 0.12

    var onPress: (() -> Void)?
    var onRelease: ((Bool) -> Void)?
    var onCancel: (() -> Void)?

    func start() {
        stop()

        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            self?.handleKeyDown()
        }
    }

    func stop() {
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
        }
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
        flagsMonitor = nil
        keyDownMonitor = nil
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let optionPressed = flags.contains(.option)
        let hasConflictingModifier = !flags.intersection([.command, .control, .shift]).isEmpty

        if optionPressed && !optionDown {
            guard !hasConflictingModifier else { return }
            guard Date().timeIntervalSince(lastReleaseAt) >= cooldown else { return }

            optionDown = true
            captureCancelled = false
            onPress?()
            return
        }

        if !optionPressed && optionDown {
            optionDown = false
            lastReleaseAt = Date()
            let cancelled = captureCancelled
            captureCancelled = false
            onRelease?(cancelled)
            return
        }

        if optionPressed && optionDown && hasConflictingModifier && !captureCancelled {
            captureCancelled = true
            onCancel?()
        }
    }

    private func handleKeyDown() {
        guard optionDown, !captureCancelled else { return }
        captureCancelled = true
        onCancel?()
    }
}
