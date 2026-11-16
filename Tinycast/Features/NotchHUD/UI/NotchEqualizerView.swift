import AppKit
import SwiftUI

/// Looping bars animated by Core Animation, so playback costs Tinycast no per-frame work.
struct NotchEqualizerView: NSViewRepresentable {
    func makeNSView(context: Context) -> NotchEqualizerLayerView {
        NotchEqualizerLayerView()
    }

    func updateNSView(_ nsView: NotchEqualizerLayerView, context: Context) {}
}

final class NotchEqualizerLayerView: NSView {
    private static let barWidth: CGFloat = 2.5
    private static let barSpacing: CGFloat = 2
    private static let barHeight: CGFloat = 12
    private static let restingScale: CGFloat = 0.3
    private static let animationKey = "notchEqualizer"
    /// Mismatched periods keep the bars from ever pulsing in unison.
    private static let periods: [CFTimeInterval] = [0.52, 0.38, 0.61, 0.44]

    private let bars: [CALayer] = periods.map { _ in CALayer() }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for bar in bars {
            bar.backgroundColor = NSColor.white.cgColor
            bar.cornerRadius = Self.barWidth / 2
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: Self.barHeight)
            layer?.addSublayer(bar)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let count = CGFloat(bars.count)
        return NSSize(
            width: count * Self.barWidth + (count - 1) * Self.barSpacing,
            height: Self.barHeight)
    }

    override func layout() {
        super.layout()
        let total = intrinsicContentSize.width
        let originX = (bounds.width - total) / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            let offset = CGFloat(index) * (Self.barWidth + Self.barSpacing)
            bar.position = CGPoint(x: originX + offset + Self.barWidth / 2, y: bounds.midY)
        }
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        restartAnimations()
    }

    /// Leaving a window strips a layer's animations, so every return re-adds them.
    private func restartAnimations() {
        for (bar, period) in zip(bars, Self.periods) {
            bar.removeAnimation(forKey: Self.animationKey)
            guard window != nil, Motion.isEnabled else {
                bar.transform = CATransform3DMakeScale(1, 0.6, 1)
                continue
            }
            bar.transform = CATransform3DIdentity
            let pulse = CABasicAnimation(keyPath: "transform.scale.y")
            pulse.fromValue = Self.restingScale
            pulse.toValue = 1
            pulse.duration = period
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.add(pulse, forKey: Self.animationKey)
        }
    }
}
