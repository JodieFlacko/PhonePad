import UIKit

/// One control on the virtual pad, laid out like the 8BitDo SN30 Pro.
enum Control: Hashable, CaseIterable {
    case up, down, left, right
    case a, b, x, y
    case l, r, select, start

    /// Godot `JoyButton` index. Face buttons are positional, the same as SDL maps a real
    /// controller: the 8BitDo's right button is labelled A but is Godot's "right" button (1).
    var godotButton: Int {
        switch self {
        case .b: 0       // bottom
        case .a: 1       // right
        case .y: 2       // left
        case .x: 3       // top
        case .select: 4
        case .start: 6
        case .l: 9
        case .r: 10
        case .up: 11
        case .down: 12
        case .left: 13
        case .right: 14
        }
    }
}

/// Full-screen multi-touch surface that draws the pad and reports which controls are held.
/// Fingers can slide between buttons (a thumb rolling across the D-pad or from B to A).
final class PadView: UIView {
    var onChange: ((Control, Bool) -> Void)?

    private var touchControls: [ObjectIdentifier: Set<Control>] = [:]
    private var pressed: Set<Control> = []
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = UIColor(white: 0.13, alpha: 1)
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Layout

    private struct Layout {
        let dpadCenter: CGPoint
        let dpadRadius: CGFloat
        let faceCenter: CGPoint
        let faceSpacing: CGFloat
        let faceRadius: CGFloat
        let lRect: CGRect
        let rRect: CGRect
        let selectRect: CGRect
        let startRect: CGRect

        var faceCenters: [(Control, CGPoint)] {
            [(.x, CGPoint(x: faceCenter.x, y: faceCenter.y - faceSpacing)),
             (.a, CGPoint(x: faceCenter.x + faceSpacing, y: faceCenter.y)),
             (.b, CGPoint(x: faceCenter.x, y: faceCenter.y + faceSpacing)),
             (.y, CGPoint(x: faceCenter.x - faceSpacing, y: faceCenter.y))]
        }
    }

    private var layout: Layout {
        let safe = bounds.inset(by: safeAreaInsets)
        let w = safe.width, h = safe.height
        let radius = min(h * 0.3, w * 0.15)
        let rowY = safe.minY + h * 0.58
        let shoulder = CGSize(width: w * 0.26, height: max(44, h * 0.14))
        let pill = CGSize(width: 76, height: 32)
        return Layout(
            dpadCenter: CGPoint(x: safe.minX + w * 0.18, y: rowY),
            dpadRadius: radius,
            faceCenter: CGPoint(x: safe.maxX - w * 0.18, y: rowY),
            faceSpacing: radius * 0.64,
            faceRadius: radius * 0.34,
            lRect: CGRect(x: safe.minX + 8, y: safe.minY + 8, width: shoulder.width, height: shoulder.height),
            rRect: CGRect(x: safe.maxX - 8 - shoulder.width, y: safe.minY + 8, width: shoulder.width, height: shoulder.height),
            selectRect: CGRect(x: safe.midX - pill.width - 12, y: safe.maxY - pill.height - 20, width: pill.width, height: pill.height),
            startRect: CGRect(x: safe.midX + 12, y: safe.maxY - pill.height - 20, width: pill.width, height: pill.height)
        )
    }

    // MARK: Hit testing

