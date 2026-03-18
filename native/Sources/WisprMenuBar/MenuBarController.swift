@preconcurrency import AppKit
import Foundation

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "Flow is ready", action: nil, keyEquivalent: "")
    private let showHistoryItem = NSMenuItem(title: "Show History", action: #selector(toggleHistoryPanel), keyEquivalent: "")
    private let menuSeparator = NSMenuItem.separator()
    private let footerSeparator = NSMenuItem.separator()
    private let revealHistoryItem = NSMenuItem(title: "Reveal History File", action: #selector(revealHistoryFile), keyEquivalent: "")
    private let revealPhrasesItem = NSMenuItem(title: "Reveal Phrases File", action: #selector(revealPhrasesFile), keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
    private let historyFileURL: URL
    private let phrasesFileURL: URL

    var onToggleHistoryPanel: (() -> Void)?
    var onQuit: (() -> Void)?

    init(historyFileURL: URL, phrasesFileURL: URL) {
        self.historyFileURL = historyFileURL
        self.phrasesFileURL = phrasesFileURL
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
        revealHistoryItem.target = self
        revealPhrasesItem.target = self
        quitItem.target = self

        updateStatus(.ready)

        menu.addItem(statusMenuItem)
        menu.addItem(showHistoryItem)
        menu.addItem(menuSeparator)
        menu.addItem(footerSeparator)
        menu.addItem(revealHistoryItem)
        menu.addItem(revealPhrasesItem)
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
        let eventType = NSApp.currentEvent?.type
        DispatchQueue.main.async { [weak self] in
            switch eventType {
            case .rightMouseUp:
                self?.showContextMenu()
            default:
                self?.onToggleHistoryPanel?()
            }
        }
    }

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleHistoryPanel() {
        onToggleHistoryPanel?()
    }

    @objc private func revealHistoryFile() {
        NSWorkspace.shared.activateFileViewerSelecting([historyFileURL])
    }

    @objc private func revealPhrasesFile() {
        NSWorkspace.shared.activateFileViewerSelecting([phrasesFileURL])
    }

    @objc private func quit() {
        onQuit?()
    }
}
