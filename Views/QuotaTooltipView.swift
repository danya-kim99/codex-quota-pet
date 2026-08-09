import SwiftUI

struct QuotaTooltipContent {
    let remainingPercent: Int?
    let speedMode: SpeedMode
    let connectionState: ConnectionState
    let resetDate: Date?
    let windowDurationMinutes: Int64?
    let now: Date
    let locale: Locale
    let calendar: Calendar
    let history: QuotaHistoryPresentation
    let showsQuotaDynamics: Bool

    init(
        remainingPercent: Int?,
        speedMode: SpeedMode,
        connectionState: ConnectionState,
        resetDate: Date?,
        windowDurationMinutes: Int64?,
        now: Date,
        locale: Locale,
        calendar: Calendar,
        history: QuotaHistoryPresentation = .empty(),
        showsQuotaDynamics: Bool = false
    ) {
        self.remainingPercent = remainingPercent
        self.speedMode = speedMode
        self.connectionState = connectionState
        self.resetDate = resetDate
        self.windowDurationMinutes = windowDurationMinutes
        self.now = now
        self.locale = locale
        self.calendar = calendar
        self.history = history
        self.showsQuotaDynamics = showsQuotaDynamics
    }

    var progressFraction: CGFloat {
        CGFloat(min(100, max(0, remainingPercent ?? 0))) / 100
    }

    var quotaLevel: QuotaTooltipView.QuotaLevel {
        QuotaTooltipView.quotaLevel(for: remainingPercent)
    }

    var dayIndicator: QuotaTooltipView.DayIndicator? {
        QuotaTooltipView.dayIndicator(
            resetDate: resetDate,
            now: now,
            windowDurationMinutes: windowDurationMinutes
        )
    }

    var resetCountdownText: String {
        guard let resetDate else {
            return NSLocalizedString("reset.unavailable", comment: "Missing reset time")
        }
        let duration = QuotaTooltipView.localizedResetDuration(
            until: resetDate,
            now: now,
            locale: locale,
            calendar: calendar
        )
        return String(
            format: NSLocalizedString(
                "reset.countdown.remaining",
                comment: "Time until reset"
            ),
            locale: locale,
            duration
        )
    }

