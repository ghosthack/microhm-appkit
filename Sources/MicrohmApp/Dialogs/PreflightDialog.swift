import AppKit

/// The shared confirmation for actions that end a session (Java's `PreflightDialog`): one
/// copy and layout for every entry point, so the toolbar, the menus and the keyboard never
/// drift into different confirmations. Ending a session requires choosing the action.
enum PreflightDialog {

    /// One affected session as the review list shows it.
    struct Session {
        let displayName: String
        let sessionName: String
        let status: String

        init(_ entry: SidebarEntry) {
            displayName = entry.displayName
            sessionName = entry.sessionName
            status = entry.statusPhrase
        }

        var detail: String {
            displayName == sessionName ? status : "\(sessionName) · \(status)"
        }
    }

    struct Request {
        let title: String
        let sessions: [Session]
        let consequence: String
        let confirmLabel: String
        let destructive: Bool

        static func kill(_ session: Session) -> Request {
            Request(title: "Kill session?", sessions: [session],
                    consequence: "Microhm will stop the harness immediately. Any unsaved terminal work will be lost.",
                    confirmLabel: "Kill Session", destructive: true)
        }

        static func close(_ session: Session) -> Request {
            Request(title: "Close session?", sessions: [session],
                    consequence: "Microhm will ask the harness and shell to exit. A closed session loses its "
                        + "scrollback, and you can resume it from the sidebar. A busy or unresponsive session stays open.",
                    confirmLabel: "Close Session", destructive: false)
        }

        static func reload(_ session: Session) -> Request {
            Request(title: "Reload session?", sessions: [session],
                    consequence: "Microhm will restart the harness in a fresh terminal and resume its conversation. "
                        + "A busy or unresponsive session stays open.",
                    confirmLabel: "Reload Session", destructive: false)
        }

        static func closeAll(_ sessions: [Session]) -> Request {
            Request(title: "Close \(sessions.count == 1 ? "the live session" : "all \(sessions.count) live sessions")?",
                    sessions: sessions,
                    consequence: "Microhm will ask each harness to exit. Closed sessions lose their scrollback "
                        + "and can be resumed from the sidebar. Microhm will report any sessions still running.",
                    confirmLabel: "Close All", destructive: false)
        }
    }

    /// Shows `request` as a sheet on `window` (app-modal without one) and reports the answer.
    static func present(_ request: Request, on window: NSWindow?, completion: @escaping (Bool) -> Void) {
        guard !request.sessions.isEmpty else {
            completion(false)
            return
        }
        let sheet = SessionActionSheet(title: request.title, message: request.consequence,
                                       content: review(request.sessions), confirmTitle: request.confirmLabel,
                                       destructive: request.destructive) { response in
            completion(response == .OK)
        }
        sheet.present(on: window)
    }

