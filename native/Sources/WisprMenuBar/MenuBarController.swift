@preconcurrency import AppKit
import Foundation

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "Flow is ready", action: nil, keyEquivalent: "")
    private let showHistoryItem = NSMenuItem(title: "Show History", action: #selector(showHistoryPanel), keyEquivalent: "")
    private let showPhrasesItem = NSMenuItem(title: "Show Phrases", action: #selector(showPhrasesPanel), keyEquivalent: "")
    private let menuSeparator = NSMenuItem.separator()
    private let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
    private var pendingPrimaryClick: DispatchWorkItem?

    var onShowHistoryPanel: (() -> Void)?
    var onShowPhrasesPanel: (() -> Void)?
    var onQuit: (() -> Void)?

    override init() {
        super.init()
        configureMenu()
    }

    func updateStatus(_ status: AppStatus) {
        statusItem.button?.image = symbolImage(for: status)
        statusItem.button?.contentTintColor = status.tintColor
        statusItem.button?.toolTip = status.menuDescription
        statusMenuItem.title = status.menuDescription
    }

    func statusButtonScreenFrame() -> NSRect? {
        guard let button = statusItem.button, let window = button.window else {
            return nil
        }
        return window.convertToScreen(button.frame)
    }

    private func configureMenu() {
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleStatusItemClick(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.imagePosition = .imageOnly

        showHistoryItem.target = self
        showPhrasesItem.target = self
        quitItem.target = self

        updateStatus(.ready)

        menu.addItem(statusMenuItem)
        menu.addItem(showHistoryItem)
        menu.addItem(showPhrasesItem)
        menu.addItem(menuSeparator)
        menu.addItem(quitItem)
    }

    private func symbolImage(for status: AppStatus) -> NSImage? {
        let baseImage = NSImage(
            systemSymbolName: status.symbolName,
            accessibilityDescription: status.accessibilityDescription
        )
        let configuredImage = baseImage?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        )
        configuredImage?.isTemplate = true
        return configuredImage
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        let event = NSApp.currentEvent
        let eventType = event?.type
        let clickCount = event?.clickCount ?? 1

        switch eventType {
        case .rightMouseUp:
            pendingPrimaryClick?.cancel()
            pendingPrimaryClick = nil
            showContextMenu()
        case .leftMouseUp:
            if clickCount >= 2 {
                pendingPrimaryClick?.cancel()
                pendingPrimaryClick = nil
                onShowPhrasesPanel?()
            } else {
                let workItem = DispatchWorkItem { [weak self] in
                    self?.onShowHistoryPanel?()
                }
                pendingPrimaryClick?.cancel()
                pendingPrimaryClick = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: workItem)
            }
        default:
            break
        }
    }

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func showHistoryPanel() {
        onShowHistoryPanel?()
    }

    @objc private func showPhrasesPanel() {
        onShowPhrasesPanel?()
    }

    @objc private func quit() {
        onQuit?()
    }
}
