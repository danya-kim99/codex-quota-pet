import SwiftUI

struct PixelQuotaTooltipView: View {
    nonisolated static let largeCardSize = CGSize(width: 390, height: 180)
    nonisolated static let largePanelSize = CGSize(width: 420, height: 210)
    nonisolated static let largeHistoryCardSize = CGSize(width: 390, height: 260)
    nonisolated static let largeHistoryPanelSize = CGSize(width: 420, height: 290)
    nonisolated static let mediumCardSize = CGSize(width: 312, height: 144)
    nonisolated static let mediumPanelSize = CGSize(width: 336, height: 168)
    nonisolated static let mediumHistoryCardSize = CGSize(width: 312, height: 208)
    nonisolated static let mediumHistoryPanelSize = CGSize(width: 336, height: 232)
    nonisolated static let smallCardSize = CGSize(width: 280, height: 128)
    nonisolated static let smallPanelSize = CGSize(width: 304, height: 148)
    nonisolated static let smallHistoryCardSize = CGSize(width: 280, height: 154)
    nonisolated static let smallHistoryPanelSize = CGSize(width: 304, height: 174)
    nonisolated static let purpleShadowOffset = CGSize(width: 5, height: -5)
    nonisolated static let blackShadowOffset = CGSize(width: 9, height: -9)
    nonisolated static let smallRingSize: CGFloat = 80
    nonisolated static let smallRingLineWidth: CGFloat = 9
    nonisolated static let smallRingChevronSize = CGSize(width: 6, height: 7)
    nonisolated static var smallRingRadius: CGFloat {
        (smallRingSize - smallRingLineWidth) / 2
    }

    let content: QuotaTooltipContent
    let placement: QuotaTooltipView.Placement
    let petSize: PetSize

    private let gold = Color(red: 1, green: 0.76, blue: 0.31)
    private let orange = Color(red: 1, green: 0.34, blue: 0.16)
    private let purple = Color(red: 0.68, green: 0.27, blue: 0.94)

    static func panelSize(for petSize: PetSize, showsHistory: Bool = false) -> CGSize {
        switch petSize {
        case .large: showsHistory ? largeHistoryPanelSize : largePanelSize
        case .medium: showsHistory ? mediumHistoryPanelSize : mediumPanelSize
        case .small: showsHistory ? smallHistoryPanelSize : smallPanelSize
        }
    }

    @ViewBuilder
    var body: some View {
        if petSize == .small {
            smallTooltip
        } else {
            largeTooltip
                .scaleEffect(petSize == .medium ? 0.8 : 1)
                .frame(
                    width: Self.panelSize(for: petSize).width,
                    height: Self.panelSize(
                        for: petSize,
                        showsHistory: content.showsQuotaDynamics
                    ).height
                )
        }
    }

    private var largeTooltip: some View {
        pixelCard(
            size: content.showsQuotaDynamics
                ? Self.largeHistoryCardSize
                : Self.largeCardSize
        ) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Text(localized("pixel.quota.title"))
                        .font(pixelFont(size: 15, weight: .bold))
                        .tracking(0.8)

                    modeBadge

                    Spacer(minLength: 8)

                    Text(percentText)
                        .font(pixelFont(size: 25, weight: .bold))
                        .foregroundStyle(quotaColor)
                        .monospacedDigit()
                        .lineLimit(1)
                }

                pixelProgressBar
                    .padding(.top, 12)

                Rectangle()
                    .fill(PixelPalette.innerBorder)
                    .frame(height: 2)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                resetRow

