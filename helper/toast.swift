import AppKit

final class SwipeToastView: NSVisualEffectView {
    var onSwipeDismiss: ((CGFloat) -> Void)?
    private var dragStartMouseX: CGFloat?
    private var dragStartOrigin: NSPoint?
    private var scrollStartOrigin: NSPoint?
    private var scrollDistance: CGFloat = 0
    private(set) var isDragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        isDragging = true
        dragStartMouseX = NSEvent.mouseLocation.x
        dragStartOrigin = window.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let startX = dragStartMouseX, let startOrigin = dragStartOrigin else { return }
        let distance = NSEvent.mouseLocation.x - startX
        window.setFrameOrigin(NSPoint(x: startOrigin.x + distance, y: startOrigin.y))
        window.alphaValue = max(0.32, 1 - abs(distance) / 320)
    }

    override func mouseUp(with event: NSEvent) {
        guard let window, let startX = dragStartMouseX, let startOrigin = dragStartOrigin else { return }
        let distance = NSEvent.mouseLocation.x - startX
        isDragging = false
        dragStartMouseX = nil
        dragStartOrigin = nil

        if abs(distance) >= 85 {
            onSwipeDismiss?(distance < 0 ? -1 : 1)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrameOrigin(startOrigin)
            window.animator().alphaValue = 1
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY), let window else {
            super.scrollWheel(with: event)
            return
        }

        if event.phase == .began || scrollStartOrigin == nil {
            scrollStartOrigin = window.frame.origin
            scrollDistance = 0
            isDragging = true
        }
        guard let startOrigin = scrollStartOrigin else { return }
        scrollDistance += event.scrollingDeltaX
        window.setFrameOrigin(NSPoint(x: startOrigin.x + scrollDistance, y: startOrigin.y))
        window.alphaValue = max(0.32, 1 - abs(scrollDistance) / 320)

        if event.phase == .ended || event.phase == .cancelled {
            finishScroll(window: window, startOrigin: startOrigin)
        }
    }

    private func finishScroll(window: NSWindow, startOrigin: NSPoint) {
        let distance = scrollDistance
        scrollStartOrigin = nil
        scrollDistance = 0
        isDragging = false

        if abs(distance) >= 55 {
            onSwipeDismiss?(distance < 0 ? -1 : 1)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrameOrigin(startOrigin)
            window.animator().alphaValue = 1
        }
    }
}

final class RenameToastDelegate: NSObject, NSApplicationDelegate {
    private let originalName: String
    private let renamedName: String
    private let slot: Int
    private var panel: NSPanel?
    private var isDismissing = false

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
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow

        let background = SwipeToastView(frame: NSRect(origin: .zero, size: size))
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
        let finalOrigin = NSPoint(
            x: visible.maxX - size.width - 22,
            y: visible.maxY - size.height - 18 - CGFloat(slot) * (size.height + 10)
        )
        panel.setFrameOrigin(NSPoint(x: finalOrigin.x, y: finalOrigin.y + 10))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel
        background.onSwipeDismiss = { [weak self, weak panel] direction in
            guard let self, let panel else { return }
            self.dismiss(panel, direction: direction)
        }

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

        scheduleAutoDismiss(panel, view: background, after: 3.2)
    }

    private func scheduleAutoDismiss(_ panel: NSPanel, view: SwipeToastView, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak panel, weak view] in
            guard let self, let panel, let view else { return }
            if view.isDragging {
                self.scheduleAutoDismiss(panel, view: view, after: 0.5)
            } else {
                self.dismiss(panel, direction: nil)
            }
        }
    }

    private func dismiss(_ panel: NSPanel, direction: CGFloat?) {
        guard !isDismissing else { return }
        isDismissing = true
        var destination = panel.frame.origin
        if let direction {
            destination.x += direction * (panel.frame.width + 90)
        } else {
            destination.y += 8
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = direction == nil ? 0.24 : 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrameOrigin(destination)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            NSApp.terminate(nil)
        })
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
