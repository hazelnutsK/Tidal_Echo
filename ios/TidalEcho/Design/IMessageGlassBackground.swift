import SwiftUI
import UIKit

/// A background-only native Liquid Glass surface. No label, image, TextField,
/// or button is hosted in its effect tree. Keeping UIKit's backdrop as a sibling
/// below SwiftUI content prevents glass composition from sampling the controls.
struct IMessageGlassBackground: UIViewRepresentable {
    let cornerRadius: CGFloat

    func makeUIView(context: Context) -> UIVisualEffectView {
        let glass = UIGlassEffect(style: .clear)
        let view = UIVisualEffectView(effect: glass)
        view.isUserInteractionEnabled = false
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = cornerRadius
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        view.layer.cornerRadius = cornerRadius
    }
}
