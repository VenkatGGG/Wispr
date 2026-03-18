@preconcurrency import AppKit
import SwiftUI

@MainActor
final class HistoryPanelModel: ObservableObject {
    let historyFileURL: URL
    let phrasesFileURL: URL

    @Published private(set) var status: AppStatus = .ready
    @Published private(set) var entries: [HistoryEntry] = []

    init(historyFileURL: URL, phrasesFileURL: URL) {
        self.historyFileURL = historyFileURL
        self.phrasesFileURL = phrasesFileURL
    }

    func updateStatus(_ status: AppStatus) {
        self.status = status
    }

    func updateHistory(_ entries: [HistoryEntry]) {
        self.entries = entries
    }
}

@MainActor
final class HistoryPanelController {
    private let model: HistoryPanelModel
    private let panel: FloatingHistoryPanel

    init(model: HistoryPanelModel) {
        self.model = model
        panel = FloatingHistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configurePanel()
    }

    func toggle(relativeTo statusButtonFrame: NSRect?) {
        if panel.isVisible {
            hide()
        } else {
            show(relativeTo: statusButtonFrame)
        }
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
            onCopy: { [weak self] text in self?.copy(text) },
            onRevealHistoryFile: { [weak self] in self?.reveal(self?.model.historyFileURL) },
            onRevealPhrasesFile: { [weak self] in self?.reveal(self?.model.phrasesFileURL) },
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

    private func reveal(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
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

    let onCopy: (String) -> Void
    let onRevealHistoryFile: () -> Void
    let onRevealPhrasesFile: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .overlay(Color.white.opacity(0.08))
            content
            footer
        }
        .frame(width: 420, height: 560)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.12, blue: 0.15),
                    Color(red: 0.08, green: 0.09, blue: 0.11),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Flow")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(model.status.headline)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                Text(model.status.detail)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 10) {
                StatusBadge(status: model.status)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if model.entries.isEmpty {
                    emptyState
                } else {
                    ForEach(model.entries) { entry in
                        HistoryEntryCard(entry: entry, onCopy: onCopy)
                    }
                }
            }
            .padding(18)
        }
        .scrollIndicators(.hidden)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No dictations yet")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("Hold Option, speak, and release. Your recent dictations will land here.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            FooterButton(title: "History File", icon: "clock.arrow.circlepath", action: onRevealHistoryFile)
            FooterButton(title: "Phrases File", icon: "text.badge.plus", action: onRevealPhrasesFile)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.18))
    }
}

private struct StatusBadge: View {
    let status: AppStatus

    var body: some View {
        Label(title, systemImage: status.symbolName)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
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

private struct HistoryEntryCard: View {
    let entry: HistoryEntry
    let onCopy: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(entry.sourceApp ?? "Unknown App")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.99, green: 0.79, blue: 0.45))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(red: 0.99, green: 0.79, blue: 0.45).opacity(0.16), in: Capsule())
                Spacer()
                Text(entry.createdAt.historyPanelTimestamp)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Formatted")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                Text(entry.finalText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
            }

            if entry.rawTranscript != entry.finalText {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Raw transcript")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                    Text(entry.rawTranscript)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .textSelection(.enabled)
                }
            }

            HStack {
                Spacer()
                Button("Copy") {
                    onCopy(entry.finalText)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.84, green: 0.37, blue: 0.17))
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct FooterButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .foregroundStyle(.white.opacity(0.84))
    }
}

private extension Date {
    var historyPanelTimestamp: String {
        HistoryPanelFormatting.dateFormatter.string(from: self)
    }
}

private enum HistoryPanelFormatting {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
