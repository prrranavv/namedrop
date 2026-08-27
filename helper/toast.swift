import AppKit

final class RenameToastDelegate: NSObject, NSApplicationDelegate {
    private let originalName: String
    private let renamedName: String
    private var panel: NSPanel?

    init(originalName: String, renamedName: String) {
        self.originalName = originalName
        self.renamedName = renamedName
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        showToast()
    }

    private func showToast() {
        let size = NSSize(width: 430, height: 96)
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
        background.layer?.cornerRadius = 16
        background.layer?.masksToBounds = true
        panel.contentView = background

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        if let iconPath = ProcessInfo.processInfo.environment["NAMEDROP_ICON"] {
            iconView.image = NSImage(contentsOfFile: iconPath)
        }

        let title = NSTextField(labelWithString: "NameDrop")
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .secondaryLabelColor

        let original = NSTextField(labelWithString: originalName)
        original.font = .systemFont(ofSize: 13, weight: .regular)
        original.textColor = .secondaryLabelColor
        original.lineBreakMode = .byTruncatingMiddle
        original.maximumNumberOfLines = 1

        let renamed = NSTextField(labelWithString: renamedName)
        renamed.font = .systemFont(ofSize: 14, weight: .semibold)
        renamed.textColor = .labelColor
        renamed.lineBreakMode = .byTruncatingMiddle
        renamed.maximumNumberOfLines = 1
        renamed.alphaValue = 0

        let textStack = NSStackView(views: [title, original, renamed])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3

        background.addSubview(iconView)
        background.addSubview(textStack)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 54),
            iconView.heightAnchor.constraint(equalToConstant: 54),
            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -18),
            textStack.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            original.widthAnchor.constraint(equalTo: textStack.widthAnchor),
            renamed.widthAnchor.constraint(equalTo: textStack.widthAnchor),
        ])

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSPointInRect(mouse, $0.frame) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let finalOrigin = NSPoint(x: visible.maxX - size.width - 22, y: visible.maxY - size.height - 18)
        panel.setFrameOrigin(NSPoint(x: finalOrigin.x, y: finalOrigin.y + 10))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel

        if let layer = iconView.layer {
            let bounce = CASpringAnimation(keyPath: "transform.scale")
            bounce.fromValue = 0.72
            bounce.toValue = 1.0
            bounce.damping = 9
            bounce.initialVelocity = 0.5
            bounce.mass = 0.7
            bounce.duration = bounce.settlingDuration
            layer.add(bounce, forKey: "stampBounce")
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(finalOrigin)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            original.attributedStringValue = NSAttributedString(
                string: self.originalName,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: NSColor.systemRed,
                ]
            )
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                renamed.animator().alphaValue = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.75) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.24
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
            renamedName: CommandLine.arguments[2]
        )
        application.delegate = delegate
        application.run()
    }
}
