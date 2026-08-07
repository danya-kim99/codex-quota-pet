import SwiftUI

struct QuotaHistorySection: View {
    enum Style {
        case smooth
        case pixel
    }

    let presentation: QuotaHistoryPresentation
    let style: Style
    let quotaColor: Color

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: style == .pixel ? 4 : 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(NSLocalizedString("history.title", comment: "Local quota history title"))
                    .font(titleFont)
                    .foregroundStyle(secondaryColor)
                    .tracking(style == .pixel ? 0.45 : 0.25)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(presentation.endpointText(locale: locale))
                    .font(valueFont)
                    .foregroundStyle(quotaColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            if let duration = presentation.durationText(locale: locale, compact: false),
               presentation.hasComparableChange {
                Text(duration)
                    .font(durationFont)
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)
            }

            if presentation.points.count >= 2 {
                QuotaHistoryChart(
                    presentation: presentation,
                    lineColor: quotaColor,
                    usesPixelSteps: style == .pixel
                )
                .frame(height: 38)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilitySummary(locale: locale))
    }

    private var titleFont: Font {
        switch style {
        case .smooth: .system(size: 9, weight: .medium, design: .rounded)
        case .pixel: .system(size: 9, weight: .semibold, design: .monospaced)
        }
    }

    private var valueFont: Font {
        switch style {
        case .smooth: .system(size: 11, weight: .medium, design: .rounded)
        case .pixel: .system(size: 11, weight: .semibold, design: .monospaced)
        }
    }

    private var durationFont: Font {
        switch style {
        case .smooth: .system(size: 9, weight: .regular, design: .rounded)
        case .pixel: .system(size: 8, weight: .medium, design: .monospaced)
        }
    }

    private var secondaryColor: Color {
        style == .pixel ? PixelPalette.mutedGold : .secondary
    }
}

struct QuotaHistoryCompactText: View {
    let presentation: QuotaHistoryPresentation
    let style: QuotaHistorySection.Style
    let color: Color

    @Environment(\.locale) private var locale

    var body: some View {
        Text(presentation.compactSummary(locale: locale))
            .font(
                style == .pixel
                    ? .system(size: 9, weight: .semibold, design: .monospaced)
                    : .system(size: 10, weight: .medium, design: .rounded)
            )
            .foregroundStyle(color)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityLabel(presentation.accessibilitySummary(locale: locale))
    }
}

private struct QuotaHistoryChart: View {
    let presentation: QuotaHistoryPresentation
    let lineColor: Color
    let usesPixelSteps: Bool

    private let resetColor = Color(red: 0.68, green: 0.27, blue: 0.94)

    var body: some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) {
            context,
            size in
            guard size.width > 0, size.height > 0 else { return }
            let points = presentation.points
            let plotPoint: (QuotaHistoryPoint) -> CGPoint = { point in
                let range = max(1, presentation.rangeEnd.timeIntervalSince(presentation.rangeStart))
                let elapsed = point.observedAt.timeIntervalSince(presentation.rangeStart)
                let x = min(size.width, max(0, CGFloat(elapsed / range) * size.width))
                let inset: CGFloat = 3
                let fraction = CGFloat(min(100, max(0, point.remainingPercent))) / 100
                let y = inset + (1 - fraction) * max(0, size.height - inset * 2)
                return CGPoint(x: x, y: y)
            }

            for fraction in [CGFloat(0.25), CGFloat(0.75)] {
                var grid = Path()
                let y = size.height * fraction
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(grid, with: .color(.white.opacity(0.08)), lineWidth: 1)
            }

            for index in points.indices where index > points.startIndex {
                let previous = points[points.index(before: index)]
                let current = points[index]
                let start = plotPoint(previous)
                let end = plotPoint(current)

                if current.boundaryBefore == .continuous {
                    var path = Path()
                    path.move(to: start)
                    if usesPixelSteps {
                        path.addLine(to: CGPoint(x: end.x, y: start.y))
                    }
                    path.addLine(to: end)
                    context.stroke(
                        path,
                        with: .color(lineColor),
                        style: StrokeStyle(
                            lineWidth: usesPixelSteps ? 3 : 2,
                            lineCap: usesPixelSteps ? .butt : .round,
                            lineJoin: usesPixelSteps ? .miter : .round
                        )
                    )
                } else if current.boundaryBefore == .reset {
                    var diamond = Path()
                    diamond.move(to: CGPoint(x: end.x, y: end.y - 5))
                    diamond.addLine(to: CGPoint(x: end.x + 5, y: end.y))
                    diamond.addLine(to: CGPoint(x: end.x, y: end.y + 5))
                    diamond.addLine(to: CGPoint(x: end.x - 5, y: end.y))
                    diamond.closeSubpath()
                    context.stroke(diamond, with: .color(resetColor), lineWidth: 2)
                } else if current.boundaryBefore == .gap {
                    var gap = Path()
                    gap.move(to: CGPoint(x: end.x, y: 2))
                    gap.addLine(to: CGPoint(x: end.x, y: size.height - 2))
                    context.stroke(
                        gap,
                        with: .color(.white.opacity(0.42)),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
                }
            }

            if let first = points.first, let last = points.last {
                for point in [plotPoint(first), plotPoint(last)] {
                    let marker = Path(ellipseIn: CGRect(
                        x: point.x - 2.5,
                        y: point.y - 2.5,
                        width: 5,
                        height: 5
                    ))
                    context.fill(marker, with: .color(lineColor))
                }
            }
        }
    }
}