    private func controls(at p: CGPoint) -> Set<Control> {
        let lay = layout

        // D-pad: 8 sectors around the centre, so diagonals press two directions.
        let dx = p.x - lay.dpadCenter.x, dy = p.y - lay.dpadCenter.y
        let dist = hypot(dx, dy)
        if dist <= lay.dpadRadius * 1.35 {
            if dist < lay.dpadRadius * 0.18 { return [] }
            let angle = atan2(-dy, dx) // 0 = right, counter-clockwise, y up
            let sector = Int(((angle + .pi * 2 + .pi / 8).truncatingRemainder(dividingBy: .pi * 2)) / (.pi / 4))
            switch sector {
            case 0: return [.right]
            case 1: return [.up, .right]
            case 2: return [.up]
            case 3: return [.up, .left]
            case 4: return [.left]
            case 5: return [.down, .left]
            case 6: return [.down]
            default: return [.down, .right]
            }
        }

        // Face buttons: nearest one; a thumb between two adjacent buttons presses both.
        if hypot(p.x - lay.faceCenter.x, p.y - lay.faceCenter.y) <= lay.faceSpacing + lay.faceRadius * 1.7 {
            let ranked = lay.faceCenters
                .map { ($0.0, hypot(p.x - $0.1.x, p.y - $0.1.y)) }
                .sorted { $0.1 < $1.1 }
            if ranked[1].1 - ranked[0].1 < lay.faceRadius * 0.35 {
                return [ranked[0].0, ranked[1].0]
            }
            return [ranked[0].0]
        }

        let pad: CGFloat = -14
        if lay.lRect.insetBy(dx: pad, dy: pad).contains(p) { return [.l] }
        if lay.rRect.insetBy(dx: pad, dy: pad).contains(p) { return [.r] }
        if lay.selectRect.insetBy(dx: pad, dy: pad).contains(p) { return [.select] }
        if lay.startRect.insetBy(dx: pad, dy: pad).contains(p) { return [.start] }
        return []
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches, ended: false) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches, ended: false) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches, ended: true) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches, ended: true) }

    private func update(_ touches: Set<UITouch>, ended: Bool) {
        for t in touches {
            let key = ObjectIdentifier(t)
            if ended {
                touchControls[key] = nil
            } else {
                touchControls[key] = controls(at: t.location(in: self))
            }
        }
        let now = touchControls.values.reduce(into: Set<Control>()) { $0.formUnion($1) }
        guard now != pressed else { return }
        let released = pressed.subtracting(now)
        let added = now.subtracting(pressed)
        pressed = now
        for c in released { onChange?(c, false) }
        for c in added { onChange?(c, true) }
        if !added.isEmpty { haptic.impactOccurred() }
        setNeedsDisplay()
    }

    /// Lets go of everything, e.g. when the app goes to the background.
    func releaseAll() {
        touchControls.removeAll()
        for c in pressed { onChange?(c, false) }
        pressed.removeAll()
        setNeedsDisplay()
    }

    // MARK: Drawing

    private let body = UIColor(white: 0.62, alpha: 1)
    private let bodyPressed = UIColor(white: 0.88, alpha: 1)
    private let dark = UIColor(white: 0.22, alpha: 1)
    private let darkPressed = UIColor(white: 0.45, alpha: 1)

    override func draw(_ rect: CGRect) {
        let lay = layout

        // Shoulders
        for (c, r, label) in [(Control.l, lay.lRect, "L"), (.r, lay.rRect, "R")] {
            let path = UIBezierPath(roundedRect: r, cornerRadius: r.height / 2)
            (pressed.contains(c) ? bodyPressed : body).setFill()
            path.fill()
            drawLabel(label, in: r, size: 18, color: dark)
        }

        // Select / Start
        for (c, r, label) in [(Control.select, lay.selectRect, "SELECT"), (.start, lay.startRect, "START")] {
            let path = UIBezierPath(roundedRect: r, cornerRadius: r.height / 2)
            (pressed.contains(c) ? darkPressed : dark).setFill()
            path.fill()
            drawLabel(label, in: r, size: 11, color: UIColor(white: 0.75, alpha: 1))
        }

        // D-pad: a cross, each arm lights up on its own.
        let arm = lay.dpadRadius * 0.62, half = lay.dpadRadius
        let cx = lay.dpadCenter.x, cy = lay.dpadCenter.y
        let arms: [(Control, CGRect)] = [
            (.up, CGRect(x: cx - arm / 2, y: cy - half, width: arm, height: half)),
            (.down, CGRect(x: cx - arm / 2, y: cy, width: arm, height: half)),
            (.left, CGRect(x: cx - half, y: cy - arm / 2, width: half, height: arm)),
            (.right, CGRect(x: cx, y: cy - arm / 2, width: half, height: arm)),
        ]
        dark.setFill()
        for (_, r) in arms { UIBezierPath(roundedRect: r, cornerRadius: 6).fill() }
        for (c, r) in arms where pressed.contains(c) {
            darkPressed.setFill()
            UIBezierPath(roundedRect: r, cornerRadius: 6).fill()
        }

        // Face buttons, labelled like the 8BitDo.
        for (c, center) in lay.faceCenters {
            let r = CGRect(x: center.x - lay.faceRadius, y: center.y - lay.faceRadius,
                           width: lay.faceRadius * 2, height: lay.faceRadius * 2)
            (pressed.contains(c) ? darkPressed : dark).setFill()
            UIBezierPath(ovalIn: r).fill()
            let label: String = switch c { case .a: "A"; case .b: "B"; case .x: "X"; default: "Y" }
            drawLabel(label, in: r, size: lay.faceRadius * 0.8, color: UIColor(white: 0.85, alpha: 1))
        }
    }

    private func drawLabel(_ text: String, in rect: CGRect, size: CGFloat, color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: .bold),
            .foregroundColor: color,
        ]
        let s = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: CGPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2), withAttributes: attrs)
    }
}
