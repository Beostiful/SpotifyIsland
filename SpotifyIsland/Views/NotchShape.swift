import SwiftUI

/// Mimics the MacBook notch outline:
///   - Small convex radius at the top corners (where notch meets bezel)
///   - Concave "ears" — sides flare outward in a smooth S-curve
///   - Convex rounded corners at the bottom
///
/// ```
///   ╭──────────────────────────────╮   ← small convex radius at top
///   ╯                              ╰   ← concave ear transition
///   │                              │   ← straight sides
///   ╰──────────────────────────────╯   ← rounded bottom
/// ```
struct NotchShape: Shape {
    /// Horizontal distance the ear extends beyond the straight sides.
    var earWidth: CGFloat = 5
    /// Vertical height of the concave ear region.
    var earHeight: CGFloat = 10
    /// Small convex radius at the top corners (bezel transition).
    var topRadius: CGFloat = 4
    /// Convex radius at the bottom corners.
    var bottomRadius: CGFloat = 14

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let ew = earWidth
        let eh = earHeight
        let tr = min(topRadius, eh * 0.4)
        let br = min(bottomRadius, h / 2, (w - 2 * ew) / 2)

        var p = Path()

        // ── Start: just after the top-left convex radius ──
        p.move(to: CGPoint(x: tr, y: 0))

        // ── Top edge ──
        p.addLine(to: CGPoint(x: w - tr, y: 0))

        // ── Top-right: small convex radius into concave ear ──
        // Convex arc turns from horizontal to roughly vertical
        p.addCurve(
            to:       CGPoint(x: w, y: tr),
            control1: CGPoint(x: w - tr * 0.44, y: 0),
            control2: CGPoint(x: w, y: tr * 0.44)
        )

        // Concave ear: from (w, tr) curving inward to (w - ew, eh)
        p.addCurve(
            to:       CGPoint(x: w - ew, y: eh),
            control1: CGPoint(x: w, y: eh * 0.55),
            control2: CGPoint(x: w - ew, y: eh * 0.45)
        )

        // ── Right side straight down ──
        p.addLine(to: CGPoint(x: w - ew, y: h - br))

        // ── Bottom-right convex corner ──
        p.addCurve(
            to:       CGPoint(x: w - ew - br, y: h),
            control1: CGPoint(x: w - ew, y: h - br * 0.44),
            control2: CGPoint(x: w - ew - br * 0.44, y: h)
        )

        // ── Bottom edge ──
        p.addLine(to: CGPoint(x: ew + br, y: h))

        // ── Bottom-left convex corner ──
        p.addCurve(
            to:       CGPoint(x: ew, y: h - br),
            control1: CGPoint(x: ew + br * 0.44, y: h),
            control2: CGPoint(x: ew, y: h - br * 0.44)
        )

        // ── Left side straight up ──
        p.addLine(to: CGPoint(x: ew, y: eh))

        // ── Top-left: concave ear into small convex radius ──
        p.addCurve(
            to:       CGPoint(x: 0, y: tr),
            control1: CGPoint(x: ew, y: eh * 0.45),
            control2: CGPoint(x: 0, y: eh * 0.55)
        )

        // Convex arc back to horizontal top edge
        p.addCurve(
            to:       CGPoint(x: tr, y: 0),
            control1: CGPoint(x: 0, y: tr * 0.44),
            control2: CGPoint(x: tr * 0.44, y: 0)
        )

        p.closeSubpath()
        return p
    }
}
