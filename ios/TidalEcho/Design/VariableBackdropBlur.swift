import CoreImage.CIFilterBuiltins
import QuartzCore
import SwiftUI
import UIKit

enum VariableBlurMask: Equatable {
    case blurredTopClearBottom
    case clearTopBlurredBottom
    case solid
}

/// A live backdrop blur adapted from jtrivedi/VariableBlurView and
/// nikstar/VariableBlur. `CAFilter` is private API, so this is intended for
/// the app's personal sideloaded build rather than App Store distribution.
struct VariableBackdropBlur: UIViewRepresentable {
    var radius: CGFloat = 18
    var mask: VariableBlurMask = .blurredTopClearBottom
    var startOffset: CGFloat = -0.08

    func makeUIView(context: Context) -> VariableBackdropUIView {
        VariableBackdropUIView(radius: radius, mask: mask, startOffset: startOffset)
    }

    func updateUIView(_ uiView: VariableBackdropUIView, context: Context) {
        uiView.update(radius: radius, mask: mask, startOffset: startOffset)
    }
}

final class VariableBackdropUIView: UIVisualEffectView {
    private static let imageContext = CIContext(options: [.cacheIntermediates: true])

    private var variableBlurFilter: NSObject?
    private var blurRadius: CGFloat
    private var blurMask: VariableBlurMask
    private var startOffset: CGFloat

    init(radius: CGFloat, mask: VariableBlurMask, startOffset: CGFloat) {
        blurRadius = radius
        blurMask = mask
        self.startOffset = startOffset
        super.init(effect: UIBlurEffect(style: .regular))
        isUserInteractionEnabled = false
        installFilterIfPossible()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(radius: CGFloat, mask: VariableBlurMask, startOffset: CGFloat) {
        guard radius != blurRadius || mask != blurMask || startOffset != self.startOffset else { return }
        blurRadius = radius
        blurMask = mask
        self.startOffset = startOffset
        applyFilterValues()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        installFilterIfPossible()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let window, let backdropLayer = subviews.first?.layer else { return }
        backdropLayer.setValue(window.traitCollection.displayScale, forKey: "scale")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        // Calling super here crashes on some iOS 16 builds after replacing the
        // visual-effect filters. Reinstalling in layoutSubviews is sufficient.
        installFilterIfPossible()
    }

    private func installFilterIfPossible() {
        guard let backdropLayer = subviews.first?.layer else { return }

        if variableBlurFilter == nil {
            let className = String("retliFAC".reversed())
            let selectorName = String(":epyThtiWretlif".reversed())
            guard
                let filterClass = NSClassFromString(className) as? NSObject.Type,
                let filter = filterClass
                    .perform(NSSelectorFromString(selectorName), with: "variableBlur")?
                    .takeUnretainedValue() as? NSObject
            else { return }
            variableBlurFilter = filter
        }

        applyFilterValues()
        if let variableBlurFilter {
            backdropLayer.filters = [variableBlurFilter]
        }

        // Remove UIVisualEffectView's system gray/tint layers. Only the live
        // backdrop layer and our explicit SwiftUI tint remain visible.
        for subview in subviews.dropFirst() {
            subview.alpha = 0
        }
    }

    private func applyFilterValues() {
        guard let variableBlurFilter else { return }
        variableBlurFilter.setValue(blurRadius, forKey: "inputRadius")
        variableBlurFilter.setValue(makeMaskImage(), forKey: "inputMaskImage")
        variableBlurFilter.setValue(true, forKey: "inputNormalizeEdges")
    }

    private func makeMaskImage(width: CGFloat = 100, height: CGFloat = 100) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)

        if blurMask == .solid {
            return Self.imageContext.createCGImage(
                CIImage(color: CIColor.black).cropped(to: bounds),
                from: bounds
            )
        }

        let gradient = CIFilter.linearGradient()
        gradient.color0 = CIColor.black
        gradient.color1 = CIColor.clear
        gradient.point0 = CGPoint(x: 0, y: height)
        gradient.point1 = CGPoint(x: 0, y: startOffset * height)

        if blurMask == .clearTopBlurredBottom {
            gradient.point0.y = 0
            gradient.point1.y = height - gradient.point1.y
        }

        guard let output = gradient.outputImage else { return nil }
        return Self.imageContext.createCGImage(output, from: bounds)
    }
}