    var compactResetText: String? {
        guard let resetDate else { return nil }
        let parts = QuotaTooltipView.resetDateParts(
            resetDate,
            relativeTo: now,
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

    var resetAccessibilityLabel: String {
        [resetCountdownText, compactResetText].compactMap { $0 }.joined(separator: ", ")
    }

    var isStale: Bool {
        remainingPercent != nil && connectionState != .connected
    }

    var accessibilitySummary: String {
        QuotaTooltipView.accessibilitySummary(
            remainingPercent: remainingPercent,
            speedMode: speedMode,
            connectionState: connectionState,
            resetDate: resetDate,
            history: history,
            showsQuotaDynamics: showsQuotaDynamics,
            locale: locale
        )
    }
}

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

    struct DayIndicator: Equatable {
        let activeSegments: Int
        let totalSegments: Int
    }

    static let cardWidth: CGFloat = 320
    static let panelSize = CGSize(width: cardWidth + 40, height: 178)
    static let historyPanelSize = CGSize(width: cardWidth + 40, height: 252)
    static let smallCardSize = CGSize(width: 248, height: 112)
    static let smallPanelSize = CGSize(width: 272, height: 132)
    static let historySmallCardSize = CGSize(width: 248, height: 138)
    static let historySmallPanelSize = CGSize(width: 272, height: 158)
    private static let smallRingSize: CGFloat = 70
    private static let smallRingLineWidth: CGFloat = 8
    // Gold sprite states render at roughly 214–216 pt inside BlackHoleView.
    static let petAnchorHalfSize = CGSize(width: 108, height: 64)

    let appState: AppState
    let placement: Placement
    let isTooltipPresented: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1
    @State private var badgeHighlightIntensity: CGFloat = 0
    @State private var badgeHighlightTask: Task<Void, Never>?

    private let gold = Color(red: 1, green: 0.76, blue: 0.31)
    private let orange = Color(red: 1, green: 0.34, blue: 0.16)
    private let purple = Color(red: 0.68, green: 0.27, blue: 0.94)
    private let cardColor = Color(red: 0.065, green: 0.07, blue: 0.08)

    init(
        appState: AppState,
        placement: Placement = .below,
        isTooltipPresented: Bool = false
    ) {
        self.appState = appState
        self.placement = placement
        self.isTooltipPresented = isTooltipPresented
    }

    private var content: QuotaTooltipContent {
        QuotaTooltipContent(
            remainingPercent: appState.quota?.primary?.remainingPercent,
            speedMode: appState.speedMode,
            connectionState: appState.connectionState,
            resetDate: appState.quota?.primary?.resetDate,
            windowDurationMinutes: appState.quota?.primary?.windowDurationMins,
            now: Date(),
            locale: locale,
            calendar: calendar,
            history: appState.quotaHistory,
            showsQuotaDynamics: appState.showsQuotaDynamics
        )
    }

    private var remainingPercent: Int? {
        content.remainingPercent
    }

    private var speedMode: SpeedMode {
        content.speedMode
    }

    private var resetDate: Date? {
        content.resetDate
    }

    private var dayIndicator: DayIndicator? {
        content.dayIndicator
    }

    private var quotaColor: Color {
        switch content.quotaLevel {
        case .normal: gold
        case .warning: orange
        case .critical: purple
        }
    }

    @ViewBuilder
    var body: some View {
        let accessibilityScale = min(1.5, max(1, textScale))
        let baseSize = Self.panelSize(
            for: appState.petSize,
            style: appState.tooltipStyle,
            showsHistory: appState.showsQuotaDynamics
        )

        Group {
            if appState.tooltipStyle == .pixel {
                PixelQuotaTooltipView(
                    content: content,
                    placement: placement,
                    petSize: appState.petSize,
                    badgeHighlightIntensity: badgeHighlightIntensity
                )
            } else {
                smoothTooltip
            }
        }
        .scaleEffect(accessibilityScale)
        .frame(
            width: baseSize.width * accessibilityScale,
            height: baseSize.height * accessibilityScale
        )
        .onChange(of: isTooltipPresented, initial: true) { wasPresented, isPresented in
            if !isPresented {
                cancelBadgeHighlight()
            } else if !wasPresented {
                startBadgeHighlightIfEligible()
            }
        }
        .onChange(of: speedMode) { previousMode, mode in
            if mode == .turbo, previousMode == .standard {
                startBadgeHighlightIfEligible()
            } else if mode == .standard {
                cancelBadgeHighlight()
            }
        }
        .onChange(of: isBadgeHighlightEligible) { _, isEligible in
            if !isEligible {
                cancelBadgeHighlight()
            }
        }
        .onDisappear {
            cancelBadgeHighlight()
        }
    }

    @ViewBuilder
    private var smoothTooltip: some View {
        if appState.petSize == .small {
            smallTooltipContent
        } else {
            let scaledPanelSize = Self.panelSize(
                for: appState.petSize,
                style: .smooth,
                showsHistory: appState.showsQuotaDynamics
            )

            tooltipContent
                .scaleEffect(appState.petSize.scale)
                .frame(width: scaledPanelSize.width, height: scaledPanelSize.height)
        }
    }

    private var smallTooltipContent: some View {
        HStack(spacing: 12) {
            smallCircularProgress

            VStack(alignment: .leading, spacing: appState.showsQuotaDynamics ? 5 : 7) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(NSLocalizedString("quota.available", comment: "Quota card title"))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .lineLimit(1)

                    smoothModeBadge(compact: true)
                }

                Divider()
                    .overlay(.white.opacity(0.14))

                smallResetRows

                if appState.showsQuotaDynamics {
                    Divider()
                        .overlay(.white.opacity(0.14))
                    QuotaHistoryCompactText(
                        presentation: content.history,
                        style: .smooth,
                        color: quotaColor,
                        currentUnavailable: content.remainingPercent == nil
                    )
                }
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(
            width: Self.smallCardSize.width,
            height: appState.showsQuotaDynamics
                ? Self.historySmallCardSize.height
                : Self.smallCardSize.height
        )
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
            height: appState.showsQuotaDynamics
                ? Self.historySmallPanelSize.height
                : Self.smallPanelSize.height,
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
                Text(resetCountdownText)
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

                smoothModeBadge(compact: false)

                Spacer(minLength: 8)

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

            if appState.showsQuotaDynamics {
                Divider()
                    .overlay(.white.opacity(0.14))
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                QuotaHistorySection(
                    presentation: content.history,
                    style: .smooth,
                    quotaColor: quotaColor,
                    currentUnavailable: content.remainingPercent == nil
                )
            }
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
            height: appState.showsQuotaDynamics
                ? Self.historyPanelSize.height
                : Self.panelSize.height,
            alignment: panelAlignment
        )
    }

