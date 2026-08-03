import SwiftUI

struct QuotaTooltipView: View {
    enum Placement: Equatable {
        case above
        case below
        case left
        case right
    }

    enum QuotaLevel: Equatable {
        case normal
        case warning
        case critical
    }

    enum ProgressPresentation: Equatable {
        case standard
        case turbo
    }

    struct DayIndicator: Equatable {
        let activeSegments: Int
        let totalSegments: Int
    }

    static let cardWidth: CGFloat = 320
    static let panelSize = CGSize(width: cardWidth + 40, height: 178)
    static let smallCardSize = CGSize(width: 248, height: 112)
    static let smallPanelSize = CGSize(width: 272, height: 132)
    private static let smallRingSize: CGFloat = 70
    private static let smallRingLineWidth: CGFloat = 8
    private static var smallRingRadius: CGFloat {
        (smallRingSize - smallRingLineWidth) / 2
    }
    // Gold sprite states render at roughly 214–216 pt inside BlackHoleView.
    static let petAnchorHalfSize = CGSize(width: 108, height: 64)

    let appState: AppState
    let placement: Placement

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    private let gold = Color(red: 1, green: 0.76, blue: 0.31)
    private let orange = Color(red: 1, green: 0.34, blue: 0.16)
    private let purple = Color(red: 0.68, green: 0.27, blue: 0.94)
    private let cardColor = Color(red: 0.065, green: 0.07, blue: 0.08)

    init(appState: AppState, placement: Placement = .below) {
        self.appState = appState
        self.placement = placement
    }

    private var remainingPercent: Int? {
        appState.quota?.primary?.remainingPercent
    }

    private var speedMode: SpeedMode {
        appState.speedMode
    }

    private var resetDate: Date? {
        appState.quota?.primary?.resetDate
    }

    private var dayIndicator: DayIndicator? {
        Self.dayIndicator(
            resetDate: resetDate,
            now: Date(),
            windowDurationMinutes: appState.quota?.primary?.windowDurationMins
        )
    }

    private var quotaColor: Color {
        switch Self.quotaLevel(for: remainingPercent) {
        case .normal: gold
        case .warning: orange
        case .critical: purple
        }
    }

    @ViewBuilder
    var body: some View {
        if appState.petSize == .small {
            smallTooltipContent
        } else {
            let scaledPanelSize = Self.panelSize(for: appState.petSize)

            tooltipContent
                .scaleEffect(appState.petSize.scale)
                .frame(width: scaledPanelSize.width, height: scaledPanelSize.height)
        }
    }

    private var smallTooltipContent: some View {
        HStack(spacing: 12) {
            smallCircularProgress

            VStack(alignment: .leading, spacing: 7) {
                Text(NSLocalizedString("quota.available", comment: "Quota card title"))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .lineLimit(1)

                Divider()
                    .overlay(.white.opacity(0.14))

                smallResetRows
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(width: Self.smallCardSize.width, height: Self.smallCardSize.height)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.18))
        }
        .overlay(alignment: pointerAlignment) {
            tooltipPointer
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(
            width: Self.smallPanelSize.width,
            height: Self.smallPanelSize.height,
            alignment: panelAlignment
        )
    }

