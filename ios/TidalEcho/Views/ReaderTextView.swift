import SwiftUI
import UIKit

/// 章节正文。用 UITextView 而不是 SwiftUI 的 Text，是因为共读要的东西 SwiftUI 给不了：
/// 选中区间的字符偏移、选择菜单里塞自己的动作、以及"视口顶部现在是第几个字"。
/// 注意正文里不掺任何额外文字（章节标题在顶栏），否则偏移会整体错位，
/// 划线会挪位、furthest 会失真。
struct ReaderTextView: UIViewRepresentable {
    let text: String
    let charCount: Int
    let annotations: [BookAnnotation]
    let fontSize: Double
    let textColor: UIColor
    let herHighlight: UIColor
    let aiHighlight: UIColor
    let scrollToOffset: Int?
    let onVisibleOffset: (Int) -> Void
    let onMark: (Int, Int, String) -> Void
    let onAnnotate: (Int, Int, String) -> Void
    let onTapAnnotations: ([BookAnnotation]) -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.backgroundColor = .clear
        view.alwaysBounceVertical = true
        view.showsVerticalScrollIndicator = true
        view.textContainerInset = UIEdgeInsets(top: 14, left: 18, bottom: 90, right: 18)
        view.delegate = context.coordinator
        view.contentInsetAdjustmentBehavior = .never

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)

        context.coordinator.textView = view
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        let signature = "\(text.hashValue)#\(fontSize)#\(annotations.map { "\($0.id):\($0.startOff)-\($0.endOff):\($0.author)" }.joined(separator: ","))"
        if coordinator.renderedSignature != signature {
            let keepOffset = coordinator.renderedText == text ? view.contentOffset.y : 0
            coordinator.renderedSignature = signature
            coordinator.renderedText = text
            view.attributedText = attributedChapter()
            view.layoutIfNeeded()
            // 重新上色不该把她读的位置弹走
            view.contentOffset = CGPoint(x: 0, y: keepOffset)
        }

        if let target = scrollToOffset, coordinator.appliedScrollTarget != target {
            coordinator.appliedScrollTarget = target
            DispatchQueue.main.async { coordinator.scroll(to: target) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    private func attributedChapter() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = CGFloat(fontSize) * 0.62
        paragraph.paragraphSpacing = CGFloat(fontSize) * 0.5
        paragraph.firstLineHeadIndent = CGFloat(fontSize) * 2
        paragraph.alignment = .justified

        let font = UIFont(name: "PingFangSC-Regular", size: CGFloat(fontSize))
            ?? UIFont.systemFont(ofSize: CGFloat(fontSize))
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraph
            ]
        )

        let utf16Count = attributed.length
        // 她的先上色，小克的压在上面：他留的话本来就该更显眼一点
        for annotation in annotations.sorted(by: { !$0.isAI && $1.isAI }) {
            let start = ScalarOffset.toUTF16(text, annotation.startOff)
            let end = ScalarOffset.toUTF16(text, annotation.endOff)
            guard end > start, start >= 0, end <= utf16Count else { continue }
            let range = NSRange(location: start, length: end - start)
            attributed.addAttribute(.backgroundColor, value: annotation.isAI ? aiHighlight : herHighlight, range: range)
            if annotation.hasNote {
                attributed.addAttributes([
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: annotation.isAI ? aiHighlight.withAlphaComponent(0.9) : herHighlight.withAlphaComponent(0.9)
                ], range: range)
            }
        }
        return attributed
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: ReaderTextView
        weak var textView: UITextView?
        var renderedSignature = ""
        var renderedText = ""
        var appliedScrollTarget: Int?

        init(parent: ReaderTextView) {
            self.parent = parent
        }

        // MARK: 视口顶部现在读到哪

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let view = textView else { return }
            parent.onVisibleOffset(currentOffset(in: view))
        }

        private func currentOffset(in view: UITextView) -> Int {
            // 滚到底就是这一章读完了，直接报满。不然 furthest 永远差一屏，
            // chapter-done 就永远不会触发。
            if view.contentOffset.y + view.bounds.height >= view.contentSize.height - 8 {
                return parent.charCount
            }
            let point = CGPoint(
                x: view.textContainerInset.left + 2,
                y: view.contentOffset.y + view.textContainerInset.top + 2
            )
            guard let position = view.closestPosition(to: point) else { return 0 }
            let utf16Offset = view.offset(from: view.beginningOfDocument, to: position)
            return min(parent.charCount, ScalarOffset.fromUTF16(parent.text, utf16Offset))
        }

        func scroll(to scalarOffset: Int) {
            guard let view = textView, scalarOffset > 0 else {
                textView?.setContentOffset(.zero, animated: false)
                return
            }
            view.layoutIfNeeded()
            let utf16Offset = ScalarOffset.toUTF16(parent.text, scalarOffset)
            guard let position = view.position(from: view.beginningOfDocument, offset: utf16Offset) else { return }
            let rect = view.caretRect(for: position)
            guard rect.origin.y.isFinite else { return }
            let maxY = max(0, view.contentSize.height - view.bounds.height + view.textContainerInset.bottom)
            view.setContentOffset(CGPoint(x: 0, y: min(max(0, rect.minY - 10), maxY)), animated: false)
        }

        // MARK: 选中之后能做什么

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard range.length > 0 else { return UIMenu(children: suggestedActions) }
            let text = parent.text
            let start = ScalarOffset.fromUTF16(text, range.location)
            let end = ScalarOffset.fromUTF16(text, range.location + range.length)
            guard end > start else { return UIMenu(children: suggestedActions) }
            let quote = ScalarOffset.substring(text, from: start, to: end)

            let mark = UIAction(title: "划线", image: UIImage(systemName: "highlighter")) { [weak self] _ in
                guard let self else { return }
                self.parent.onMark(start, end, quote)
                textView.selectedTextRange = nil
            }
            let annotate = UIAction(title: "写批注", image: UIImage(systemName: "square.and.pencil")) { [weak self] _ in
                guard let self else { return }
                self.parent.onAnnotate(start, end, quote)
                textView.selectedTextRange = nil
            }
            return UIMenu(children: [mark, annotate] + suggestedActions)
        }

        // MARK: 点已有划线 → 看这处说过的话

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = textView, view.selectedTextRange?.isEmpty ?? true else { return }
            let point = recognizer.location(in: view)
            guard let position = view.closestPosition(to: point) else { return }
            let utf16Offset = view.offset(from: view.beginningOfDocument, to: position)
            let offset = ScalarOffset.fromUTF16(parent.text, utf16Offset)
            let hits = parent.annotations.filter { $0.startOff <= offset && $0.endOff > offset }
            guard let first = hits.first else { return }
            // 同一句被划过好几次：整组一起看
            let group = parent.annotations.filter { $0.endOff > first.startOff && $0.startOff < first.endOff }
            parent.onTapAnnotations(group)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