                if content.showsQuotaDynamics {
                    Rectangle()
                        .fill(PixelPalette.innerBorder)
                        .frame(height: 2)
                        .padding(.top, 14)
                        .padding(.bottom, 10)

                    QuotaHistorySection(
                        presentation: content.history,
                        style: .pixel,
                        quotaColor: quotaColor,
                        currentUnavailable: content.remainingPercent == nil
                    )
                }
            }
            .padding(.horizontal, 19)
            .padding(.vertical, 17)
            .opacity(content.isStale ? 0.62 : 1)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 15)
        .frame(
            width: Self.largePanelSize.width,
            height: content.showsQuotaDynamics
                ? Self.largeHistoryPanelSize.height
                : Self.largePanelSize.height,
            alignment: panelAlignment
        )
        .accessibilityHidden(true)
    }

    private var smallTooltip: some View {
        pixelCard(
            size: content.showsQuotaDynamics
                ? Self.smallHistoryCardSize
                : Self.smallCardSize
        ) {
            HStack(spacing: 14) {
                smallRing

                VStack(alignment: .leading, spacing: 7) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localized("pixel.quota.title"))
                            .font(pixelFont(size: 11, weight: .bold))
                            .tracking(0.4)
                            .lineLimit(1)
                        modeBadge
                    }

                    Rectangle()
                        .fill(PixelPalette.innerBorder)
                        .frame(height: 2)

                    smallResetRows

                    if content.showsQuotaDynamics {
                        Rectangle()
                            .fill(PixelPalette.innerBorder)
                            .frame(height: 2)
                        QuotaHistoryCompactText(
                            presentation: content.history,
                            style: .pixel,
                            color: quotaColor,
                            currentUnavailable: content.remainingPercent == nil
                        )
                    }
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .opacity(content.isStale ? 0.62 : 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(
            width: Self.smallPanelSize.width,
            height: content.showsQuotaDynamics
                ? Self.smallHistoryPanelSize.height
                : Self.smallPanelSize.height,
            alignment: panelAlignment
        )
        .accessibilityHidden(true)
    }

    private func pixelCard<Content: View>(
        size: CGSize,
        @ViewBuilder content cardContent: () -> Content
    ) -> some View {
        cardContent()
            .foregroundStyle(PixelPalette.highlightText)
            .frame(width: size.width, height: size.height)
            .background {
                ZStack {
                    PixelTooltipPanelShape()
                        .fill(.black.opacity(0.58))
                        .offset(
                            x: Self.blackShadowOffset.width,
                            y: Self.blackShadowOffset.height
                        )

                    PixelTooltipPanelShape()
                        .fill(PixelPalette.purple.opacity(0.7))
                        .offset(
                            x: Self.purpleShadowOffset.width,
                            y: Self.purpleShadowOffset.height
                        )

                    PixelTooltipPanelShape()
                        .fill(PixelPalette.background)
                        .overlay {
                            PixelTooltipPanelShape()
                                .stroke(PixelPalette.brightGold, lineWidth: 3)
                        }
                        .overlay {
                            PixelTooltipPanelShape(inset: 6)
                                .stroke(PixelPalette.innerBorder, lineWidth: 2)
                        }
                        .overlay(alignment: .topLeading) {
                            PixelCornerAccent()
                                .foregroundStyle(PixelPalette.orange)
                                .padding(8)
                        }
                        .overlay(alignment: .bottomTrailing) {
                            PixelCornerAccent()
                                .foregroundStyle(PixelPalette.purple)
                                .rotationEffect(.degrees(180))
                                .padding(8)
                        }
                }
            }
            .overlay(alignment: pointerAlignment) {
                pixelPointer
            }
    }

    private var modeBadge: some View {
        HStack(spacing: 4) {
            if content.speedMode == .turbo {
                PixelBolt()
                    .fill(PixelPalette.orange)
                    .frame(width: 7, height: 12)
                    .accessibilityHidden(true)
            }
            Text(content.speedMode.title.uppercased())
                .lineLimit(1)
        }
        .font(pixelFont(size: 10, weight: .bold))
        .foregroundStyle(content.speedMode == .turbo ? PixelPalette.orange : PixelPalette.mutedGold)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(PixelPalette.hoverBackground)
        .overlay {
            Rectangle()
                .stroke(
                    content.speedMode == .turbo ? PixelPalette.orange : PixelPalette.border,
                    lineWidth: 2
                )
        }
    }

    private var pixelProgressBar: some View {
        GeometryReader { geometry in
            let fillWidth = geometry.size.width * content.progressFraction
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(PixelPalette.hoverBackground.opacity(0.75))
                    .overlay { Rectangle().stroke(PixelPalette.border, lineWidth: 2) }

                if fillWidth > 0 {
                    Rectangle()
                        .fill(quotaColor)
                        .frame(width: min(geometry.size.width, fillWidth))

                    if content.progressPresentation == .turbo {
                        PixelChevronPattern()
                            .frame(width: min(geometry.size.width, fillWidth))
                            .clipped()

                        Rectangle()
                            .fill(PixelPalette.highlightText)
                            .frame(width: 3, height: 14)
                            .offset(
                                x: min(
                                    max(0, fillWidth - 3),
                                    geometry.size.width - 3
                                )
                            )
                    }
                }

                if content.remainingPercent == nil {
                    PixelMissingPattern()
                        .foregroundStyle(PixelPalette.disabled)
                }
            }
        }
        .frame(height: 22)
    }

    private var smallRing: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    PixelPalette.hoverBackground,
                    lineWidth: Self.smallRingLineWidth
                )

            if content.progressFraction > 0 {
                Circle()
                    .inset(by: Self.smallRingLineWidth / 2)
                    .trim(from: 0, to: content.progressFraction)
                    .stroke(
                        quotaColor,
                        style: StrokeStyle(
                            lineWidth: Self.smallRingLineWidth,
                            lineCap: .butt
                        )
                    )
                    .rotationEffect(.degrees(-90))
            }

            if content.speedMode == .turbo {
                ForEach(0..<8, id: \.self) { index in
                    let markerFraction = 0.06 + CGFloat(index) * 0.12
                    if markerFraction <= content.progressFraction {
                        PixelRingChevron()
                            .frame(
                                width: Self.smallRingChevronSize.width,
                                height: Self.smallRingChevronSize.height
                            )
                            .offset(y: -Self.smallRingRadius)
                            .rotationEffect(.degrees(360 * markerFraction))
                    }
                }

                PixelBolt()
                    .fill(PixelPalette.orange)
                    .frame(width: 9, height: 15)
                    .offset(y: -Self.smallRingRadius)
                    .accessibilityHidden(true)
            }

            Text(percentText)
                .font(pixelFont(size: 18, weight: .bold))
                .foregroundStyle(quotaColor)
                .monospacedDigit()
        }
        .frame(width: Self.smallRingSize, height: Self.smallRingSize)
    }

    private var resetRow: some View {
        HStack(spacing: 9) {
            PixelTooltipIcon(kind: .clock)
                .frame(width: 14, height: 14)
                .foregroundStyle(PixelPalette.mutedGold)

            if let indicator = content.dayIndicator {
                daySegments(indicator)
                    .frame(width: 63, height: 12)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(localized("pixel.reset.window"))
                    .font(pixelFont(size: 9, weight: .bold))
                    .foregroundStyle(PixelPalette.mutedGold)
                    .tracking(0.5)

                Text(content.resetCountdownText)
                    .font(pixelFont(size: 11, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            if let compactResetText = content.compactResetText {
                HStack(spacing: 5) {
                    PixelTooltipIcon(kind: .calendar)
                        .frame(width: 13, height: 13)
                        .foregroundStyle(PixelPalette.mutedGold)
                    Text(compactResetText)
                        .font(pixelFont(size: 10, weight: .medium))
                        .foregroundStyle(PixelPalette.mutedGold)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var smallResetRows: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                PixelTooltipIcon(kind: .clock)
                    .frame(width: 12, height: 12)
                    .foregroundStyle(PixelPalette.mutedGold)
                Text(content.resetCountdownText)
                    .font(pixelFont(size: 10, weight: .semibold))
                    .lineLimit(2)
            }

            if let compactResetText = content.compactResetText {
                HStack(spacing: 5) {
                    PixelTooltipIcon(kind: .calendar)
                        .frame(width: 12, height: 12)
                        .foregroundStyle(PixelPalette.mutedGold)
                    Text(compactResetText)
                        .font(pixelFont(size: 9, weight: .medium))
                        .foregroundStyle(PixelPalette.mutedGold)
                        .lineLimit(1)
                }
            }
        }
        .minimumScaleFactor(0.8)
    }

    private func daySegments(_ indicator: QuotaTooltipView.DayIndicator) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<indicator.totalSegments, id: \.self) { index in
                Rectangle()
                    .fill(index < indicator.activeSegments ? quotaColor : PixelPalette.hoverBackground)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var pixelPointer: some View {
        switch placement {
        case .below:
            pointer(direction: .up, size: CGSize(width: 27, height: 14)).offset(y: -13)
        case .above:
            pointer(direction: .down, size: CGSize(width: 27, height: 14)).offset(y: 13)
        case .left:
            pointer(direction: .right, size: CGSize(width: 14, height: 27)).offset(x: 13)
        case .right:
            pointer(direction: .left, size: CGSize(width: 14, height: 27)).offset(x: -13)
        }
    }

    private func pointer(
        direction: PixelTooltipPointer.Direction,
        size: CGSize
    ) -> some View {
        PixelTooltipPointer(direction: direction)
            .fill(PixelPalette.background)
            .overlay {
                PixelTooltipPointer(direction: direction)
                    .stroke(PixelPalette.brightGold, lineWidth: 3)
            }
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(true)
    }

    private var panelAlignment: Alignment {
        switch placement {
        case .below: .top
        case .above: .bottom
        case .left, .right: .center
        }
    }

    private var pointerAlignment: Alignment {
        switch placement {
        case .below: .top
        case .above: .bottom
        case .left: .trailing
        case .right: .leading
        }
    }

    private var percentText: String {
        content.remainingPercent.map { "\($0)%" } ?? "—"
    }

    private var quotaColor: Color {
        switch content.quotaLevel {
        case .normal: content.remainingPercent == nil ? PixelPalette.disabled : gold
        case .warning: orange
        case .critical: purple
        }
    }

    private func pixelFont(size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "Pixel quota tooltip")
    }
}

private struct PixelTooltipPanelShape: Shape {
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        let step: CGFloat = 8
        return Path { path in
            path.move(to: CGPoint(x: rect.minX + step, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - step, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - step, y: rect.minY + 4))
            path.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.minY + 4))
            path.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.minY + step))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + step))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - step))
            path.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.maxY - step))
            path.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.maxY - 4))
            path.addLine(to: CGPoint(x: rect.maxX - step, y: rect.maxY - 4))
            path.addLine(to: CGPoint(x: rect.maxX - step, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + step, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + step, y: rect.maxY - 4))
            path.addLine(to: CGPoint(x: rect.minX + 4, y: rect.maxY - 4))
            path.addLine(to: CGPoint(x: rect.minX + 4, y: rect.maxY - step))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - step))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + step))
            path.addLine(to: CGPoint(x: rect.minX + 4, y: rect.minY + step))
            path.addLine(to: CGPoint(x: rect.minX + 4, y: rect.minY + 4))
            path.addLine(to: CGPoint(x: rect.minX + step, y: rect.minY + 4))
            path.closeSubpath()
        }
    }
}