    static func panelSize(
        for petSize: PetSize,
        style: TooltipStyle = .smooth,
        showsHistory: Bool = false
    ) -> CGSize {
        if style == .pixel {
            return PixelQuotaTooltipView.panelSize(for: petSize, showsHistory: showsHistory)
        }
        if petSize == .small {
            return showsHistory ? historySmallPanelSize : smallPanelSize
        }
        return panelSize(forScale: petSize.scale, showsHistory: showsHistory)
    }

    static func panelSize(
        forScale scale: CGFloat,
        style: TooltipStyle = .smooth,
        showsHistory: Bool = false
    ) -> CGSize {
        if style == .pixel {
            if scale <= PetSize.small.scale {
                return PixelQuotaTooltipView.panelSize(
                    for: .small,
                    showsHistory: showsHistory
                )
            }
            return PixelQuotaTooltipView.panelSize(
                for: scale < 0.9 ? .medium : .large,
                showsHistory: showsHistory
            )
        }
        if scale <= PetSize.small.scale {
            return showsHistory ? historySmallPanelSize : smallPanelSize
        }
        let base = showsHistory ? historyPanelSize : panelSize
        return CGSize(width: base.width * scale, height: base.height * scale)
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
            standardProgressBar(in: geometry.size)
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

    private var progressFraction: CGFloat {
        content.progressFraction
    }

    private var resetRow: some View {
        HStack(spacing: 8) {
            if let dayIndicator {
                daySegments(dayIndicator)
                    .frame(width: 64, height: 14)
            }

            Text(resetCountdownText)
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

    private var resetCountdownText: String {
        content.resetCountdownText
    }

    private func compactResetText(_ date: Date) -> String {
        content.compactResetText ?? ""
    }

    private var resetAccessibilityLabel: String {
        content.resetAccessibilityLabel
    }

    nonisolated static func isTurboBadgeHighlightEligible(
        isTooltipPresented: Bool,
        speedMode: SpeedMode,
        connectionState: ConnectionState,
        remainingPercent: Int?,
        reduceMotion: Bool
    ) -> Bool {
        isTooltipPresented
            && speedMode == .turbo
            && connectionState == .connected
            && (remainingPercent ?? 0) > 0
            && !reduceMotion
    }

    static func dayIndicator(
        resetDate: Date?,
        now: Date,
        windowDurationMinutes: Int64?
    ) -> DayIndicator? {
        guard let resetDate, let windowDurationMinutes, windowDurationMinutes > 0 else {
            return nil
        }

        let remainingDays = max(0, Int(resetDate.timeIntervalSince(now) / 86_400))
        let totalSegments = max(1, Int(ceil(Double(windowDurationMinutes) / 1_440)))

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

    static func localizedResetDuration(
        until resetDate: Date,
        now: Date,
        locale: Locale,
        calendar: Calendar
    ) -> String {
        let remainingSeconds = max(0, Int(resetDate.timeIntervalSince(now)))
        let formatter = DateComponentsFormatter()
        var localizedCalendar = calendar
        localizedCalendar.locale = locale
        formatter.calendar = localizedCalendar
        formatter.maximumUnitCount = 2

        let components: DateComponents
        if remainingSeconds >= 86_400 {
            formatter.allowedUnits = [.day]
            formatter.unitsStyle = .full
            formatter.maximumUnitCount = 1
            components = DateComponents(day: remainingSeconds / 86_400)
        } else if remainingSeconds >= 3_600 {
            formatter.allowedUnits = [.hour]
            formatter.unitsStyle = .abbreviated
            formatter.maximumUnitCount = 1
            components = DateComponents(hour: remainingSeconds / 3_600)
        } else {
            formatter.allowedUnits = [.minute, .second]
            formatter.unitsStyle = .abbreviated
            formatter.zeroFormattingBehavior = [.pad]
            components = DateComponents(
                minute: remainingSeconds / 60,
                second: remainingSeconds % 60
            )
        }

        return formatter.string(from: components) ?? "0"
    }

    static func resetCountdownUpdateDelay(
        resetDate: Date?,
        now: Date
    ) -> TimeInterval {
        guard let resetDate else { return 60 }
        let remaining = resetDate.timeIntervalSince(now)
        guard remaining > 0 else { return 60 }
        guard remaining >= 3_600 else { return 1 }

        let unit: TimeInterval = remaining >= 86_400 ? 86_400 : 3_600
        let nextBoundary = remaining.truncatingRemainder(dividingBy: unit) + 0.05
        return min(60, max(0.05, nextBoundary))
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
        resetDate: Date?,
        history: QuotaHistoryPresentation = .empty(),
        showsQuotaDynamics: Bool = false,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        var details: [String] = []
        if let remainingPercent {
            let key = connectionState == .connected
                ? "quota.percent.remaining"
                : "accessibility.quota.last_known"
            details.append(
                String(
                    format: NSLocalizedString(
                        key,
                        comment: "Accessible remaining quota"
                    ),
                    remainingPercent
                )
            )
        } else {
            details.append(
                NSLocalizedString(
                    "accessibility.quota.unavailable",
                    comment: "Accessible unavailable quota"
                )
            )
        }
        details.append(speedMode.title)
        details.append(connectionState.title)
        if let resetDate {
            details.append(resetDate.formatted(date: .abbreviated, time: .shortened))
        }
        if showsQuotaDynamics {
            details.append(history.accessibilitySummary(
                locale: locale,
                liveCurrentUnavailable: remainingPercent == nil
            ))
        }
        return details.joined(separator: ", ")
    }

    private var isBadgeHighlightEligible: Bool {
        Self.isTurboBadgeHighlightEligible(
            isTooltipPresented: isTooltipPresented,
            speedMode: speedMode,
            connectionState: content.connectionState,
            remainingPercent: remainingPercent,
            reduceMotion: reduceMotion
        )
    }

    private func startBadgeHighlightIfEligible() {
        cancelBadgeHighlight()
        guard isBadgeHighlightEligible else { return }

        badgeHighlightTask = Task { @MainActor in
            for target: CGFloat in [1, 0, 1, 0] {
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.6)) {
                    badgeHighlightIntensity = target
                }
                do {
                    try await Task.sleep(nanoseconds: 600_000_000)
                } catch {
                    return
                }
            }
        }
    }

    private func cancelBadgeHighlight() {
        badgeHighlightTask?.cancel()
        badgeHighlightTask = nil
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            badgeHighlightIntensity = 0
        }
    }

    private func smoothModeBadge(compact: Bool) -> some View {
        ZStack {
            smoothModeBadgeContent(for: .standard)
                .hidden()
                .accessibilityHidden(true)
            smoothModeBadgeContent(for: .turbo)
                .hidden()
                .accessibilityHidden(true)
            smoothModeBadgeContent(for: speedMode)
        }
        .font(
            .system(
                size: compact ? 9 : 10,
                weight: .semibold,
                design: .rounded
            )
        )
        .foregroundStyle(speedMode == .turbo ? gold : .white.opacity(0.72))
        .padding(.horizontal, compact ? 6 : 7)
        .frame(height: compact ? 18 : 20)
        .background(.white.opacity(speedMode == .turbo ? 0.09 : 0.06), in: Capsule())
        .overlay {
            Capsule()
                .stroke(
                    speedMode == .turbo ? gold.opacity(0.72) : .white.opacity(0.18),
                    lineWidth: 1
                )
        }
        .shadow(
            color: speedMode == .turbo
                ? gold.opacity(0.5 * Double(badgeHighlightIntensity))
                : .clear,
            radius: 4 + 4 * badgeHighlightIntensity
        )
        .accessibilityHidden(true)
    }

    private func smoothModeBadgeContent(for mode: SpeedMode) -> some View {
        HStack(spacing: 4) {
            if mode == .turbo {
                Image(systemName: "bolt.fill")
                    .accessibilityHidden(true)
            }
            Text(mode.title)
                .lineLimit(1)
        }
        .fixedSize()
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
