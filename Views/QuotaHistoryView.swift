import SwiftUI

struct QuotaHistorySection: View {
    enum Style {
        case smooth
        case pixel
    }

    let presentation: QuotaHistoryPresentation
    let style: Style
    let quotaColor: Color
    let currentUnavailable: Bool

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

                Text(presentation.compactSummary(
                    locale: locale,
                    liveCurrentUnavailable: currentUnavailable
                ))
                    .font(valueFont)
                    .foregroundStyle(quotaColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            if presentation.points.count >= 2 {
                QuotaHistoryChart(
                    presentation: presentation,
                    lineColor: quotaColor,
                    labelColor: secondaryColor,
                    usesPixelSteps: style == .pixel,
                    currentUnavailable: currentUnavailable
                )
                .frame(height: 52)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilitySummary(
            locale: locale,
            liveCurrentUnavailable: currentUnavailable
        ))
    }

    private var titleFont: Font {
        switch style {
        case .smooth: .system(size: 10, weight: .medium, design: .rounded)
        case .pixel: .system(size: 10, weight: .semibold, design: .monospaced)
        }
    }

    private var valueFont: Font {
        switch style {
        case .smooth: .system(size: 11, weight: .medium, design: .rounded)
        case .pixel: .system(size: 11, weight: .semibold, design: .monospaced)
        }
    }

    private var secondaryColor: Color {
        style == .pixel ? PixelPalette.mutedGold : .white.opacity(0.62)
    }
}

struct QuotaHistoryCompactText: View {
    let presentation: QuotaHistoryPresentation
    let style: QuotaHistorySection.Style
    let color: Color
    let currentUnavailable: Bool

    @Environment(\.locale) private var locale

    var body: some View {
        Text(presentation.compactSummary(
            locale: locale,
            liveCurrentUnavailable: currentUnavailable
        ))
            .font(
                style == .pixel
                    ? .system(size: 9, weight: .semibold, design: .monospaced)
                    : .system(size: 10, weight: .medium, design: .rounded)
            )
            .foregroundStyle(color)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityLabel(presentation.accessibilitySummary(
                locale: locale,
                liveCurrentUnavailable: currentUnavailable
            ))
    }
}

private struct QuotaHistoryChart: View {
    let presentation: QuotaHistoryPresentation
    let lineColor: Color
    let labelColor: Color
    let usesPixelSteps: Bool
    let currentUnavailable: Bool

    private let resetColor = Color(red: 0.68, green: 0.27, blue: 0.94)

    private var axisFont: Font {
        .system(
            size: 10,
            weight: .medium,
            design: usesPixelSteps ? .monospaced : .rounded
        )
    }

    private var boundaryFont: Font {
        .system(
            size: 10,
            weight: .semibold,
            design: usesPixelSteps ? .monospaced : .rounded
        )
    }