private struct PixelTooltipPointer: Shape {
    enum Direction { case up, down, left, right }
    let direction: Direction

    func path(in rect: CGRect) -> Path {
        Path { path in
            switch direction {
            case .up:
                path.move(to: CGPoint(x: rect.midX - 4, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX + 4, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX + 4, y: rect.minY + 4))
                path.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.maxY - 4))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 4))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - 4))
                path.addLine(to: CGPoint(x: rect.minX + 4, y: rect.maxY - 4))
                path.addLine(to: CGPoint(x: rect.midX - 4, y: rect.minY + 4))
            case .down:
                path.addPath(Self(direction: .up).path(in: rect).applying(
                    CGAffineTransform(translationX: rect.midX, y: rect.midY)
                        .rotated(by: .pi)
                        .translatedBy(x: -rect.midX, y: -rect.midY)
                ))
            case .left:
                path.addPath(Self(direction: .up).path(in: CGRect(x: 0, y: 0, width: rect.height, height: rect.width)).applying(
                    CGAffineTransform(rotationAngle: -.pi / 2)
                        .translatedBy(x: -rect.height, y: 0)
                ))
            case .right:
                path.addPath(Self(direction: .up).path(in: CGRect(x: 0, y: 0, width: rect.height, height: rect.width)).applying(
                    CGAffineTransform(rotationAngle: .pi / 2)
                        .translatedBy(x: 0, y: -rect.width)
                ))
            }
            path.closeSubpath()
        }
    }
}

