import SwiftUI
import UIKit

/// A small shape that loops a scale/opacity animation forever (the live dot's ripple, the breathing step ring…).
///
/// SwiftUI's `repeatForever` animations make the interface redraw every frame, 120 times a second, for as long as they
/// run. Here Core Animation plays the loop outside the app, so it costs nothing per frame. Same shape, same timing curves.
struct LoopingShape: UIViewRepresentable {
    enum Shape: Equatable { case ring(lineWidth: CGFloat), capsule }

    struct Loop: Equatable {
        var scale: (from: CGFloat, to: CGFloat) = (1, 1)
        var opacity: (from: Float, to: Float) = (1, 1)
        var duration: Double
        var autoreverses: Bool
        var easeInOut: Bool   // false: ease out

        static func == (a: Loop, b: Loop) -> Bool {
            a.scale == b.scale && a.opacity == b.opacity && a.duration == b.duration && a.autoreverses == b.autoreverses && a.easeInOut == b.easeInOut
        }
    }

    var shape: Shape
    var color: Color
    var loop: Loop

    func makeUIView(context: Context) -> LoopingShapeView { LoopingShapeView() }

    func updateUIView(_ view: LoopingShapeView, context: Context) {
        view.configure(shape: shape, color: UIColor(color), loop: loop)
    }
}

final class LoopingShapeView: UIView {
    private let shapeLayer = CAShapeLayer()
    private var shape: LoopingShape.Shape = .capsule
    private var loop: LoopingShape.Loop?

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.addSublayer(shapeLayer)
        NotificationCenter.default.addObserver(self, selector: #selector(restart), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(shape: LoopingShape.Shape, color: UIColor, loop: LoopingShape.Loop) {
        let reshape = shape != self.shape
        self.shape = shape
        switch shape {
        case .ring(let width):
            shapeLayer.fillColor = nil
            shapeLayer.strokeColor = color.cgColor
            shapeLayer.lineWidth = width
        case .capsule:
            shapeLayer.fillColor = color.cgColor
            shapeLayer.strokeColor = nil
        }
        if reshape { setNeedsLayout() }
        if loop != self.loop {
            self.loop = loop
            restart()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.frame = bounds
        switch shape {
        case .ring: shapeLayer.path = UIBezierPath(ovalIn: bounds).cgPath
        case .capsule: shapeLayer.path = UIBezierPath(roundedRect: bounds, cornerRadius: min(bounds.width, bounds.height) / 2).cgPath
        }
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { restart() }
    }

    @objc private func restart() {
        shapeLayer.removeAnimation(forKey: "loop")
        guard let loop else { return }
        shapeLayer.opacity = loop.opacity.from
        shapeLayer.transform = CATransform3DMakeScale(loop.scale.from, loop.scale.from, 1)
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = loop.scale.from
        scale.toValue = loop.scale.to
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = loop.opacity.from
        opacity.toValue = loop.opacity.to
        let group = CAAnimationGroup()
        group.animations = [scale, opacity]
        group.duration = loop.duration
        group.autoreverses = loop.autoreverses
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: loop.easeInOut ? .easeInEaseOut : .easeOut)
        group.isRemovedOnCompletion = false
        shapeLayer.add(group, forKey: "loop")
    }
}
