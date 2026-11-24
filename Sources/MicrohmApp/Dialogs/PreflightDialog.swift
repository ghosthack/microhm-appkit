import AppKit

/// The shared confirmation for actions that end a session (Java's `PreflightDialog`): one
/// copy and layout for every entry point, so the toolbar, the menus and the keyboard never
/// drift into different confirmations. Ending a session requires choosing the action.
enum PreflightDialog {

    /// The affected session as named in the sidebar.
    struct Session {
        let displayName: String

        init(_ entry: SidebarEntry) {
            displayName = entry.displayName
        }
    }

    struct Request {
        let title: String
        let sessions: [Session]
        let consequence: String
        let confirmLabel: String
        let destructive: Bool

        static func kill(_ session: Session) -> Request {
            Request(title: title("Kill", for: session), sessions: [session],
                    consequence: "Stops immediately. Unsaved work is lost.",
                    confirmLabel: "Kill", destructive: true)
        }

        static func close(_ session: Session) -> Request {
            Request(title: title("Close", for: session), sessions: [session],
                    consequence: "Scrollback is lost. You can resume from the sidebar.",
                    confirmLabel: "Close", destructive: false)
        }

        static func reload(_ session: Session) -> Request {
            Request(title: title("Reload", for: session), sessions: [session],
                    consequence: "Restarts in a fresh terminal and resumes the conversation when available.",
                    confirmLabel: "Reload", destructive: false)
        }

        static func closeAll(_ sessions: [Session]) -> Request {
            if sessions.count == 1, let session = sessions.first {
                return close(session)
            }
            return Request(title: "Close \(sessions.count) sessions?", sessions: sessions,
                           consequence: "Scrollback is lost. You can resume from the sidebar.",
                           confirmLabel: "Close All", destructive: false)
        }

        private static func title(_ action: String, for session: Session) -> String {
            let font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let lineWidth: CGFloat = 210
            var name = MainWindowController.ellipsizeRight(session.displayName,
                                                          MainWindowController.windowTitleSessionMaxChars)
            var title = "\(action) “\(name)”?"
            while !name.isEmpty && (title as NSString).size(withAttributes: attributes).width > lineWidth {
                name.removeLast()
                title = "\(action) “\(name.trimmingCharacters(in: .whitespaces))…”?"
            }
            return title
        }
    }

    /// Shows `request` as a sheet on `window` (app-modal without one) and reports the answer.
    static func present(_ request: Request, on window: NSWindow?, completion: @escaping (Bool) -> Void) {
        guard !request.sessions.isEmpty else {
            completion(false)
            return
        }
        let alert = NSAlert()
        alert.alertStyle = request.destructive ? .critical : .warning
        alert.messageText = request.title
        alert.informativeText = request.consequence
        let confirm = alert.addButton(withTitle: request.confirmLabel)
        let cancel = alert.addButton(withTitle: "Cancel")
        confirm.hasDestructiveAction = request.destructive
        confirm.keyEquivalent = ""
        cancel.keyEquivalent = "\u{1b}"
        alert.window.defaultButtonCell = nil
        if let window, window.attachedSheet == nil, window.isVisible {
            alert.beginSheetModal(for: window) { response in
                completion(response == .alertFirstButtonReturn)
            }
        } else {
            completion(alert.runModal() == .alertFirstButtonReturn)
        }
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Edits the sidebar name or restores the harness name.
final class RenameSheet: NSWindowController {
    enum Choice {
        case rename(String)
        case clear
        case cancel
    }

    private static let contentWidth: CGFloat = 400
    private static let restoreResponse = NSApplication.ModalResponse(rawValue: 2)
    private let field = NSTextField()

    static func present(on window: NSWindow, current: String, inherited: String,
                        completion: @escaping (Choice) -> Void) {
        let sheet = RenameSheet(current: current, inherited: inherited)
        guard let panel = sheet.window else { return }
        window.beginSheet(panel) { response in
            switch response {
            case .OK: completion(.rename(sheet.field.stringValue))
            case Self.restoreResponse: completion(.clear)
            default: completion(.cancel)
            }
        }
    }

    private init(current: String, inherited: String) {
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .docModalWindow],
                            backing: .buffered, defer: true)
        panel.title = "Rename session"
        super.init(window: panel)

        let heading = NSTextField(labelWithString: panel.title)
        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        field.bezelStyle = .roundedBezel
        field.setAccessibilityLabel("Session name")
        field.stringValue = current
        field.placeholderString = inherited
        let hint = NSTextField(wrappingLabelWithString: "Harness name: \(inherited)")
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = Self.contentWidth
        let content = NSStackView(views: [field, hint])
        content.orientation = .vertical
        content.alignment = .leading
        for view in [field, hint] {
            view.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        }

        let renameButton = NSButton(title: "Rename", target: self, action: #selector(rename(_:)))
        renameButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancelButton.keyEquivalent = "\u{1b}"
        let restoreButton = NSButton(title: "Use Harness Name", target: self, action: #selector(restore(_:)))
        let footer = NSStackView(views: [restoreButton, NSView(), cancelButton, renameButton])
        footer.spacing = 8

        let stack = NSStackView(views: [heading, content, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)
        stack.setCustomSpacing(15, after: heading)
        stack.setCustomSpacing(18, after: content)
        for view in [heading, content, footer] {
            view.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        }
        panel.contentView = stack
        panel.setContentSize(stack.fittingSize)
        panel.initialFirstResponder = field
        panel.defaultButtonCell = renameButton.cell as? NSButtonCell
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    @objc private func rename(_ sender: Any?) { finish(.OK) }
    @objc private func cancel(_ sender: Any?) { finish(.cancel) }
    @objc private func restore(_ sender: Any?) { finish(Self.restoreResponse) }

    private func finish(_ response: NSApplication.ModalResponse) {
        guard let panel = window else { return }
        panel.sheetParent?.endSheet(panel, returnCode: response)
    }
}
