import SwiftUI

struct CompletionNoticeView: View {
    static let panelSize = CGSize(width: 312, height: 94)
    static let cardInset: CGFloat = 9
    static let closeButtonSize: CGFloat = 28
    static let closeButtonInset: CGFloat = 8
    let notice: CompletionNotice
    let style: TooltipStyle
    var dismiss: (UUID) -> Void = { _ in }
    var interactionChanged: (CompletionNoticeInteraction, Bool, UUID) -> Void = { _, _, _ in }

    var body: some View {
        CompletionNoticeContent(notice: notice, style: style, dismiss: dismiss, interactionChanged: interactionChanged)
            .id(notice.id)
    }
}

private struct CompletionNoticeContent: View {
    let notice: CompletionNotice
    let style: TooltipStyle
    let dismiss: (UUID) -> Void
    let interactionChanged: (CompletionNoticeInteraction, Bool, UUID) -> Void
    @FocusState private var closeHasKeyboardFocus: Bool
    private enum AccessibilityElement: Hashable { case message, close }
    @AccessibilityFocusState private var accessibilityFocus: AccessibilityElement?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(style == .pixel ? PixelPalette.brightGold : .white.opacity(0.9))
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: style == .pixel ? 0 : 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(notice.heading)
                    .font(.system(size: 14, weight: .semibold, design: style == .pixel ? .monospaced : .default))
                    .foregroundStyle(style == .pixel ? PixelPalette.brightGold : .white)
                    .lineLimit(1)
                Text(notice.title)
                    .font(.system(size: 12, design: style == .pixel ? .monospaced : .default))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(notice.accessibilitySummary)
            .accessibilityFocused($accessibilityFocus, equals: .message)
            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
        .padding(.trailing, CompletionNoticeView.closeButtonSize + 2 * CompletionNoticeView.closeButtonInset)
        .frame(height: 76)
        .background {
            if style == .pixel {
                PixelMenuBackground()
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.055, green: 0.055, blue: 0.065).opacity(0.98))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.14)))
                    .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
            }
        }
        .contentShape(Rectangle())
        .overlay(alignment: .topTrailing) {
            Button { dismiss(notice.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: CompletionNoticeView.closeButtonSize, height: CompletionNoticeView.closeButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(CompletionCloseButtonStyle(style: style, isFocused: closeHasKeyboardFocus || accessibilityFocus == .close))
            .focused($closeHasKeyboardFocus)
            .accessibilityFocused($accessibilityFocus, equals: .close)
            .accessibilityLabel(NSLocalizedString("completion.dismiss", comment: "Dismiss response notice"))
            .help(NSLocalizedString("completion.dismiss", comment: "Dismiss response notice"))
            .onExitCommand {
                if closeHasKeyboardFocus || accessibilityFocus == .close { dismiss(notice.id) }
            }
            .padding(CompletionNoticeView.closeButtonInset)
        }
        .onHover { interactionChanged(.hover, $0, notice.id) }
        .onChange(of: closeHasKeyboardFocus) { _, focused in
            interactionChanged(.keyboardFocus, focused, notice.id)
        }
        .onChange(of: accessibilityFocus) { _, focused in
            interactionChanged(.accessibilityFocus, focused != nil, notice.id)
        }
        .onDisappear {
            for reason in [CompletionNoticeInteraction.hover, .keyboardFocus, .accessibilityFocus] {
                interactionChanged(reason, false, notice.id)
            }
        }
        .padding(CompletionNoticeView.cardInset)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

private struct CompletionCloseButtonStyle: ButtonStyle {
    let style: TooltipStyle
    let isFocused: Bool
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(style == .pixel ? PixelPalette.brightGold : .white.opacity(0.85))
            .background(.white.opacity(configuration.isPressed ? 0.22 : isHovering ? 0.12 : 0.04),
                        in: RoundedRectangle(cornerRadius: style == .pixel ? 0 : 6))
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: style == .pixel ? 0 : 6)
                        .strokeBorder(style == .pixel ? PixelPalette.brightGold : .white, lineWidth: 2)
                }
            }
            .onHover { isHovering = $0 }
    }
}
