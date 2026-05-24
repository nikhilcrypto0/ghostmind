import AppKit

// NSWindowSharingNone is the single most critical line — makes window
// invisible to all screen capture APIs used by Zoom, Meet, Teams
class OverlayWindow: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        configure()
    }

    private func configure() {
        sharingType = .none
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
    }
}
