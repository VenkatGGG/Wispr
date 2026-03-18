@preconcurrency import AppKit
import SwiftUI

enum HistoryPanelMode {
    case history
    case phrases
}

@MainActor
final class HistoryPanelModel: ObservableObject {
    @Published private(set) var status: AppStatus = .ready
    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var phrases: [PhraseEntry] = []
    @Published private(set) var mode: HistoryPanelMode = .history

    func updateStatus(_ status: AppStatus) {
        self.status = status
    }

    func updateHistory(_ entries: [HistoryEntry]) {
        self.entries = entries
    }

    func updatePhrases(_ phrases: [PhraseEntry]) {
        self.phrases = phrases
    }

    func showHistory() {
        mode = .history
    }

    func showPhrases() {
        mode = .phrases
    }
}

@MainActor
final class HistoryPanelController {
    private let model: HistoryPanelModel
    private let phraseStore: PhraseStore
    private let panel: FloatingHistoryPanel

    init(model: HistoryPanelModel, phraseStore: PhraseStore) {
        self.model = model
        self.phraseStore = phraseStore
        panel = FloatingHistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 520),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configurePanel()
    }

    func showHistory(relativeTo statusButtonFrame: NSRect?) {
        model.showHistory()
        show(relativeTo: statusButtonFrame)
    }

    func showPhrases(relativeTo statusButtonFrame: NSRect?) {
        model.showPhrases()
        show(relativeTo: statusButtonFrame)
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func show(relativeTo statusButtonFrame: NSRect?) {
        positionPanel(relativeTo: statusButtonFrame)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private func configurePanel() {
        panel.title = "Flow"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let view = HistoryPanelView(
            model: model,
            onCopySentence: { [weak self] text in self?.copy(text) },
            onShowHistory: { [weak self] in self?.model.showHistory() },
            onShowPhrases: { [weak self] in self?.model.showPhrases() },
            onAddPhrase: { [weak self] trigger, replacement in self?.addPhrase(trigger: trigger, replacement: replacement) },
            onUpdatePhrase: { [weak self] id, trigger, replacement in self?.updatePhrase(id: id, trigger: trigger, replacement: replacement) },
            onRemovePhrase: { [weak self] id in self?.removePhrase(id: id) },
            onClose: { [weak self] in self?.hide() }
        )

        let hostingView = NSHostingView(rootView: view)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        contentView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        panel.contentView = contentView
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func addPhrase(trigger: String, replacement: String) {
        do {
            try phraseStore.add(trigger: trigger, replacement: replacement)
            model.updatePhrases(phraseStore.allEntries())
            model.showPhrases()
        } catch {
            model.updateStatus(.error(error.localizedDescription))
        }
    }

    private func updatePhrase(id: UUID, trigger: String, replacement: String) {
        do {
            try phraseStore.update(id: id, trigger: trigger, replacement: replacement)
            model.updatePhrases(phraseStore.allEntries())
            model.showPhrases()
        } catch {
            model.updateStatus(.error(error.localizedDescription))
        }
    }

    private func removePhrase(id: UUID) {
        phraseStore.remove(id: id)
        model.updatePhrases(phraseStore.allEntries())
        model.showPhrases()
    }

    private func positionPanel(relativeTo statusButtonFrame: NSRect?) {
        let panelSize = panel.frame.size
        let fallbackScreen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let screenFrame = statusButtonFrame
            .flatMap { frame in NSScreen.screens.first(where: { $0.frame.contains(frame.origin) })?.visibleFrame }
            ?? fallbackScreen

        let anchor = statusButtonFrame ?? NSRect(
            x: screenFrame.maxX - 40,
            y: screenFrame.maxY - 30,
            width: 20,
            height: 20
        )

        let minX = screenFrame.minX + 12
        let maxX = screenFrame.maxX - panelSize.width - 12
        let originX = min(max(anchor.maxX - panelSize.width, minX), maxX)
        let originY = max(screenFrame.maxY - panelSize.height - 18, screenFrame.minY + 18)
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
}

private final class FloatingHistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct HistoryPanelView: View {
    @ObservedObject var model: HistoryPanelModel

    let onCopySentence: (String) -> Void
    let onShowHistory: () -> Void
    let onShowPhrases: () -> Void
    let onAddPhrase: (String, String) -> Void
    let onUpdatePhrase: (UUID, String, String) -> Void
    let onRemovePhrase: (UUID) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .overlay(Color.white.opacity(0.06))
            Group {
                switch model.mode {
                case .history:
                    historyContent
                case .phrases:
                    phrasesContent
                }
            }
            footer
        }
        .frame(width: 400, height: 520)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.11, blue: 0.13),
                    Color(red: 0.07, green: 0.08, blue: 0.10),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Flow")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(model.mode == .history ? "History" : "Phrases")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                if case .error = model.status {
                    Text(model.status.detail)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.38))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                StatusBadge(status: model.status)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.84))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private var historyContent: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if model.entries.isEmpty {
                    MinimalEmptyState(
                        title: "No translations yet",
                        detail: "Hold Option, speak, release."
                    )
                } else {
                    ForEach(model.entries) { entry in
                        SentenceRow(text: entry.finalText) {
                            onCopySentence(entry.finalText)
                        }
                    }
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
    }

    private var phrasesContent: some View {
        PhraseEditorView(
            phrases: model.phrases,
            onAddPhrase: onAddPhrase,
            onUpdatePhrase: onUpdatePhrase,
            onRemovePhrase: onRemovePhrase
        )
        .padding(16)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            FooterPill(
                title: "History",
                subtitle: "single click",
                isActive: model.mode == .history,
                onTap: onShowHistory
            )

            DoubleTapFooterPill(
                title: "Phrases",
                subtitle: "double click",
                isActive: model.mode == .phrases,
                onDoubleTap: onShowPhrases
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(Color.black.opacity(0.16))
    }
}