    private var smallCircularProgress: some View {
        ZStack {
            Circle()
                .strokeBorder(.white.opacity(0.13), lineWidth: Self.smallRingLineWidth)

            if progressFraction > 0 {
                Circle()
                    .inset(by: Self.smallRingLineWidth / 2)
                    .trim(from: 0, to: progressFraction)
                    .stroke(
                        quotaColor,
                        style: StrokeStyle(
                            lineWidth: Self.smallRingLineWidth,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(-90))
            }

            if speedMode == .turbo {
                ForEach(1..<10, id: \.self) { index in
                    let fraction = CGFloat(index) / 10
                    if fraction <= progressFraction {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 5, weight: .bold))
                            .foregroundStyle(.white.opacity(0.45))
                            .offset(y: -Self.smallRingRadius)
                            .rotationEffect(.degrees(Double(fraction) * 360))
                            .accessibilityHidden(true)
                    }
                }

                Circle()
                    .fill(cardColor)
                    .overlay {
                        Circle().stroke(quotaColor, lineWidth: 1.5)
                    }
                    .frame(width: 24, height: 24)
                    .overlay {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(quotaColor)
                    }
                    .offset(y: -Self.smallRingRadius)
                    .accessibilityHidden(true)
            }

            Text(remainingPercent.map { "\($0)%" } ?? "—")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: Self.smallRingSize, height: Self.smallRingSize)
        .accessibilityRepresentation {
            ProgressView(value: Double(remainingPercent ?? 0), total: 100) {
                Text(NSLocalizedString("quota.available", comment: "Progress label"))
            }
        }
    }

    private var smallResetRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "timer")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(daysUntilResetText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }

            if let resetDate {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(compactResetText(resetDate))
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(resetAccessibilityLabel)
    }

    private var tooltipContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text(NSLocalizedString("quota.available", comment: "Quota card title"))
                    .font(.system(size: 16, weight: .medium, design: .rounded))

                Spacer(minLength: 16)

                Text(remainingPercent.map { "\($0)%" } ?? "—")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(quotaColor)
                    .monospacedDigit()
            }

            progressBar
                .padding(.top, 10)

            Divider()
                .overlay(.white.opacity(0.14))
                .padding(.top, 16)
                .padding(.bottom, 14)

            resetRow
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(width: Self.cardWidth)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.18))
        }
        .overlay(alignment: pointerAlignment) {
            tooltipPointer
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(
            width: Self.panelSize.width,
            height: Self.panelSize.height,
            alignment: panelAlignment
        )
    }

    static func panelSize(for petSize: PetSize) -> CGSize {
        petSize == .small ? smallPanelSize : panelSize(forScale: petSize.scale)
    }

    static func panelSize(forScale scale: CGFloat) -> CGSize {
        if scale <= PetSize.small.scale {
            return smallPanelSize
        }
        return CGSize(width: panelSize.width * scale, height: panelSize.height * scale)
    }

    @ViewBuilder
    private var tooltipPointer: some View {
        switch placement {
        case .below:
            pointer(direction: .up, size: CGSize(width: 22, height: 11))
                .offset(y: -11)
        case .above:
            pointer(direction: .down, size: CGSize(width: 22, height: 11))
                .offset(y: 11)
        case .left:
            pointer(direction: .right, size: CGSize(width: 11, height: 22))
                .offset(x: 11)
        case .right:
            pointer(direction: .left, size: CGSize(width: 11, height: 22))
                .offset(x: -11)
        }
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

    private func pointer(
        direction: TooltipPointer.Direction,
        size: CGSize
    ) -> some View {
        TooltipPointer(direction: direction)
            .fill(cardColor)
            .stroke(.white.opacity(0.18), lineWidth: 1)
            .frame(width: size.width, height: size.height)
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            switch Self.progressPresentation(for: speedMode) {
            case .standard:
                standardProgressBar(in: geometry.size)
            case .turbo:
                turboProgressBar(in: geometry.size)
            }
        }
        .frame(height: 28)
        .accessibilityRepresentation {
            ProgressView(value: Double(remainingPercent ?? 0), total: 100) {
                Text(NSLocalizedString("quota.available", comment: "Progress label"))
            }
        }
    }

    private func standardProgressBar(in size: CGSize) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.13))
            Capsule()
                .fill(quotaColor)
                .frame(width: size.width * progressFraction)
        }
        .frame(height: 10)
        .frame(maxHeight: .infinity)
    }

    private func turboProgressBar(in size: CGSize) -> some View {
        let iconSize: CGFloat = 28
        let trackInset = iconSize / 2
        let trackWidth = max(0, size.width - trackInset)
        let fillWidth = trackWidth * progressFraction

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(.white.opacity(0.13))
                .frame(width: trackWidth, height: 12)
                .offset(x: trackInset)

            if fillWidth > 0 {
                ZStack {
                    Capsule().fill(quotaColor)
                    TurboChevronPattern()
                        .clipShape(Capsule())
                }
                .frame(width: fillWidth, height: 12)
                .offset(x: trackInset)

                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: 3, height: 18)
                    .shadow(color: quotaColor.opacity(0.9), radius: 6)
                    .offset(x: max(trackInset, trackInset + fillWidth - 3))
            }

            Circle()
                .fill(cardColor)
                .overlay {
                    Circle().stroke(quotaColor, lineWidth: 1.5)
                }
                .frame(width: iconSize, height: iconSize)
                .overlay {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(quotaColor)
                }
        }
    }

    private var progressFraction: CGFloat {
        CGFloat(remainingPercent ?? 0) / 100
    }

    private var resetRow: some View {
        HStack(spacing: 8) {
            if let dayIndicator {
                daySegments(dayIndicator)
                    .frame(width: 64, height: 14)
            }

            Text(daysUntilResetText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)

            Spacer(minLength: 2)

            if let resetDate {
                Text(compactResetText(resetDate))
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(resetAccessibilityLabel)
    }

    private func daySegments(_ indicator: DayIndicator) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<indicator.totalSegments, id: \.self) { index in
                Capsule()
                    .fill(
                        index < indicator.activeSegments
                            ? quotaColor
                            : .white.opacity(0.18)
                    )
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var daysUntilResetText: String {
        guard let dayIndicator else {
            return NSLocalizedString("reset.unavailable", comment: "Missing reset time")
        }

        let dayCount = Self.localizedDayCount(
            dayIndicator.activeSegments,
            locale: locale,
            calendar: calendar
        )

        return String(
            format: NSLocalizedString("reset.days.remaining", comment: "Days until reset"),
            locale: locale,
            dayCount
        )
    }

    private func compactResetText(_ date: Date) -> String {
        let parts = Self.resetDateParts(
            date,
            relativeTo: Date(),
            locale: locale,
            calendar: calendar
        )
        return String(
            format: NSLocalizedString("reset.compact.absolute", comment: "Compact reset time"),
            locale: locale,
            parts.date,
            parts.time
        )
    }

    private var resetAccessibilityLabel: String {
        guard let resetDate else { return daysUntilResetText }
        return "\(daysUntilResetText), \(compactResetText(resetDate))"
    }

    static func progressPresentation(for speedMode: SpeedMode) -> ProgressPresentation {
        speedMode == .turbo ? .turbo : .standard
    }

    static func dayIndicator(
        resetDate: Date?,
        now: Date,
        windowDurationMinutes: Int64?
    ) -> DayIndicator? {
        guard let resetDate else { return nil }

        let remainingDays = max(0, Int(resetDate.timeIntervalSince(now) / 86_400))
        let totalSegments: Int
        if let windowDurationMinutes, windowDurationMinutes > 0 {
            totalSegments = max(1, Int(ceil(Double(windowDurationMinutes) / 1_440)))
        } else {
            totalSegments = max(1, remainingDays)
        }

        return DayIndicator(
            activeSegments: min(remainingDays, totalSegments),
            totalSegments: totalSegments
        )
    }

    static func localizedDayCount(
        _ dayCount: Int,
        locale: Locale,
        calendar: Calendar
    ) -> String {
        let formatter = DateComponentsFormatter()
        var localizedCalendar = calendar
        localizedCalendar.locale = locale
        formatter.calendar = localizedCalendar
        formatter.allowedUnits = [.day]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        return formatter.string(from: DateComponents(day: dayCount)) ?? "\(dayCount)"
    }

    static func quotaLevel(for remainingPercent: Int?) -> QuotaLevel {
        guard let remainingPercent else { return .normal }
        if remainingPercent < 10 { return .critical }
        if remainingPercent < 30 { return .warning }
        return .normal
    }

    static func resetDateParts(
        _ date: Date,
        relativeTo now: Date,
        locale: Locale,
        calendar: Calendar
    ) -> (date: String, time: String) {
        let isCurrentYear = calendar.component(.year, from: date)
            == calendar.component(.year, from: now)

        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.calendar = calendar
        dateFormatter.setLocalizedDateFormatFromTemplate(
            isCurrentYear ? "dMMM" : "dMMMy"
        )

        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.calendar = calendar
        timeFormatter.setLocalizedDateFormatFromTemplate("jm")

        return (dateFormatter.string(from: date), timeFormatter.string(from: date))
    }

    static func accessibilitySummary(
        remainingPercent: Int?,
        speedMode: SpeedMode,
        connectionState: ConnectionState,
        resetDate: Date?
    ) -> String {
        var details: [String] = []
        if let remainingPercent {
            details.append(
                String(
                    format: NSLocalizedString(
                        "quota.percent.remaining",
                        comment: "Accessible remaining quota"
                    ),
                    remainingPercent
                )
            )
        }
        details.append(speedMode.title)
        details.append(connectionState.title)
        if let resetDate {
            details.append(resetDate.formatted(date: .abbreviated, time: .shortened))
        }
        return details.joined(separator: ", ")
    }

}

private struct TurboChevronPattern: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = 2
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 1))
                path.addLine(to: CGPoint(x: x + 5, y: size.height / 2))
                path.addLine(to: CGPoint(x: x, y: size.height - 1))
                x += 10
            }
            context.stroke(
                path,
                with: .color(.white.opacity(0.2)),
                lineWidth: 1.5
            )
        }
        .allowsHitTesting(false)
    }
}

private struct TooltipPointer: Shape {
    enum Direction {
        case up
        case down
        case left
        case right
    }

    let direction: Direction

    func path(in rect: CGRect) -> Path {
        Path { path in
            switch direction {
            case .up:
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            case .down:
                path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            case .left:
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            case .right:
                path.move(to: CGPoint(x: rect.maxX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            }
            path.closeSubpath()
        }
    }
}
