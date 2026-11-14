import AppKit
import SwiftUI

struct TerminalOutputView: NSViewRepresentable {
    let tab: TerminalTab
    let horizontalInset: CGFloat
    let bottomClearance: CGFloat

    private static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let tailSlack = Theme.Spacing.chatFollowTailSlack

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var tabID: UUID?
        var generation = -1
        var revision = 0
        var interpreter = ANSIInterpreter()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(
            top: Theme.Spacing.sm, left: 0, bottom: bottomClearance, right: 0)
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = CGSize(width: horizontalInset, height: Theme.Spacing.xs)
        textView.textContainer?.lineFragmentPadding = 0
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        scrollView.contentInsets = NSEdgeInsets(
            top: Theme.Spacing.sm, left: 0, bottom: bottomClearance, right: 0)
        guard let textView = scrollView.documentView as? NSTextView,
            let storage = textView.textStorage
        else { return }
        textView.textContainerInset = CGSize(width: horizontalInset, height: Theme.Spacing.xs)

        let coordinator = context.coordinator
        let following = isAtBottom(scrollView)
        let isSameTab = coordinator.tabID == tab.id && coordinator.generation == tab.generation
        guard !isSameTab || tab.revision != coordinator.revision else { return }

        let isAppend = isSameTab && tab.revision == coordinator.revision + 1
        if !isAppend {
            coordinator.interpreter = ANSIInterpreter()
            storage.setAttributedString(NSAttributedString())
        }
        coordinator.tabID = tab.id
        coordinator.generation = tab.generation
        coordinator.revision = tab.revision
        coordinator.interpreter.render(
            isAppend ? tab.delta : tab.log, into: storage, font: Self.font)
        if following {
            textView.scrollToEndOfDocument(nil)
        }
    }

    private func isAtBottom(_ scrollView: NSScrollView) -> Bool {
        guard let documentView = scrollView.documentView else { return true }
        let visible = scrollView.contentView.bounds
        return visible.maxY >= documentView.frame.height - Self.tailSlack
    }
}
