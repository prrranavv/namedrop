import AppKit

final class RenameToastDelegate: NSObject, NSApplicationDelegate {
    private let originalName: String
    private let renamedName: String
    private let slot: Int
    private var panel: NSPanel?

    init(originalName: String, renamedName: String, slot: Int) {
        self.originalName = originalName
        self.renamedName = renamedName
        self.slot = min(max(slot, 0), 3)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        showToast()
    }

    private func showToast() {
        let size = NSSize(width: 340, height: 58)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        panel.contentView = background

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        if let iconPath = ProcessInfo.processInfo.environment["NAMEDROP_ICON"] {
            iconView.image = NSImage(contentsOfFile: iconPath)
        }

        let original = NSTextField(labelWithString: originalName)
        original.font = .systemFont(ofSize: 11, weight: .regular)
        original.textColor = .tertiaryLabelColor
        original.lineBreakMode = .byTruncatingMiddle
        original.maximumNumberOfLines = 1

        let renamed = NSTextField(labelWithString: renamedName)
        renamed.font = .systemFont(ofSize: 12.5, weight: .medium)
        renamed.textColor = .labelColor
        renamed.lineBreakMode = .byTruncatingMiddle
        renamed.maximumNumberOfLines = 1

        let textStack = NSStackView(views: [original, renamed])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        background.addSubview(iconView)
        background.addSubview(textStack)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 11),
            iconView.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 34),
            iconView.heightAnchor.constraint(equalToConstant: 34),
            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -13),
            textStack.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            original.widthAnchor.constraint(equalTo: textStack.widthAnchor),
            renamed.widthAnchor.constraint(equalTo: textStack.widthAnchor),
        ])

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSPointInRect(mouse, $0.frame) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let finalOrigin = NSPoint(
            x: visible.maxX - size.width - 16,
            y: visible.maxY - size.height - 12 - CGFloat(slot) * (size.height + 6)
        )
        panel.setFrameOrigin(finalOrigin)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0.94
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.45) {
            NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
                NSApp.terminate(nil)
            })
        }
    }
}

@main
struct NameDropToast {
    static func main() {
        guard CommandLine.arguments.count >= 3 else {
            Foundation.exit(2)
        }
        let application = NSApplication.shared
        let delegate = RenameToastDelegate(
            originalName: CommandLine.arguments[1],
            renamedName: CommandLine.arguments[2],
            slot: CommandLine.arguments.count >= 4 ? Int(CommandLine.arguments[3]) ?? 0 : 0
        )
        application.delegate = delegate
        application.run()
    }
}