    private static func review(_ sessions: [Session]) -> NSView {
        let padding: CGFloat = 12
        let rowWidth = SessionActionSheet.contentWidth - padding * 2
        let rows = NSStackView(views: sessions.map { session in
            let name = NSTextField(labelWithString: session.displayName)
            name.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            let detail = NSTextField(labelWithString: session.detail)
            detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            detail.textColor = .secondaryLabelColor
            let row = NSStackView(views: [name, detail])
            row.orientation = .vertical
            row.alignment = .leading
            row.spacing = 2
            for label in [name, detail] {
                label.lineBreakMode = .byTruncatingMiddle
                label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                label.widthAnchor.constraint(equalToConstant: rowWidth).isActive = true
            }
            return row
        })
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 9
        rows.edgeInsets = NSEdgeInsets(top: padding, left: padding, bottom: padding, right: padding)

        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = 8
        box.borderColor = .separatorColor
        box.fillColor = NSColor.labelColor.withAlphaComponent(0.04)
        box.contentViewMargins = .zero
        let rowsHeight = rows.fittingSize.height
        let maxHeight: CGFloat = 220
        box.heightAnchor.constraint(equalToConstant: min(maxHeight, rowsHeight)).isActive = true
        if rowsHeight <= maxHeight {
            box.contentView = rows
            return box
        }

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let document = FlippedView(frame: NSRect(x: 0, y: 0,
                                                width: SessionActionSheet.contentWidth, height: rowsHeight))
        rows.frame = document.bounds
        rows.autoresizingMask = [.width]
        document.addSubview(rows)
        scroll.documentView = document
        box.contentView = scroll
        return box
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Rename: a custom sidebar name, or Clear to go back to the harness's own.
enum RenameSheet {
    enum Choice {
        case rename(String)
        case clear
        case cancel
    }

    static func present(on window: NSWindow, current: String, inherited: String,
                        completion: @escaping (Choice) -> Void) {
        let field = NSTextField()
        field.bezelStyle = .roundedBezel
        field.setAccessibilityLabel("Session name")
        field.stringValue = current
        field.placeholderString = inherited
        let hint = NSTextField(wrappingLabelWithString: "Harness name: \(inherited)")
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = SessionActionSheet.contentWidth
        let content = NSStackView(views: [field, hint])
        content.orientation = .vertical
        content.alignment = .leading
        for view in [field, hint] {
            view.widthAnchor.constraint(equalToConstant: SessionActionSheet.contentWidth).isActive = true
        }
        let sheet = SessionActionSheet(title: "Rename session", content: content, confirmTitle: "Rename",
                                       alternateTitle: "Use Harness Name", initialField: field) { response in
            switch response {
            case .OK: completion(.rename(field.stringValue))
            case SessionActionSheet.alternateResponse: completion(.clear)
            default: completion(.cancel)
            }
        }
        sheet.present(on: window)
    }
}

/// A document-modal sheet with stable action positions for session review and editing.
private final class SessionActionSheet: NSWindowController {
    static let contentWidth: CGFloat = 400
    static let alternateResponse = NSApplication.ModalResponse(rawValue: 2)
    private let completion: (NSApplication.ModalResponse) -> Void

    init(title: String, message: String? = nil, content: NSView, confirmTitle: String,
         destructive: Bool = false, alternateTitle: String? = nil, initialField: NSTextField? = nil,
         completion: @escaping (NSApplication.ModalResponse) -> Void) {
        self.completion = completion
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .docModalWindow],
                            backing: .buffered, defer: true)
        panel.title = title
        super.init(window: panel)

        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        var views: [NSView] = [heading]
        if let message {
            let description = NSTextField(wrappingLabelWithString: message)
            description.preferredMaxLayoutWidth = Self.contentWidth
            description.textColor = .secondaryLabelColor
            views.append(description)
        }

        let confirmButton = NSButton(title: confirmTitle, target: self, action: #selector(confirm(_:)))
        confirmButton.hasDestructiveAction = destructive
        if destructive {
            confirmButton.attributedTitle = NSAttributedString(string: confirmTitle,
                                                               attributes: [.foregroundColor: NSColor.systemRed])
        }
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancelButton.keyEquivalent = "\u{1b}"
        var buttons: [NSView] = []
        if let alternateTitle {
            buttons.append(NSButton(title: alternateTitle, target: self, action: #selector(alternate(_:))))
        }
        buttons.append(contentsOf: [NSView(), cancelButton, confirmButton])
        let footer = NSStackView(views: buttons)
        footer.spacing = 8

        let stack = NSStackView(views: views + [content, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)
        stack.setCustomSpacing(15, after: views.last ?? heading)
        stack.setCustomSpacing(18, after: content)
        for view in views + [content, footer] {
            view.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        }
        panel.contentView = stack
        panel.setContentSize(stack.fittingSize)
        if let initialField {
            panel.initialFirstResponder = initialField
            confirmButton.keyEquivalent = "\r"
            panel.defaultButtonCell = confirmButton.cell as? NSButtonCell
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    func present(on parent: NSWindow?) {
        guard let panel = window else { return }
        if let parent, parent.isVisible, parent.attachedSheet == nil {
            parent.beginSheet(panel) { [self] response in completion(response) }
        } else {
            panel.center()
            let response = NSApp.runModal(for: panel)
            panel.orderOut(nil)
            completion(response)
        }
    }

    @objc private func confirm(_ sender: Any?) { finish(.OK) }
    @objc private func cancel(_ sender: Any?) { finish(.cancel) }
    @objc private func alternate(_ sender: Any?) { finish(Self.alternateResponse) }

    private func finish(_ response: NSApplication.ModalResponse) {
        guard let panel = window else { return }
        if let parent = panel.sheetParent {
            parent.endSheet(panel, returnCode: response)
        } else {
            NSApp.stopModal(withCode: response)
        }
    }
}
