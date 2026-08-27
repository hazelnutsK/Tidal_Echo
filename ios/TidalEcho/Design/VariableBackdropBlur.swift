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
    /// Distance from the blurred physical edge, normalized to 0...1.
    /// Blur is solid through `fadeFrom`, fades until `fadeTo`, and is fully
    /// clear for the rest of the view. Both endpoints stay inside the frame.
    var fadeFrom: CGFloat = 0
    var fadeTo: CGFloat = 1
    /// Saturation applied to the backdrop *before* it is blurred, matching the
    /// Compose `vibrancy()` effect. 1 leaves colors untouched.
    var saturation: CGFloat = 1

    func makeUIView(context: Context) -> VariableBackdropUIView {
        VariableBackdropUIView(
            radius: radius,
            mask: mask,
            fadeFrom: fadeFrom,
            fadeTo: fadeTo,
            saturation: saturation
        )
    }

    func updateUIView(_ uiView: VariableBackdropUIView, context: Context) {
        uiView.update(
            radius: radius,
            mask: mask,
            fadeFrom: fadeFrom,
            fadeTo: fadeTo,
            saturation: saturation
        )
    }
}

final class VariableBackdropUIView: UIVisualEffectView {
    private static let imageContext = CIContext(options: [.cacheIntermediates: true])

    private var variableBlurFilter: NSObject?
    private var saturationFilter: NSObject?
    private var blurRadius: CGFloat
    private var blurMask: VariableBlurMask
    private var fadeFrom: CGFloat
    private var fadeTo: CGFloat
    private var saturation: CGFloat

    init(
        radius: CGFloat,
        mask: VariableBlurMask,
        fadeFrom: CGFloat,
        fadeTo: CGFloat,
        saturation: CGFloat = 1
    ) {
        blurRadius = radius
        blurMask = mask
        self.fadeFrom = fadeFrom
        self.fadeTo = fadeTo
        self.saturation = saturation
        super.init(effect: UIBlurEffect(style: .regular))
        isUserInteractionEnabled = false
        installFilterIfPossible()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        radius: CGFloat,
        mask: VariableBlurMask,
        fadeFrom: CGFloat,
        fadeTo: CGFloat,
        saturation: CGFloat
    ) {
        let saturationChanged = saturation != self.saturation
        guard radius != blurRadius
            || mask != blurMask
            || fadeFrom != self.fadeFrom
            || fadeTo != self.fadeTo
            || saturationChanged
        else { return }
        blurRadius = radius
        blurMask = mask
        self.fadeFrom = fadeFrom
        self.fadeTo = fadeTo
        self.saturation = saturation
        // Crossing the 1.0 boundary adds or removes a filter, so the chain has
        // to be rebuilt rather than just re-valued.
        if saturationChanged {
            installFilterIfPossible()
        } else {
            applyFilterValues()
        }
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

    private func makeFilter(named name: String) -> NSObject? {
        let className = String("retliFAC".reversed())
        let selectorName = String(":epyThtiWretlif".reversed())
        guard
            let filterClass = NSClassFromString(className) as? NSObject.Type,
            let filter = filterClass
                .perform(NSSelectorFromString(selectorName), with: name)?
                .takeUnretainedValue() as? NSObject
        else { return nil }
        return filter
    }

    private func installFilterIfPossible() {
        guard let backdropLayer = subviews.first?.layer else { return }

        if variableBlurFilter == nil {
            variableBlurFilter = makeFilter(named: "variableBlur")
        }
        if saturationFilter == nil, saturation != 1 {
            saturationFilter = makeFilter(named: "colorSaturate")
        }

        applyFilterValues()

        // Saturate before blurring, mirroring the Compose backdrop's
        // `vibrancy()` → `blur()` order: boosting afterwards would amplify the
        // averaged mush instead of the colors that fed it.
        var chain: [NSObject] = []
        if saturation != 1, let saturationFilter {
            chain.append(saturationFilter)
        }
        if let variableBlurFilter {
            chain.append(variableBlurFilter)
        }
        if !chain.isEmpty {
            backdropLayer.filters = chain
        }

        // Remove UIVisualEffectView's system gray/tint layers. Only the live
        // backdrop layer and our explicit SwiftUI tint remain visible.
        for subview in subviews.dropFirst() {
            subview.alpha = 0
        }
    }

    private func applyFilterValues() {
        saturationFilter?.setValue(saturation, forKey: "inputAmount")
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
        let solidEnd = min(max(fadeFrom, 0), 1)
        let clearStart = min(max(fadeTo, solidEnd + 0.001), 1)

        // Core Image's origin is bottom-left. For a top blur, the black
        // (full-alpha) endpoint therefore has the larger y coordinate. For a
        // bottom blur the mapping is mirrored. Outside these two points the
        // gradient clamps to solid/clear, so the view boundary is already at
        // zero blur instead of cutting a still-active filter.
        switch blurMask {
        case .blurredTopClearBottom:
            gradient.point0 = CGPoint(x: 0, y: height * (1 - solidEnd))
            gradient.point1 = CGPoint(x: 0, y: height * (1 - clearStart))
        case .clearTopBlurredBottom:
            gradient.point0 = CGPoint(x: 0, y: height * solidEnd)
            gradient.point1 = CGPoint(x: 0, y: height * clearStart)
        case .solid:
            break
        }

        guard let output = gradient.outputImage else { return nil }
        return Self.imageContext.createCGImage(output, from: bounds)
    }
}
