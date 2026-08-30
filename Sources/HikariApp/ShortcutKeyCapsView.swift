import SwiftUI

struct ShortcutKeyCapsView: View {
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 2 : 4) {
            keyCap { Text("^") }
            plus
            keyCap { Image(systemName: "command") }
            plus
            keyCap { Text("Q") }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Control Command Q")
    }

    private var plus: some View {
        Text("+")
            .font(compact ? .caption2 : .caption)
            .foregroundStyle(.secondary)
    }

    private func keyCap<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .font(.system(
                size: compact ? 9 : 11,
                weight: .semibold,
                design: .rounded
            ))
            .frame(
                minWidth: compact ? 17 : 22,
                minHeight: compact ? 16 : 20
            )
            .background(
                Color.primary.opacity(0.08),
                in: RoundedRectangle(
                    cornerRadius: compact ? 3 : 5,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: compact ? 3 : 5,
                    style: .continuous
                )
                .stroke(Color.primary.opacity(0.18), lineWidth: 0.75)
            }
    }
}
