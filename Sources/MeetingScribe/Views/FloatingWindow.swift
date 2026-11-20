import AppKit
import SwiftUI

/// Makes a floating window borderless and transparent: no title bar,
/// no window background — only the frosted content floats on the
/// desktop. Applied as a background view so it can reach its NSWindow;
/// if the window isn't reachable yet, the async dispatch retries on
/// the next run loop tick. If anything here fails, the window just
/// keeps its title bar and still works.
///
/// Options cover the floating modes: the capsule and the top bar are
/// `.floating` level so they stay above other apps while a meeting
/// runs; the top bar additionally docks itself at the top center of
/// the screen. The mini window keeps its own (proven) configurator
/// in MiniView.swift and does not use this one.
struct BorderlessWindowConfigurator: NSViewRepresentable {
    var level: NSWindow.Level?
    /// Dock at the top center of the screen, `topGap` below the menu bar.
    var dockAtTopCenter: Bool = false
    var dockWidth: CGFloat?
    var dockHeight: CGFloat?
    var topGap: CGFloat = 8

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask.remove(.titled)
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.isMovableByWindowBackground = true
            if let level { window.level = level }
            if dockAtTopCenter, let screen = window.screen ?? NSScreen.main {
                let frame = screen.visibleFrame
                let width = dockWidth ?? window.frame.width
                let height = dockHeight ?? window.frame.height
                window.setFrame(
                    NSRect(
                        x: frame.midX - width / 2,
                        y: frame.maxY - height - topGap,
                        width: width,
                        height: height
                    ),
                    display: true
                )
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Re-apply the level when it changes at runtime (the top bar's
        // pin toggle switches between floating and normal).
        if let level { nsView.window?.level = level }
    }
}
