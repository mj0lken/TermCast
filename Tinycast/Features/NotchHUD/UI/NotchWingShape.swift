import SwiftUI

/// Hardware-blended notch silhouette with outward top-shoulder concave ears and rounded lower corners.
struct NotchWingShape: Shape {
    private static let bezierKappa: CGFloat = 0.5522847498

    let notchOriginX: CGFloat
    let notchWidth: CGFloat
    var leftExtension: CGFloat
    var rightExtension: CGFloat
    let earRadius: CGFloat
    let innerCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(leftExtension, rightExtension) }
        set {
            leftExtension = newValue.first
            rightExtension = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let height = max(rect.height, 1)
        let leftX = notchOriginX - max(leftExtension, 0)
        let rightX = notchOriginX + notchWidth + max(rightExtension, 0)
        let totalWidth = max(rightX - leftX, 2)

        let ear = min(earRadius, height * 0.35)
        let inner = min(innerCornerRadius, height * 0.48, totalWidth * 0.45)
        let kEar = ear * (1 - Self.bezierKappa)
        let kInner = inner * (1 - Self.bezierKappa)

        var path = Path()
        path.move(to: CGPoint(x: leftX - ear, y: 0))

        // Outward-curving top-left concave shoulder flush against screen.frame.maxY.
        path.addCurve(
            to: CGPoint(x: leftX, y: ear),
            control1: CGPoint(x: leftX - kEar, y: 0),
            control2: CGPoint(x: leftX, y: kEar))

        path.addLine(to: CGPoint(x: leftX, y: height - inner))

        path.addCurve(
            to: CGPoint(x: leftX + inner, y: height),
            control1: CGPoint(x: leftX, y: height - kInner),
            control2: CGPoint(x: leftX + kInner, y: height))

        path.addLine(to: CGPoint(x: rightX - inner, y: height))

        path.addCurve(
            to: CGPoint(x: rightX, y: height - inner),
            control1: CGPoint(x: rightX - kInner, y: height),
            control2: CGPoint(x: rightX, y: height - kInner))

        path.addLine(to: CGPoint(x: rightX, y: ear))

        // Outward-curving top-right concave shoulder flush against screen.frame.maxY.
        path.addCurve(
            to: CGPoint(x: rightX + ear, y: 0),
            control1: CGPoint(x: rightX, y: kEar),
            control2: CGPoint(x: rightX + kEar, y: 0))

        path.closeSubpath()
        return path
    }
}