private struct PixelCornerAccent: View {
    var body: some View {
        HStack(spacing: 3) {
            Rectangle().frame(width: 4, height: 12)
            Rectangle().frame(width: 4, height: 8)
            Rectangle().frame(width: 4, height: 4)
        }
        .frame(width: 18, height: 12, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

private struct PixelChevronPattern: View {
    var body: some View {
        Canvas { context, size in
            var x: CGFloat = 3
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 3))
                path.addLine(to: CGPoint(x: x + 5, y: size.height / 2))
                path.addLine(to: CGPoint(x: x, y: size.height - 3))
                context.stroke(path, with: .color(.white.opacity(0.35)), lineWidth: 2)
                x += 12
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PixelRingChevron: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 1, y: 1))
            path.addLine(to: CGPoint(x: size.width - 1, y: size.height / 2))
            path.addLine(to: CGPoint(x: 1, y: size.height - 1))
            context.stroke(
                path,
                with: .color(PixelPalette.highlightText.opacity(0.55)),
                lineWidth: 2
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PixelBolt: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.maxX * 0.58, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY * 1.08))
            path.addLine(to: CGPoint(x: rect.maxX * 0.43, y: rect.midY * 1.08))
            path.addLine(to: CGPoint(x: rect.maxX * 0.28, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY * 0.76))
            path.addLine(to: CGPoint(x: rect.maxX * 0.58, y: rect.midY * 0.76))
            path.closeSubpath()
        }
    }
}