private struct StatusBadge: View {
    let status: AppStatus

    var body: some View {
        Label(title, systemImage: status.symbolName)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(Color(nsColor: status.tintColor))
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(Color(nsColor: status.tintColor).opacity(0.16))
            )
    }

    private var title: String {
        switch status {
        case .ready:
            return "Ready"
        case .recording:
            return "Recording"
        case .processing:
            return "Processing"
        case .error:
            return "Error"
        }
    }
}

private struct MinimalEmptyState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text(detail)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.56))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SentenceRow: View {
    let text: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct FooterPill: View {
    let title: String
    let subtitle: String
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .opacity(0.56)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(.white)
            .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var background: Color {
        isActive ? Color.white.opacity(0.12) : Color.white.opacity(0.06)
    }
}

private struct DoubleTapFooterPill: View {
    let title: String
    let subtitle: String
    let isActive: Bool
    let onDoubleTap: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .opacity(0.56)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
        .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onDoubleTap)
    }

    private var background: Color {
        isActive ? Color.white.opacity(0.12) : Color.white.opacity(0.06)
    }
}

private struct PhraseEditorView: View {
    let phrases: [PhraseEntry]
    let onAddPhrase: (String, String) -> Void
    let onUpdatePhrase: (UUID, String, String) -> Void
    let onRemovePhrase: (UUID) -> Void

    @State private var newTrigger = ""
    @State private var newReplacement = ""
    @State private var editingID: UUID?
    @State private var editingTrigger = ""
    @State private var editingReplacement = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if phrases.isEmpty {
                    MinimalEmptyState(
                        title: "No phrases yet",
                        detail: "Add quick replacements below."
                    )
                } else {
                    ForEach(phrases) { phrase in
                        phraseRow(for: phrase)
                    }
                }

                addPhraseCard
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func phraseRow(for phrase: PhraseEntry) -> some View {
        if editingID == phrase.id {
            VStack(alignment: .leading, spacing: 10) {
                PhraseField(title: "Trigger", text: $editingTrigger)
                PhraseField(title: "Replacement", text: $editingReplacement)
                HStack(spacing: 8) {
                    smallActionButton("Save", tint: Color(red: 0.30, green: 0.72, blue: 0.45)) {
                        onUpdatePhrase(phrase.id, editingTrigger, editingReplacement)
                        editingID = nil
                        editingTrigger = ""
                        editingReplacement = ""
                    }
                    smallActionButton("Cancel", tint: Color.white.opacity(0.16)) {
                        editingID = nil
                        editingTrigger = ""
                        editingReplacement = ""
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(phrase.trigger)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(phrase.replacement)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                }

                HStack(spacing: 8) {
                    smallActionButton("Edit", tint: Color.white.opacity(0.14)) {
                        editingID = phrase.id
                        editingTrigger = phrase.trigger
                        editingReplacement = phrase.replacement
                    }
                    smallActionButton("Remove", tint: Color(red: 0.75, green: 0.26, blue: 0.24)) {
                        onRemovePhrase(phrase.id)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var addPhraseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add New")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            PhraseField(title: "Trigger", text: $newTrigger)
            PhraseField(title: "Replacement", text: $newReplacement)
            smallActionButton("Add", tint: Color(red: 0.28, green: 0.62, blue: 0.96)) {
                onAddPhrase(newTrigger, newReplacement)
                newTrigger = ""
                newReplacement = ""
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func smallActionButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint, in: Capsule())
    }
}

private struct PhraseField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.54))
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
