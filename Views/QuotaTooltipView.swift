import SwiftUI

struct QuotaTooltipContent {
    struct PersonalResetHeader: Equatable {
        enum Tone: Equatable { case watch, scheduled, neutral }

        let text: String
        let accessibilityText: String
        let tone: Tone
    }

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
    let codexResetSourceState: CodexResetSourceState
    let resetCreditsAvailableCount: Int?
    let bundle: Bundle

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
        showsQuotaDynamics: Bool = false,
        codexResetSourceState: CodexResetSourceState = .disabled,
        resetCreditsAvailableCount: Int? = nil,
        bundle: Bundle = .main
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
        self.codexResetSourceState = codexResetSourceState
        self.resetCreditsAvailableCount = resetCreditsAvailableCount
        self.bundle = bundle
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
            locale: locale,
            resetWatchAccessibilityText: resetInformationAccessibilityText
        )
    }

    var personalResetHeader: PersonalResetHeader? {
        Self.personalResetHeader(
            resetCreditsAvailableCount: connectionState == .connected
                ? resetCreditsAvailableCount
                : nil,
            locale: locale,
            bundle: bundle
        )
    }

    static func personalResetHeader(
        resetCreditsAvailableCount: Int? = nil,
        locale: Locale,
        bundle: Bundle = .main
    ) -> PersonalResetHeader? {
        func localized(_ key: String) -> String {
            bundle.localizedString(forKey: key, value: nil, table: nil)
        }
        func formatted(_ key: String, _ argument: CVarArg) -> String {
            String(format: localized(key), locale: locale, argument)
        }

        if let resetCreditsAvailableCount, resetCreditsAvailableCount > 0 {
            let isSingleCredit = resetCreditsAvailableCount == 1
            let isCappedVisibleCount = resetCreditsAvailableCount >= 100
            return PersonalResetHeader(
                text: isSingleCredit
                    ? localized("reset_credit.header.one")
                    : isCappedVisibleCount
                        ? localized("reset_credit.header.capped")
                        : formatted("reset_credit.header.many", resetCreditsAvailableCount),
                accessibilityText: isSingleCredit
                    ? localized("reset_credit.accessibility.one")
                    : formatted(
                        "reset_credit.accessibility.many",
                        String(resetCreditsAvailableCount)
                    ),
                tone: .scheduled
            )
        }

        let key = resetCreditsAvailableCount == 0
            ? "reset_credit.header.none" : "reset_credit.header.unknown"
        return PersonalResetHeader(
            text: localized(key), accessibilityText: localized(key), tone: .neutral
        )
    }

    struct ResetAnnouncement: Equatable {
        let title: String
        let detail: String
    }

    var resetAnnouncementCount: Int { codexResetSourceState.itemCount(at: now) }

    static func resetFooterHeight(itemCount: Int) -> CGFloat {
        itemCount == 0 ? 0 : itemCount > 1 ? 102 : 68
    }

    var resetFooterHeight: CGFloat { Self.resetFooterHeight(itemCount: resetAnnouncementCount) }

    var resetSourceTitle: String { localized("reset_info.source") }

    var resetAnnouncements: [ResetAnnouncement] {
        switch codexResetSourceState {
        case .disabled: return []
        case .loading:
            return [.init(title: localized("reset_info.loading"), detail: "")]
        case .unavailable:
            return [.init(title: localized("reset_info.error"), detail: localized("reset_info.error.detail"))]
        case let .available(_, checkedAt):
            let signals = codexResetSourceState.signals(at: now)
            guard !signals.isEmpty else {
                return [.init(
                    title: localized("reset_info.empty"),
                    detail: String(format: localized("reset_info.checked"), locale: locale, eventDate(checkedAt))
                )]
            }
            return signals.map { signal in
                switch signal {
                case let .watch(chance, _):
                    return .init(
                        title: chance.map {
                            String(format: localized("reset_info.watch.chance"), locale: locale, $0)
                        } ?? localized("reset_info.watch"),
                        detail: localized("reset_info.forecast")
                    )
                case let .scheduled(type, date, _):
                    if let date, date <= now {
                        return .init(title: localized("reset_info.awaiting"), detail: eventDate(date))
                    }
                    return .init(
                        title: localized(type == .banked ? "reset_info.banked.announced" : "reset_info.regular.announced"),
                        detail: date.map(eventDate) ?? localized("reset_info.time.unknown")
                    )
                case let .completed(type, date, _):
                    return .init(
                        title: localized(type == .banked ? "reset_info.banked.completed" : "reset_info.regular.completed"),
                        detail: eventDate(date)
                    )
                }
            }
        }
    }

    var resetInformationAccessibilityText: String {
        var sentences = [personalResetHeader?.accessibilityText].compactMap { $0 }
        if resetAnnouncementCount > 0 {
            sentences.append(localized("reset_info.accessibility.source"))
            sentences += resetAnnouncements.map { [$0.title, $0.detail].filter { !$0.isEmpty }.joined(separator: ", ") }
        }
        return sentences.joined(separator: ". ")
    }

    private func localized(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    private func eventDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("jm")
        let time = formatter.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) {
            return String(format: localized("reset_info.date.today"), locale: locale, time)
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(format: localized("reset_info.date.tomorrow"), locale: locale, time)
        }
        formatter.setLocalizedDateFormatFromTemplate("dMMMjm")
        return formatter.string(from: date)
    }
}

