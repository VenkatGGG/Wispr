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

    init(historyStore: HistoryStore, phraseStore: PhraseStore) {
        model = HistoryPanelModel()
        historyPanelController = HistoryPanelController(model: model, phraseStore: phraseStore)
        menuBarController = MenuBarController()
        menuBarController.onShowHistoryPanel = { [weak self] in
            self?.showHistoryPanel()
        }
        menuBarController.onShowPhrasesPanel = { [weak self] in
            self?.showPhrasesPanel()
        }
        model.updateHistory(historyStore.recentEntries())
        model.updatePhrases(phraseStore.allEntries())
    }

    func updateStatus(_ status: AppStatus) {
        model.updateStatus(status)
        menuBarController.updateStatus(status)
    }

    func updateHistory(_ entries: [HistoryEntry]) {
        model.updateHistory(entries)
    }

    func updatePhrases(_ entries: [PhraseEntry]) {
        model.updatePhrases(entries)
    }

    func stop() {
        historyPanelController.hide()
    }

    private func showHistoryPanel() {
        historyPanelController.showHistory(relativeTo: menuBarController.statusButtonScreenFrame())
    }

    private func showPhrasesPanel() {
        historyPanelController.showPhrases(relativeTo: menuBarController.statusButtonScreenFrame())
    }
}