    var body: some View {
        let rangeStartLabel = NSLocalizedString(
            "history.chart.range_start",
            comment: "Quota history chart range start"
        )
        let nowLabel = NSLocalizedString(
            "history.chart.now",
            comment: "Quota history chart current time"
        )
        let gapLabel = NSLocalizedString(
            "history.chart.gap",
            comment: "Quota history chart continuity gap"
        )
        let resetLabel = NSLocalizedString(
            "history.chart.reset",
            comment: "Quota history chart reset boundary"
        )

        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) {
            context,
            size in
            guard size.width > 56, size.height > 32 else { return }
            let points = presentation.points
            let plotRect = CGRect(
                x: 34,
                y: 10,
                width: size.width - 40,
                height: size.height - 23
            )
            let plotPoint: (QuotaHistoryPoint) -> CGPoint = { point in
                let range = max(1, presentation.rangeEnd.timeIntervalSince(presentation.rangeStart))
                let elapsed = point.observedAt.timeIntervalSince(presentation.rangeStart)
                let x = plotRect.minX
                    + min(1, max(0, CGFloat(elapsed / range))) * plotRect.width
                let yRange = max(
                    1,
                    presentation.yDomain.upperBound - presentation.yDomain.lowerBound
                )
                let fraction = min(
                    1,
                    max(
                        0,
                        CGFloat(point.remainingPercent - presentation.yDomain.lowerBound)
                            / CGFloat(yRange)
                    )
                )
                let y = plotRect.minY + (1 - fraction) * plotRect.height
                return CGPoint(x: x, y: y)
            }

            for fraction in [CGFloat(0.25), CGFloat(0.75)] {
                var grid = Path()
                let y = plotRect.minY + plotRect.height * fraction
                grid.move(to: CGPoint(x: plotRect.minX, y: y))
                grid.addLine(to: CGPoint(x: plotRect.maxX, y: y))
                context.stroke(grid, with: .color(.white.opacity(0.08)), lineWidth: 1)
            }

            context.draw(
                Text("\(presentation.yDomain.upperBound)%")
                    .font(axisFont)
                    .foregroundStyle(labelColor),
                at: CGPoint(x: plotRect.minX - 4, y: plotRect.minY),
                anchor: .trailing
            )
            context.draw(
                Text("\(presentation.yDomain.lowerBound)%")
                    .font(axisFont)
                    .foregroundStyle(labelColor),
                at: CGPoint(x: plotRect.minX - 4, y: plotRect.maxY),
                anchor: .trailing
            )
            context.draw(
                Text(rangeStartLabel).font(axisFont).foregroundStyle(labelColor),
                at: CGPoint(x: plotRect.minX + 10, y: size.height),
                anchor: .bottomLeading
            )
            context.draw(
                Text(nowLabel).font(axisFont).foregroundStyle(labelColor),
                at: CGPoint(x: plotRect.maxX, y: size.height),
                anchor: .bottomTrailing
            )

            for gapRange in presentation.gapRanges {
                let xPositions = gapRange.map { plotPoint(points[$0]).x }
                guard let minimumX = xPositions.min(),
                      let maximumX = xPositions.max() else { continue }
                let gapRect = CGRect(
                    x: minimumX,
                    y: plotRect.minY,
                    width: maximumX - minimumX,
                    height: plotRect.height
                )
                let gap = Path(gapRect)
                context.fill(gap, with: .color(.white.opacity(0.035)))
                context.stroke(
                    gap,
                    with: .color(.white.opacity(0.42)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
                if gapRange == presentation.gapRanges.last, gapRect.width >= 44 {
                    context.draw(
                        Text(gapLabel)
                            .font(boundaryFont)
                            .foregroundStyle(labelColor),
                        at: CGPoint(x: gapRect.midX, y: 0),
                        anchor: .top
                    )
                }
            }

            let latestResetIndex = points.indices.reversed().first {
                points[$0].boundaryBefore == .reset
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
                    let resetPoint = CGPoint(
                        x: (start.x + end.x) / 2,
                        y: plotRect.midY
                    )
                    var diamond = Path()
                    diamond.move(to: CGPoint(x: resetPoint.x, y: resetPoint.y - 5))
                    diamond.addLine(to: CGPoint(x: resetPoint.x + 5, y: resetPoint.y))
                    diamond.addLine(to: CGPoint(x: resetPoint.x, y: resetPoint.y + 5))
                    diamond.addLine(to: CGPoint(x: resetPoint.x - 5, y: resetPoint.y))
                    diamond.closeSubpath()
                    context.fill(diamond, with: .color(.black.opacity(0.72)))
                    context.stroke(diamond, with: .color(resetColor), lineWidth: 2)
                    if index == latestResetIndex {
                        let labelX = min(
                            plotRect.maxX - 20,
                            max(plotRect.minX + 20, resetPoint.x)
                        )
                        context.draw(
                            Text(resetLabel)
                                .font(boundaryFont)
                                .foregroundStyle(resetColor),
                            at: CGPoint(x: labelX, y: 0),
                            anchor: .top
                        )
                    }
                }
            }

            if let first = points.first {
                let point = plotPoint(first)
                let marker = Path(ellipseIn: CGRect(
                    x: point.x - 2.5,
                    y: point.y - 2.5,
                    width: 5,
                    height: 5
                ))
                context.fill(marker, with: .color(lineColor))
            }
            if !currentUnavailable, let last = points.last {
                let point = plotPoint(last)
                let outerMarker = Path(ellipseIn: CGRect(
                    x: point.x - 4.5,
                    y: point.y - 4.5,
                    width: 9,
                    height: 9
                ))
                context.fill(outerMarker, with: .color(.black.opacity(0.72)))
                context.stroke(outerMarker, with: .color(lineColor), lineWidth: 2)
                let centerMarker = Path(ellipseIn: CGRect(
                    x: point.x - 1.5,
                    y: point.y - 1.5,
                    width: 3,
                    height: 3
                ))
                context.fill(centerMarker, with: .color(lineColor))
            }
        }
    }
}