struct ResetAnnouncementsFooter: View {
    let content: QuotaTooltipContent
    var pixel = false

    var body: some View {
        if content.resetAnnouncementCount > 0 {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle().fill(.white.opacity(0.14)).frame(height: 1)
                Text(content.resetSourceTitle)
                    .font(.system(size: 9, weight: .semibold, design: pixel ? .monospaced : .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 4)
                    .padding(.bottom, 2)
                ForEach(Array(content.resetAnnouncements.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.title)
                            .font(.system(size: pixel ? 11 : 12, weight: .medium, design: pixel ? .monospaced : .rounded))
                            .foregroundStyle(content.codexResetSourceState.signals(at: content.now).isEmpty ? .white.opacity(0.86) : Color(red: 1, green: 0.68, blue: 0.35))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(item.detail)
                            .font(.system(size: 9.5, design: pixel ? .monospaced : .rounded))
                            .foregroundStyle(.white.opacity(0.58))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, pixel ? 15 : 14)
            .frame(height: content.resetFooterHeight)
            .accessibilityHidden(true)
        }
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
    private let now: () -> Date
    let codexResetSourceStateDidChange: @MainActor (
        CodexResetSourceState,
        CodexResetSourceState
    ) -> Void

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
        isTooltipPresented: Bool = false,
        now: @escaping () -> Date = Date.init,
        codexResetSourceStateDidChange: @escaping @MainActor (
            CodexResetSourceState,
            CodexResetSourceState
        ) -> Void = { _, _ in }
    ) {
        self.appState = appState
        self.placement = placement
        self.isTooltipPresented = isTooltipPresented
        self.now = now
        self.codexResetSourceStateDidChange = codexResetSourceStateDidChange
    }

    private var content: QuotaTooltipContent {
        QuotaTooltipContent(
            remainingPercent: appState.quota?.primary?.remainingPercent,
            speedMode: appState.speedMode,
            connectionState: appState.connectionState,
            resetDate: appState.quota?.primary?.resetDate,
            windowDurationMinutes: appState.quota?.primary?.windowDurationMins,
            now: now(),
            locale: locale,
            calendar: calendar,
            history: appState.quotaHistory,
            showsQuotaDynamics: appState.showsQuotaDynamics,
            codexResetSourceState: appState.codexResetSourceState,
            resetCreditsAvailableCount: appState.resetCreditsAvailableCount
        )
    }

    private var remainingPercent: Int? {
        content.remainingPercent
    }

    private var speedMode: SpeedMode {
        content.speedMode
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
            showsHistory: appState.showsQuotaDynamics,
            resetAnnouncementCount: content.resetAnnouncementCount
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
        .onChange(of: appState.codexResetSourceState) { previousState, state in
            codexResetSourceStateDidChange(previousState, state)
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
                showsHistory: appState.showsQuotaDynamics,
                resetAnnouncementCount: content.resetAnnouncementCount
            )

            tooltipContent
                .scaleEffect(appState.petSize.scale)
                .frame(width: scaledPanelSize.width, height: scaledPanelSize.height)
        }
    }

