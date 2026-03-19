import ApplicationServices
@preconcurrency import AppKit
import Foundation

private struct ClipboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]
}

private struct TargetApplicationContext {
    let pid: pid_t
    let bundleIdentifier: String
    let localizedName: String
}

enum TextInsertionMethod: String {
    case accessibility
    case pasteboard
}

final class TextInserter {
    // Apps that expose AXTextArea but route input through PTY — AX value writes
    // are silently ignored, so paste (Cmd+V to PID) is the only reliable path.
    private static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "co.zeit.hyper",
        "com.1password.1password", // password fields block AX writes
    ]

    // Web and Electron prompt boxes often expose placeholder or hint text as
    // the live AX value. Paste is more reliable than reconstructing their
    // string content through kAXValueAttribute writes.
    private static let pastePreferredBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.brave.Browser",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser", // Arc
        "app.zen-browser.zen",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "com.openai.codex",
    ]

    private let restoreDelay: TimeInterval

    init(restoreClipboardDelayMs: Int) {
        restoreDelay = TimeInterval(restoreClipboardDelayMs) / 1000
    }

    func insertText(_ text: String) throws -> TextInsertionMethod {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(
                domain: "WisprMenuBar",
                code: 30,
                userInfo: [NSLocalizedDescriptionKey: "Cannot insert empty text."]
            )
        }

        logInsertionContext()

        var failures: [(method: String, error: Error)] = []
        var attemptedPaste = false

        // Terminal emulators ignore kAXValueAttribute writes — the value change
        // lands in the AX tree but never reaches the PTY. Skip AX for these apps
        // and go straight to paste (Cmd+V posted to the process PID).
        let targetApp = resolveTargetApplicationContext()
        let targetBundleID = targetApp?.bundleIdentifier ?? ""
        let targetDisplayName = targetApp?.localizedName ?? "unknown"
        let isTerminal = TextInserter.terminalBundleIDs.contains(targetBundleID)
        let prefersPaste = TextInserter.pastePreferredBundleIDs.contains(targetBundleID)

        NSLog("[TextInserter] Target app for insertion: %@ (%@)", targetDisplayName, targetBundleID)

        if isTerminal {
            NSLog("[TextInserter] Skipping AX for terminal app (%@), using paste.", targetBundleID)
        } else if prefersPaste {
            NSLog("[TextInserter] Preferring paste for app (%@) to avoid placeholder-style AX values.", targetBundleID)
            do {
                attemptedPaste = true
                try pasteText(trimmed)
                NSLog("[TextInserter] Inserted text via pasteboard paste.")
                return .pasteboard
            } catch {
                NSLog("[TextInserter] Paste insertion failed: %@", error.localizedDescription)
                failures.append((method: "pasteboard", error: error))
            }

            do {
                try insertViaAccessibility(trimmed)
                NSLog("[TextInserter] Inserted text via accessibility fallback.")
                return .accessibility
            } catch {
                NSLog("[TextInserter] Accessibility fallback failed: %@", error.localizedDescription)
                failures.append((method: "accessibility", error: error))
            }
        } else {
            do {
                try insertViaAccessibility(trimmed)
                NSLog("[TextInserter] Inserted text via accessibility.")
                return .accessibility
            } catch {
                NSLog("[TextInserter] Accessibility insertion failed: %@", error.localizedDescription)
                failures.append((method: "accessibility", error: error))
            }
        }

        if !attemptedPaste {
            do {
                try pasteText(trimmed)
                NSLog("[TextInserter] Inserted text via pasteboard paste.")
                return .pasteboard
            } catch {
                NSLog("[TextInserter] Paste insertion failed: %@", error.localizedDescription)
                failures.append((method: "pasteboard", error: error))
            }
        }

        let summary = failures.map { "  [\($0.method)] \($0.error.localizedDescription)" }.joined(separator: "\n")
        NSLog("[TextInserter] All insertion methods failed:\n%@", summary)
        throw NSError(
            domain: "WisprMenuBar",
            code: 43,
            userInfo: [NSLocalizedDescriptionKey: "All insertion methods failed:\n\(summary)"]
        )
    }

    // MARK: - Diagnostics

    private func logInsertionContext() {
        NSLog("[TextInserter] AXIsProcessTrusted: %@", AXIsProcessTrusted() ? "true" : "false")
        NSLog("[TextInserter] CGPreflightPostEventAccess: %@", CGPreflightPostEventAccess() ? "true" : "false")
        NSLog("[TextInserter] Bundle URL: %@", Bundle.main.bundleURL.path)
        NSLog("[TextInserter] Bundle identifier: %@", Bundle.main.bundleIdentifier ?? "nil")

        let systemWide = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedObject
        )
        guard focusedResult == .success, let focusedObject else {
            NSLog("[TextInserter] Could not retrieve focused element (AXError %d)", focusedResult.rawValue)
            return
        }
        let el = unsafeDowncast(focusedObject, to: AXUIElement.self)

        var pid: pid_t = 0
        if AXUIElementGetPid(el, &pid) == .success {
            NSLog("[TextInserter] Focused element PID: %d", pid)
            if let app = NSRunningApplication(processIdentifier: pid) {
                NSLog("[TextInserter] Focused element app: %@ (%@)",
                      app.localizedName ?? "unknown",
                      app.bundleIdentifier ?? "unknown")
            }
        }

        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String {
            NSLog("[TextInserter] Focused element role: %@", role)
        } else {
            NSLog("[TextInserter] Focused element role: unavailable")
        }

        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String {
            NSLog("[TextInserter] Focused element subrole: %@", subrole)
        } else {
            NSLog("[TextInserter] Focused element subrole: unavailable")
        }

        var valueRef: CFTypeRef?
        let valueErr = AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &valueRef)
        NSLog("[TextInserter] kAXValueAttribute: %@ (AXError %d)",
              valueErr == .success ? "present" : "absent", valueErr.rawValue)

        var placeholderRef: CFTypeRef?
        let placeholderErr = AXUIElementCopyAttributeValue(el, "AXPlaceholderValue" as CFString, &placeholderRef)
        if placeholderErr == .success, let placeholder = placeholderRef as? String {
            NSLog("[TextInserter] AXPlaceholderValue: %@", placeholder)
        } else {
            NSLog("[TextInserter] AXPlaceholderValue: unavailable (AXError %d)", placeholderErr.rawValue)
        }

        var rangeRef: CFTypeRef?
        let rangeErr = AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        NSLog("[TextInserter] kAXSelectedTextRangeAttribute: %@ (AXError %d)",
              rangeErr == .success ? "present" : "absent", rangeErr.rawValue)
    }

    // MARK: - Accessibility insertion

    private func insertViaAccessibility(_ text: String) throws {
        guard Permissions.hasAccessibilityAccess() else {
            throw NSError(
                domain: "WisprMenuBar",
                code: 31,
                userInfo: [NSLocalizedDescriptionKey: "AXIsProcessTrusted() returned false — grant Accessibility access in System Settings > Privacy & Security > Accessibility."]
            )
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedObject)
        guard focusedResult == .success, let focusedObject else {
            throw NSError(
                domain: "WisprMenuBar",
                code: 32,
                userInfo: [NSLocalizedDescriptionKey: "AX: could not get focused element (AXError \(focusedResult.rawValue))."]
            )
        }

        let focusedElement = unsafeDowncast(focusedObject, to: AXUIElement.self)

        var currentValueObject: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(focusedElement, kAXValueAttribute as CFString, &currentValueObject)
        guard valueResult == .success, let currentValue = currentValueObject as? String else {
            throw NSError(
                domain: "WisprMenuBar",
                code: 33,
                userInfo: [NSLocalizedDescriptionKey: "AX: focused element does not expose kAXValueAttribute (AXError \(valueResult.rawValue))."]
            )
        }

        let placeholderValue = copyPlaceholderValue(from: focusedElement)

        var selectedRangeObject: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &selectedRangeObject)
        guard rangeResult == .success,
              let axRange = selectedRangeObject,
              CFGetTypeID(axRange) == AXValueGetTypeID()
        else {
            throw NSError(
                domain: "WisprMenuBar",
                code: 34,
                userInfo: [NSLocalizedDescriptionKey: "AX: focused element does not expose kAXSelectedTextRangeAttribute (AXError \(rangeResult.rawValue))."]
            )
        }

        let selectedRangeValue = unsafeDowncast(axRange, to: AXValue.self)
        guard AXValueGetType(selectedRangeValue) == .cfRange else {
            throw NSError(
                domain: "WisprMenuBar",
                code: 35,
                userInfo: [NSLocalizedDescriptionKey: "AX: focused element returned an unsupported selection type."]
            )
        }

        var selectedRange = CFRange()
        guard AXValueGetValue(selectedRangeValue, .cfRange, &selectedRange) else {
            throw NSError(
                domain: "WisprMenuBar",
                code: 36,
                userInfo: [NSLocalizedDescriptionKey: "AX: could not read selection range value."]
            )
        }

        let isPlaceholderValue = shouldTreatAsPlaceholder(currentValue, placeholder: placeholderValue)
        let effectiveCurrentValue = isPlaceholderValue ? "" : currentValue
        let effectiveSelectedRange = isPlaceholderValue ? CFRange(location: 0, length: 0) : selectedRange

        if isPlaceholderValue, let placeholderValue {
            NSLog("[TextInserter] Treating focused field value as placeholder text: %@", placeholderValue)
        }

        let currentNSString = effectiveCurrentValue as NSString
        let replacementRange = NSRange(
            location: max(0, min(effectiveSelectedRange.location, currentNSString.length)),
            length: max(0, min(effectiveSelectedRange.length, currentNSString.length - max(0, min(effectiveSelectedRange.location, currentNSString.length))))
        )
        let updatedValue = currentNSString.replacingCharacters(in: replacementRange, with: text)

        let setValueResult = AXUIElementSetAttributeValue(focusedElement, kAXValueAttribute as CFString, updatedValue as CFTypeRef)
        guard setValueResult == .success else {
            throw NSError(
                domain: "WisprMenuBar",
                code: 37,
                userInfo: [NSLocalizedDescriptionKey: "AX: AXUIElementSetAttributeValue failed (AXError \(setValueResult.rawValue))."]
            )
        }

        let cursorLocation = replacementRange.location + (text as NSString).length
        var newSelection = CFRange(location: cursorLocation, length: 0)
        guard let newSelectionValue = AXValueCreate(.cfRange, &newSelection) else {
            return
        }
        _ = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            newSelectionValue
        )
    }

    private func copyPlaceholderValue(from element: AXUIElement) -> String? {
        var placeholderObject: CFTypeRef?
        let placeholderResult = AXUIElementCopyAttributeValue(
            element,
            "AXPlaceholderValue" as CFString,
            &placeholderObject
        )
        guard placeholderResult == .success else {
            return nil
        }
        return placeholderObject as? String
    }

    private func shouldTreatAsPlaceholder(_ currentValue: String, placeholder: String?) -> Bool {
        guard let placeholder else {
            return false
        }

        let normalizedCurrent = normalizeAccessibilityText(currentValue)
        let normalizedPlaceholder = normalizeAccessibilityText(placeholder)

        guard !normalizedCurrent.isEmpty, !normalizedPlaceholder.isEmpty else {
            return false
        }

        return normalizedCurrent == normalizedPlaceholder
    }

    private func normalizeAccessibilityText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func resolveTargetApplicationContext() -> TargetApplicationContext? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedObject
        )
        if focusedResult == .success,
           let focusedObject {
            let focusedElement = unsafeDowncast(focusedObject, to: AXUIElement.self)
            var pid: pid_t = 0
            if AXUIElementGetPid(focusedElement, &pid) == .success,
               let app = NSRunningApplication(processIdentifier: pid) {
                return TargetApplicationContext(
                    pid: pid,
                    bundleIdentifier: app.bundleIdentifier ?? "",
                    localizedName: app.localizedName ?? "unknown"
                )
            }
        }

        if let app = NSWorkspace.shared.frontmostApplication {
            return TargetApplicationContext(
                pid: app.processIdentifier,
                bundleIdentifier: app.bundleIdentifier ?? "",
                localizedName: app.localizedName ?? "unknown"
            )
        }

        return nil
    }

    // MARK: - Pasteboard paste

    private func pasteText(_ text: String) throws {
        guard Permissions.canPostEvents() else {
            throw NSError(
                domain: "WisprMenuBar",
                code: 38,
                userInfo: [NSLocalizedDescriptionKey: "CGPreflightPostEventAccess() returned false — cannot post Cmd+V."]
            )
        }

        let snapshot = captureClipboard()
        defer { restoreClipboard(snapshot) }

        try writeTextToClipboard(text)
        Thread.sleep(forTimeInterval: 0.03)
        try postPasteShortcut()
        Thread.sleep(forTimeInterval: restoreDelay)
    }

    private func captureClipboard() -> ClipboardSnapshot {
        let pasteboard = NSPasteboard.general
        let items = pasteboard.pasteboardItems ?? []
        let captured = items.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
        return ClipboardSnapshot(items: captured)
    }

    private func restoreClipboard(_ snapshot: ClipboardSnapshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let items = snapshot.items.map { itemData -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            return item
        }
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    private func writeTextToClipboard(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw NSError(
                domain: "WisprMenuBar",
                code: 12,
                userInfo: [NSLocalizedDescriptionKey: "Failed to write text to the pasteboard."]
            )
        }
    }

    private func postPasteShortcut() throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            throw NSError(
                domain: "WisprMenuBar",
                code: 39,
                userInfo: [NSLocalizedDescriptionKey: "Could not create CGEvent objects for Cmd+V."]
            )
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        // Post directly to the frontmost app's PID rather than the HID tap.
        // This bypasses Terminal's Secure Keyboard Entry restriction, which
        // blocks events injected through the HID system tap.
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            keyDown.postToPid(pid)
            keyUp.postToPid(pid)
        } else {
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