private struct PixelMissingPattern: View {
    var body: some View {
        Canvas { context, size in
            var x: CGFloat = -size.height
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(path, with: .foreground, lineWidth: 2)
                x += 9
            }
        }
        .accessibilityHidden(true)
    }
}

private struct PixelTooltipIcon: View {
    enum Kind { case clock, calendar }
    let kind: Kind

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 7
            let points: [(Int, Int)] = switch kind {
            case .clock:
                [(2, 0), (3, 0), (4, 0), (1, 1), (5, 1), (0, 2), (3, 2),
                 (6, 2), (0, 3), (3, 3), (4, 3), (6, 3), (0, 4), (6, 4),
                 (1, 5), (5, 5), (2, 6), (3, 6), (4, 6)]
            case .calendar:
                [(1, 0), (2, 0), (4, 0), (5, 0), (0, 1), (3, 1), (6, 1),
                 (0, 2), (1, 2), (2, 2), (3, 2), (4, 2), (5, 2), (6, 2),
                 (0, 3), (6, 3), (0, 4), (2, 4), (4, 4), (6, 4),
                 (0, 5), (2, 5), (4, 5), (6, 5), (0, 6), (1, 6), (2, 6),
                 (3, 6), (4, 6), (5, 6), (6, 6)]
            }
            for point in points {
                context.fill(
                    Path(CGRect(x: CGFloat(point.0) * unit, y: CGFloat(point.1) * unit, width: unit, height: unit)),
                    with: .foreground
                )
            }
        }
        .accessibilityHidden(true)
    }
}