    private var smallTooltipContent: some View {
        VStack(spacing: 0) {
        HStack(spacing: 12) {
            smallCircularProgress

            VStack(alignment: .leading, spacing: appState.showsQuotaDynamics ? 5 : 7) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        content.personalResetHeader?.text
                            ?? NSLocalizedString("quota.available", comment: "Quota card title")
                    )
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(personalResetTitleColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

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
        ResetAnnouncementsFooter(content: content)
        }
        .frame(width: Self.smallCardSize.width)
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
            height: (appState.showsQuotaDynamics
                ? Self.historySmallPanelSize.height
                : Self.smallPanelSize.height) + content.resetFooterHeight,
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
            HStack(alignment: content.resetDate == nil ? .top : .center, spacing: 5) {
                Image(systemName: "timer")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(resetCountdownText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .lineLimit(content.resetDate == nil ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let compactResetText = content.compactResetText {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(compactResetText)
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
        VStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text(
                    content.personalResetHeader?.text
                        ?? NSLocalizedString("quota.available", comment: "Quota card title")
                )
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(personalResetTitleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

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
        .frame(width: Self.cardWidth, height: (appState.showsQuotaDynamics
            ? Self.historyPanelSize.height : Self.panelSize.height) - 24)
        ResetAnnouncementsFooter(content: content)
        }
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
            height: (appState.showsQuotaDynamics
                ? Self.historyPanelSize.height
                : Self.panelSize.height) + content.resetFooterHeight,
            alignment: panelAlignment
        )
    }

    static func panelSize(
        for petSize: PetSize,
        style: TooltipStyle = .smooth,
        showsHistory: Bool = false,
        resetAnnouncementCount: Int = 0
    ) -> CGSize {
        if style == .pixel {
            return PixelQuotaTooltipView.panelSize(for: petSize, showsHistory: showsHistory, resetAnnouncementCount: resetAnnouncementCount)
        }
        if petSize == .small {
            let base = showsHistory ? historySmallPanelSize : smallPanelSize
            return CGSize(width: base.width, height: base.height + QuotaTooltipContent.resetFooterHeight(itemCount: resetAnnouncementCount))
        }
        return panelSize(forScale: petSize.scale, showsHistory: showsHistory, resetAnnouncementCount: resetAnnouncementCount)
    }

    static func panelSize(
        forScale scale: CGFloat,
        style: TooltipStyle = .smooth,
        showsHistory: Bool = false,
        resetAnnouncementCount: Int = 0
    ) -> CGSize {
        if style == .pixel {
            if scale <= PetSize.small.scale {
                return PixelQuotaTooltipView.panelSize(
                    for: .small,
                    showsHistory: showsHistory,
                    resetAnnouncementCount: resetAnnouncementCount
                )
            }
            return PixelQuotaTooltipView.panelSize(
                for: scale < 0.9 ? .medium : .large,
                showsHistory: showsHistory,
                resetAnnouncementCount: resetAnnouncementCount
            )
        }
        if scale <= PetSize.small.scale {
            let base = showsHistory ? historySmallPanelSize : smallPanelSize
            return CGSize(width: base.width, height: base.height + QuotaTooltipContent.resetFooterHeight(itemCount: resetAnnouncementCount))
        }
        let base = showsHistory ? historyPanelSize : panelSize
        return CGSize(width: base.width * scale, height: (base.height + QuotaTooltipContent.resetFooterHeight(itemCount: resetAnnouncementCount)) * scale)
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

            if let compactResetText = content.compactResetText {
                Text(compactResetText)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.trailing)
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

    private var resetAccessibilityLabel: String {
        content.resetAccessibilityLabel
    }

    private var personalResetTitleColor: Color {
        switch content.personalResetHeader?.tone {
        case .watch: orange
        case .scheduled: gold
        case .neutral, nil: .white.opacity(0.72)
        }
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
        codexResetSignal: CodexResetSignal? = nil,
        codexResetSignals: [CodexResetSignal] = [],
        now: Date
    ) -> TimeInterval {
        let personalDelay: TimeInterval
        if let resetDate {
            let remaining = resetDate.timeIntervalSince(now)
            if remaining > 0, remaining < 3_600 {
                personalDelay = 1
            } else if remaining >= 3_600 {
                let unit: TimeInterval = remaining >= 86_400 ? 86_400 : 3_600
                let nextBoundary = remaining.truncatingRemainder(dividingBy: unit) + 0.05
                personalDelay = min(60, max(0.05, nextBoundary))
            } else {
                personalDelay = 60
            }
        } else {
            personalDelay = 60
        }

        let externalBoundary = (codexResetSignals + [codexResetSignal].compactMap { $0 }).compactMap { signal -> Date? in
        switch signal {
        case let .watch(_, expiresAt) where expiresAt > now:
            return expiresAt
        case let .scheduled(_, scheduledFor?, _) where scheduledFor > now:
            return scheduledFor
        case let .completed(_, announcedAt, _) where announcedAt.addingTimeInterval(86_400) > now:
            return announcedAt.addingTimeInterval(86_400)
        default:
            return nil
        }
        }.min()
        guard let externalBoundary else { return personalDelay }
        let externalDelay = externalBoundary.timeIntervalSince(now) + 0.05
        return min(personalDelay, max(0.05, externalDelay))
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
        locale: Locale = .autoupdatingCurrent,
        resetWatchAccessibilityText: String? = nil
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
        let personalSummary = details.joined(separator: ", ")
        guard let resetWatchAccessibilityText else { return personalSummary }
        return personalSummary + ". " + resetWatchAccessibilityText
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
