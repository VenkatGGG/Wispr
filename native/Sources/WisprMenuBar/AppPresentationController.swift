@preconcurrency import AppKit
import Foundation

@MainActor
final class AppPresentationController {
    private let model: HistoryPanelModel
    private let historyPanelController: HistoryPanelController
    private let menuBarController: MenuBarController

    var onQuit: (() -> Void)? {
        didSet {
            menuBarController.onQuit = onQuit
        }
    }

    init(historyFileURL: URL, phrasesFileURL: URL) {
        model = HistoryPanelModel(historyFileURL: historyFileURL, phrasesFileURL: phrasesFileURL)
        historyPanelController = HistoryPanelController(model: model)
        menuBarController = MenuBarController(historyFileURL: historyFileURL, phrasesFileURL: phrasesFileURL)
        menuBarController.onToggleHistoryPanel = { [weak self] in
            self?.toggleHistoryPanel()
        }
    }

    func updateStatus(_ status: AppStatus) {
        model.updateStatus(status)
        menuBarController.updateStatus(status)
    }

    func updateHistory(_ entries: [HistoryEntry]) {
        model.updateHistory(entries)
    }

    func stop() {
        historyPanelController.hide()
    }

    private func toggleHistoryPanel() {
        historyPanelController.toggle(relativeTo: menuBarController.statusButtonScreenFrame())
    }
}
