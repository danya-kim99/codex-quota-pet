import AppKit
import ImageIO
import ServiceManagement
import XCTest
@testable import Black_Hole_Codex_Quota_Indicator

final class RateLimitDecodingTests: XCTestCase {
    func testBundledIconsAreConfigured() throws {
        let menuBarIcon = try XCTUnwrap(NSImage(named: "MenuBarIcon"))
        let data = try XCTUnwrap(menuBarIcon.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))

        XCTAssertEqual(menuBarIcon.size, NSSize(width: 20, height: 20))
        XCTAssertTrue(menuBarIcon.isTemplate)
        var hasTransparentPixel = false
        var hasOpaquePixel = false
        var hasAntialiasedPixel = false
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let alpha = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.alphaComponent)
                hasTransparentPixel = hasTransparentPixel || alpha == 0
                hasOpaquePixel = hasOpaquePixel || alpha == 1
                hasAntialiasedPixel = hasAntialiasedPixel || (alpha > 0 && alpha < 1)
            }
        }
        XCTAssertTrue(hasTransparentPixel)
        XCTAssertTrue(hasOpaquePixel)
        XCTAssertTrue(hasAntialiasedPixel)
        XCTAssertEqual(
            Bundle(for: AppDelegate.self).object(forInfoDictionaryKey: "CFBundleIconName") as? String,
            "AppIcon"
        )
    }

    func testDecodesMainCodexQuota() throws {
        let json = #"""
        {
          "id": 1,
          "result": {
            "rateLimits": {
              "limitId": "legacy",
              "primary": { "usedPercent": 50 }
            },
            "rateLimitsByLimitId": {
              "codex": {
                "limitId": "codex",
                "planType": "pro",
                "primary": {
                  "usedPercent": 2,
                  "windowDurationMins": 10080,
                  "resetsAt": 1786175912
                }
              }
            }
          }
        }
        """#

        let response = try JSONDecoder().decode(
            RPCResponse<RateLimitsResult>.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(response.result.codex.limitId, "codex")
        XCTAssertEqual(response.result.codex.primary?.remainingPercent, 98)
        XCTAssertEqual(response.result.codex.primary?.windowDurationMins, 10_080)
    }

    func testDecodesTurboFromEffectiveCodexConfig() throws {
        let turboJSON = #"{"id":2,"result":{"config":{"service_tier":"priority"}}}"#
        let standardJSON = #"{"id":3,"result":{"config":{"service_tier":null}}}"#

        let turbo = try JSONDecoder().decode(
            RPCResponse<ConfigReadResult>.self,
            from: Data(turboJSON.utf8)
        )
        let standard = try JSONDecoder().decode(
            RPCResponse<ConfigReadResult>.self,
            from: Data(standardJSON.utf8)
        )

        XCTAssertEqual(turbo.result.speedMode, .turbo)
        XCTAssertEqual(standard.result.speedMode, .standard)
    }

    @MainActor
    func testTooltipFollowsPetAndChoosesVisibleScreenSide() {
        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let cases: [(CGRect, QuotaTooltipView.Placement)] = [
            (CGRect(x: 0, y: 340, width: 400, height: 220), .right),
            (CGRect(x: 520, y: 0, width: 400, height: 220), .above),
            (CGRect(x: 1_040, y: 340, width: 400, height: 220), .left),
            (CGRect(x: 520, y: 680, width: 400, height: 220), .below)
        ]

        for (petFrame, expectedPlacement) in cases {
            let layout = PetPanelController.tooltipLayout(
                petFrame: petFrame,
                visibleFrame: screen
            )
            let tooltipFrame = CGRect(origin: layout.origin, size: layout.size)

            XCTAssertEqual(layout.placement, expectedPlacement)
            XCTAssertTrue(screen.contains(tooltipFrame))
        }

        let first = PetPanelController.tooltipLayout(
            petFrame: cases[0].0,
            visibleFrame: screen
        )
        let moved = PetPanelController.tooltipLayout(
            petFrame: cases[2].0,
            visibleFrame: screen
        )
        XCTAssertNotEqual(first.origin, moved.origin)
        XCTAssertEqual(BlackHoleView.size, cases[0].0.size)
    }

    @MainActor
    func testTooltipUsesDedicatedSmallLayout() {
        XCTAssertEqual(
            QuotaTooltipView.panelSize(for: .large),
            CGSize(width: 360, height: 178)
        )
        XCTAssertEqual(
            QuotaTooltipView.panelSize(for: .medium),
            CGSize(width: 288, height: 142.4)
        )
        XCTAssertEqual(
            QuotaTooltipView.panelSize(for: .small),
            CGSize(width: 272, height: 132)
        )
        XCTAssertEqual(QuotaTooltipView.smallCardSize, CGSize(width: 248, height: 112))
        XCTAssertLessThan(
            QuotaTooltipView.panelSize(for: .small).width,
            QuotaTooltipView.panelSize(for: .medium).width
        )
        XCTAssertLessThan(
            QuotaTooltipView.panelSize(for: .small).height,
            QuotaTooltipView.panelSize(for: .medium).height
        )

        XCTAssertEqual(
            QuotaTooltipView.panelSize(for: .large, style: .pixel),
            CGSize(width: 420, height: 210)
        )
        XCTAssertEqual(
            QuotaTooltipView.panelSize(for: .medium, style: .pixel),
            CGSize(width: 336, height: 168)
        )
        XCTAssertEqual(
            QuotaTooltipView.panelSize(for: .small, style: .pixel),
            CGSize(width: 304, height: 148)
        )
        XCTAssertEqual(PixelQuotaTooltipView.largeCardSize, CGSize(width: 390, height: 180))
        XCTAssertEqual(PixelQuotaTooltipView.mediumCardSize, CGSize(width: 312, height: 144))
        XCTAssertEqual(PixelQuotaTooltipView.smallCardSize, CGSize(width: 280, height: 128))

        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        for petSize in PetSize.allCases {
            let sceneSize = petSize.sceneSize
            let petFrame = CGRect(
                x: screen.midX - sceneSize.width / 2,
                y: screen.midY - sceneSize.height / 2,
                width: sceneSize.width,
                height: sceneSize.height
            )
            let layout = PetPanelController.tooltipLayout(
                petFrame: petFrame,
                visibleFrame: screen
            )

            XCTAssertEqual(layout.size, QuotaTooltipView.panelSize(for: petSize))
            XCTAssertTrue(screen.contains(CGRect(origin: layout.origin, size: layout.size)))
        }
    }

    func testPixelTooltipHardShadowsStayWithinEveryPanel() {
        let cardAndPanelSizes = [
            (PixelQuotaTooltipView.largeCardSize, PixelQuotaTooltipView.largePanelSize),
            (PixelQuotaTooltipView.mediumCardSize, PixelQuotaTooltipView.mediumPanelSize),
            (PixelQuotaTooltipView.smallCardSize, PixelQuotaTooltipView.smallPanelSize)
        ]
        let requiredHorizontalInset = max(
            PixelQuotaTooltipView.purpleShadowOffset.width,
            PixelQuotaTooltipView.blackShadowOffset.width
        )
        let requiredVerticalInset = max(
            -PixelQuotaTooltipView.purpleShadowOffset.height,
            -PixelQuotaTooltipView.blackShadowOffset.height
        )

        for (cardSize, panelSize) in cardAndPanelSizes {
            XCTAssertGreaterThanOrEqual(
                (panelSize.width - cardSize.width) / 2,
                requiredHorizontalInset
            )
            XCTAssertGreaterThanOrEqual(
                (panelSize.height - cardSize.height) / 2,
                requiredVerticalInset
            )
        }
    }

    func testPixelContextMenuHardShadowsStayWithinPanel() {
        let contentWidth = PixelContextMenuView.mainWidth
            + PixelContextMenuView.menuGap
            + PixelContextMenuView.submenuWidth
        let requiredTrailingInset = max(
            PixelContextMenuView.purpleShadowOffset.width,
            PixelContextMenuView.blackShadowOffset.width
        )
        let requiredTopInset = max(
            -PixelContextMenuView.purpleShadowOffset.height,
            -PixelContextMenuView.blackShadowOffset.height
        )

        XCTAssertGreaterThanOrEqual(
            PixelContextMenuView.panelSize.width - contentWidth,
            requiredTrailingInset
        )
        XCTAssertGreaterThanOrEqual(
            PixelContextMenuView.shadowTrailingInset,
            requiredTrailingInset
        )
        XCTAssertGreaterThanOrEqual(
            PixelContextMenuView.shadowTopInset,
            requiredTopInset
        )
        XCTAssertEqual(PixelContextMenuView.mainWidth, 232)
        XCTAssertEqual(PixelContextMenuView.compactSubmenuWidth, 146)
        XCTAssertEqual(PixelContextMenuView.submenuWidth, 214)
        XCTAssertEqual(PixelContextMenuView.matrixCategoryWidth, 76)
        XCTAssertEqual(PixelContextMenuView.matrixCellSize, 31)
        XCTAssertEqual(PixelContextMenuView.matrixCategoryCount, 3)
        XCTAssertEqual(PixelContextMenuView.matrixWeights, [0, 1, 2, 3])
        XCTAssertEqual(PixelContextMenuView.panelSize, CGSize(width: 462, height: 474))
    }

    func testPetSizeOptionsUseApprovedDimensions() {
        XCTAssertEqual(PetSize.allCases, [.small, .medium, .large])
        XCTAssertEqual(PetSize.small.label, "S")
        XCTAssertEqual(PetSize.medium.label, "M")
        XCTAssertEqual(PetSize.large.label, "L")
        XCTAssertEqual(PetSize.small.sceneSize, CGSize(width: 240, height: 132))
        XCTAssertEqual(PetSize.medium.sceneSize, CGSize(width: 320, height: 176))
        XCTAssertEqual(PetSize.large.sceneSize, CGSize(width: 400, height: 220))
    }

    @MainActor
    func testPetResizePreservesCenterAndClampsToVisibleFrame() {
        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let centered = PetPanelController.resizedPetFrame(
            currentFrame: CGRect(x: 500, y: 300, width: 400, height: 220),
            to: PetSize.medium.sceneSize,
            visibleFrame: screen
        )
        XCTAssertEqual(centered.size, PetSize.medium.sceneSize)
        XCTAssertEqual(centered.midX, 700)
        XCTAssertEqual(centered.midY, 410)

        let clamped = PetPanelController.resizedPetFrame(
            currentFrame: CGRect(x: 1_200, y: 780, width: 240, height: 120),
            to: PetSize.large.sceneSize,
            visibleFrame: screen
        )
        XCTAssertTrue(screen.contains(clamped))
        XCTAssertEqual(clamped.maxX, screen.maxX)
        XCTAssertEqual(clamped.maxY, screen.maxY)
    }

    @MainActor
    func testTooltipRestoresAfterDragOnlyWhileCursorRemainsOverPet() {
        let petFrame = CGRect(x: 500, y: 300, width: 400, height: 220)

        XCTAssertTrue(
            PetPanelController.shouldRestoreTooltipAfterDrag(
                wasVisible: true,
                cursorLocation: CGPoint(x: petFrame.midX, y: petFrame.midY),
                petFrame: petFrame
            )
        )
        XCTAssertFalse(
            PetPanelController.shouldRestoreTooltipAfterDrag(
                wasVisible: true,
                cursorLocation: CGPoint(x: petFrame.maxX + 1, y: petFrame.midY),
                petFrame: petFrame
            )
        )
        XCTAssertFalse(
            PetPanelController.shouldRestoreTooltipAfterDrag(
                wasVisible: false,
                cursorLocation: CGPoint(x: petFrame.midX, y: petFrame.midY),
                petFrame: petFrame
            )
        )
    }

    func testContextMenuClickUsesVisiblePetAndMovementThreshold() {
        for size in PetSize.allCases.map(\.sceneSize) {
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            XCTAssertTrue(
                ContextMenuInteraction.acceptsClick(
                    mouseDown: center,
                    mouseUp: CGPoint(x: center.x + 6, y: center.y),
                    sceneSize: size
                )
            )
            XCTAssertFalse(
                ContextMenuInteraction.acceptsClick(
                    mouseDown: center,
                    mouseUp: CGPoint(x: center.x + 7, y: center.y),
                    sceneSize: size
                )
            )
            XCTAssertFalse(
                ContextMenuInteraction.acceptsClick(
                    mouseDown: CGPoint(x: 1, y: 1),
                    mouseUp: CGPoint(x: 1, y: 1),
                    sceneSize: size
                )
            )
        }
    }

    @MainActor
    func testContextMenuChoosesOnScreenQuadrant() {
        let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let cases: [(CGPoint, ContextMenuPlacement)] = [
            (CGPoint(x: 20, y: 20), .aboveRight),
            (CGPoint(x: 1_420, y: 20), .aboveLeft),
            (CGPoint(x: 20, y: 880), .belowRight),
            (CGPoint(x: 1_420, y: 880), .belowLeft)
        ]

        for (anchor, expectedPlacement) in cases {
            let layout = PetPanelController.contextMenuLayout(
                anchor: anchor,
                visibleFrame: screen
            )
            XCTAssertEqual(layout.placement, expectedPlacement)
            XCTAssertTrue(screen.contains(layout.frame))
            XCTAssertEqual(layout.frame.size, PixelContextMenuView.panelSize)
        }
    }

    @MainActor
    func testContextMenuClampsApprovedMatrixGeometryOnNegativeDisplay() {
        let screen = CGRect(x: -1_600, y: -474, width: 462, height: 474)
        let cases: [(CGPoint, ContextMenuPlacement)] = [
            (CGPoint(x: screen.minX + 1, y: screen.minY + 1), .aboveRight),
            (CGPoint(x: screen.maxX - 1, y: screen.minY + 1), .aboveLeft),
            (CGPoint(x: screen.minX + 1, y: screen.maxY - 1), .belowRight),
            (CGPoint(x: screen.maxX - 1, y: screen.maxY - 1), .belowLeft)
        ]

        for (anchor, expectedPlacement) in cases {
            let layout = PetPanelController.contextMenuLayout(
                anchor: anchor,
                visibleFrame: screen
            )
            XCTAssertEqual(layout.placement, expectedPlacement)
            XCTAssertEqual(layout.frame, screen)
        }
    }

    @MainActor
    func testContextMenuSpaghettificationReversesAndReducesMotion() {
        let start = ContextMenuVisualState.make(
            phase: .opening,
            elapsedTime: 0,
            reduceMotion: false
        )
        let opening = ContextMenuVisualState.make(
            phase: .opening,
            elapsedTime: ContextMenuVisualState.appearanceDuration * 0.6,
            reduceMotion: false
        )
        let open = ContextMenuVisualState.make(
            phase: .open,
            elapsedTime: 0,
            reduceMotion: false
        )
        let closing = ContextMenuVisualState.make(
            phase: .closing,
            elapsedTime: ContextMenuVisualState.dismissalDuration * 0.6,
            reduceMotion: false
        )
        let reduced = ContextMenuVisualState.make(
            phase: .opening,
            elapsedTime: ContextMenuVisualState.reducedMotionDuration / 2,
            reduceMotion: true
        )

        XCTAssertLessThan(start.longitudinalScale, 0.1)
        XCTAssertLessThan(start.transverseScale, start.longitudinalScale)
        XCTAssertGreaterThan(opening.longitudinalScale, opening.transverseScale)
        XCTAssertEqual(open.longitudinalScale, 1)
        XCTAssertEqual(open.transverseScale, 1)
        XCTAssertLessThan(closing.visibleProgress, 1)
        XCTAssertEqual(reduced.longitudinalScale, 1)
        XCTAssertEqual(reduced.transverseScale, 1)
        XCTAssertGreaterThan(reduced.opacity, 0)
        XCTAssertLessThan(reduced.opacity, 1)
    }

    func testTooltipLocalizationsAreBundled() throws {
        let appBundle = Bundle(for: AppDelegate.self)
        let englishPath = try XCTUnwrap(
            appBundle.path(forResource: "en", ofType: "lproj")
        )
        let russianPath = try XCTUnwrap(
            appBundle.path(forResource: "ru", ofType: "lproj")
        )
        let english = try XCTUnwrap(Bundle(path: englishPath))
        let russian = try XCTUnwrap(Bundle(path: russianPath))

        XCTAssertEqual(
            english.localizedString(forKey: "quota.available", value: nil, table: nil),
            "Available"
        )
        XCTAssertEqual(
            russian.localizedString(forKey: "quota.available", value: nil, table: nil),
            "Доступно"
        )
        XCTAssertEqual(
            russian.localizedString(forKey: "reset.countdown.remaining", value: nil, table: nil),
            "%@ до сброса"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "reset.compact.absolute", value: nil, table: nil),
            "%1$@, %2$@"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "accessibility.absorb_object", value: nil, table: nil),
            "Absorb Object"
        )
        XCTAssertEqual(
            russian.localizedString(forKey: "accessibility.absorb_object", value: nil, table: nil),
            "Втянуть объект"
        )
        XCTAssertEqual(
            english.localizedString(
                forKey: "accessibility.open_context_menu",
                value: nil,
                table: nil
            ),
            "Open Context Menu"
        )
        XCTAssertEqual(
            russian.localizedString(
                forKey: "accessibility.open_context_menu",
                value: nil,
                table: nil
            ),
            "Открыть контекстное меню"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "mode.standard", value: nil, table: nil),
            "Standard"
        )
        XCTAssertEqual(
            english.localizedString(forKey: "mode.turbo", value: nil, table: nil),
            "Turbo"
        )
        XCTAssertEqual(
            russian.localizedString(forKey: "mode.standard", value: nil, table: nil),
            "Стандарт"
        )
        XCTAssertEqual(
            russian.localizedString(forKey: "mode.turbo", value: nil, table: nil),
            "Турбо"
        )

        let menuTranslations = [
            "menu.quota.short": ("Quota", "Квота"),
            "menu.retry": ("Retry Now", "Повторить сейчас"),
            "menu.hide_pet": ("Hide Pet", "Скрыть питомца"),
            "menu.show_pet": ("Show Pet", "Показать питомца"),
            "menu.size": ("Size", "Размер"),
            "menu.object_mix.format": ("Object Mix (%@)", "Состав объектов (%@)"),
            "menu.object_mix.category.format": ("%1$@ — %2$d", "%1$@ — %2$d"),
            "menu.object_mix.hint.frequency": (
                "Higher weight, more often",
                "Чем выше вес, тем чаще"
            ),
            "menu.object_mix.hint.zero": (
                "0 excludes the category",
                "0 исключает категорию"
            ),
            "menu.object_mix.off": ("Off", "Не показывать"),
            "menu.object_mix.matrix.hint.zero": ("0 — Off", "0 — Не показывать"),
            "menu.object_mix.matrix.hint.frequency": (
                "Higher — more often",
                "Больше — чаще"
            ),
            "menu.object_mix.matrix.accessibility.label": (
                "Object Mix",
                "Состав объектов"
            ),
            "menu.object_mix.matrix.zero.accessibility": (
                "0, Off",
                "0, Не показывать"
            ),
            "menu.object_mix.matrix.cell.accessibility.format": (
                "%1$@, weight %2$@",
                "%1$@, вес %2$@"
            ),
            "menu.object_mix.matrix.last_active.help": (
                "Unavailable because at least one category must remain active.",
                "Недоступно: хотя бы одна категория должна оставаться активной."
            ),
            "absorption.category.space": ("Space", "Космос"),
            "absorption.category.animals": ("Animals", "Зверюшки"),
            "absorption.category.characters": ("Characters", "Персонажи"),
            "menu.tooltip_style": ("Tooltip Style", "Стиль подсказки"),
            "tooltip_style.smooth": ("Smooth", "Обычный"),
            "tooltip_style.pixel": ("Pixel", "Стилизованный"),
            "menu.hide_full_screen": ("Hide in Full Screen", "Скрывать в полноэкранном режиме"),
            "menu.launch_at_login": ("Launch at Login", "Запускать при входе"),
            "menu.approval_required": ("Approval Required", "Требуется разрешение"),
            "menu.open_login_items": ("Open Login Items", "Открыть объекты входа"),
            "context_menu.quit": ("Quit", "Выход")
        ]
        for (key, translation) in menuTranslations {
            XCTAssertEqual(
                english.localizedString(forKey: key, value: nil, table: nil),
                translation.0
            )
            XCTAssertEqual(
                russian.localizedString(forKey: key, value: nil, table: nil),
                translation.1
            )
        }
        XCTAssertNotEqual(
            english.localizedString(forKey: "menu.object_mix.hint", value: nil, table: nil),
            "menu.object_mix.hint"
        )
        XCTAssertNotEqual(
            russian.localizedString(forKey: "menu.object_mix.hint", value: nil, table: nil),
            "menu.object_mix.hint"
        )
        let objectMixMenuLines = [
            "Object Mix (3:3:3)",
            "Higher weight, more often",
            "0 excludes the category",
            "Space — 3",
            "Animals — 3",
            "Characters — 3",
            "0 — Off",
            "Higher — more often",
            "Состав объектов (3:3:3)",
            "Чем выше вес, тем чаще",
            "0 исключает категорию",
            "Космос — 3",
            "Зверюшки — 3",
            "Персонажи — 3",
            "0 — Не показывать",
            "Больше — чаще"
        ]
        for line in objectMixMenuLines {
            XCTAssertLessThanOrEqual(line.count, 30, line)
        }
        XCTAssertEqual(
            String.localizedStringWithFormat(
                english.localizedString(
                    forKey: "menu.object_mix.matrix.cell.accessibility.format",
                    value: nil,
                    table: nil
                ),
                "Space",
                english.localizedString(
                    forKey: "menu.object_mix.matrix.zero.accessibility",
                    value: nil,
                    table: nil
                )
            ),
            "Space, weight 0, Off"
        )
        XCTAssertEqual(
            String.localizedStringWithFormat(
                russian.localizedString(
                    forKey: "menu.object_mix.matrix.cell.accessibility.format",
                    value: nil,
                    table: nil
                ),
                "Космос",
                russian.localizedString(
                    forKey: "menu.object_mix.matrix.zero.accessibility",
                    value: nil,
                    table: nil
                )
            ),
            "Космос, вес 0, Не показывать"
        )
    }

    func testTurboBadgeHighlightEligibilityMatrix() {
        XCTAssertTrue(
            QuotaTooltipView.isTurboBadgeHighlightEligible(
                isTooltipPresented: true,
                speedMode: .turbo,
                connectionState: .connected,
                remainingPercent: 1,
                reduceMotion: false
            )
        )

        let ineligibleCases: [(Bool, SpeedMode, ConnectionState, Int?, Bool)] = [
            (true, .standard, .connected, 1, false),
            (false, .turbo, .connected, 1, false),
            (true, .turbo, .connected, 1, true),
            (true, .turbo, .connected, 0, false),
            (true, .turbo, .connected, nil, false),
            (true, .turbo, .connecting, 1, false),
            (true, .turbo, .reconnecting, 1, false),
            (true, .turbo, .disconnected, 1, false)
        ]
        for (isPresented, mode, connection, remainingPercent, reduceMotion) in ineligibleCases {
            XCTAssertFalse(
                QuotaTooltipView.isTurboBadgeHighlightEligible(
                    isTooltipPresented: isPresented,
                    speedMode: mode,
                    connectionState: connection,
                    remainingPercent: remainingPercent,
                    reduceMotion: reduceMotion
                )
            )
        }
    }

    @MainActor
    func testTooltipAccessibilitySummaryContainsModeAndConnectionOnce() {
        for mode in [SpeedMode.standard, .turbo] {
            let summary = QuotaTooltipView.accessibilitySummary(
                remainingPercent: 42,
                speedMode: mode,
                connectionState: .connected,
                resetDate: nil
            )

            XCTAssertEqual(summary.components(separatedBy: mode.title).count - 1, 1)
            XCTAssertEqual(
                summary.components(separatedBy: ConnectionState.connected.title).count - 1,
                1
            )
        }
    }

    @MainActor
    func testTooltipDaySegmentsComeFromQuotaWindow() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetDate = now.addingTimeInterval(5 * 86_400 + 23 * 3_600)

        XCTAssertEqual(
            QuotaTooltipView.dayIndicator(
                resetDate: resetDate,
                now: now,
                windowDurationMinutes: 10_080
            ),
            .init(activeSegments: 5, totalSegments: 7)
        )
        XCTAssertNil(
            QuotaTooltipView.dayIndicator(
                resetDate: nil,
                now: now,
                windowDurationMinutes: 10_080
            )
        )
        XCTAssertNil(
            QuotaTooltipView.dayIndicator(
                resetDate: resetDate,
                now: now,
                windowDurationMinutes: nil
            )
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        XCTAssertTrue(
            QuotaTooltipView.localizedDayCount(
                1,
                locale: Locale(identifier: "ru_RU"),
                calendar: calendar
            ).contains("день")
        )
        XCTAssertTrue(
            QuotaTooltipView.localizedDayCount(
                2,
                locale: Locale(identifier: "ru_RU"),
                calendar: calendar
            ).contains("дня")
        )
        XCTAssertTrue(
            QuotaTooltipView.localizedDayCount(
                5,
                locale: Locale(identifier: "ru_RU"),
                calendar: calendar
            ).contains("дней")
        )
    }

    @MainActor
    func testTooltipResetCountdownUsesDaysHoursMinutesAndSeconds() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        func duration(_ seconds: TimeInterval, locale: String) -> String {
            QuotaTooltipView.localizedResetDuration(
                until: now.addingTimeInterval(seconds),
                now: now,
                locale: Locale(identifier: locale),
                calendar: calendar
            )
        }

        XCTAssertEqual(duration(86_400, locale: "en_US"), "1 day")
        XCTAssertEqual(duration(86_399, locale: "en_US"), "23h")
        XCTAssertEqual(duration(3_600, locale: "en_US"), "1h")
        XCTAssertEqual(duration(3_599, locale: "en_US"), "59m 59s")
        XCTAssertEqual(duration(0, locale: "en_US"), "0m 0s")
        XCTAssertEqual(duration(-1, locale: "en_US"), "0m 0s")

        XCTAssertEqual(duration(86_400, locale: "ru_RU"), "1 день")
        XCTAssertEqual(duration(86_399, locale: "ru_RU"), "23 ч")
        XCTAssertEqual(duration(3_600, locale: "ru_RU"), "1 ч")
        XCTAssertEqual(duration(3_599, locale: "ru_RU"), "59 мин 59 с")
        XCTAssertEqual(duration(0, locale: "ru_RU"), "0 мин 0 с")

        XCTAssertEqual(
            QuotaTooltipView.resetCountdownUpdateDelay(
                resetDate: now.addingTimeInterval(3_599),
                now: now
            ),
            1
        )
        XCTAssertEqual(
            QuotaTooltipView.resetCountdownUpdateDelay(
                resetDate: now.addingTimeInterval(3_600),
                now: now
            ),
            0.05,
            accuracy: 0.001
        )
        XCTAssertEqual(
            QuotaTooltipView.resetCountdownUpdateDelay(resetDate: nil, now: now),
            60
        )
    }

    @MainActor
    func testTooltipQuotaLevelsUseRequestedBoundaries() {
        XCTAssertEqual(QuotaTooltipView.quotaLevel(for: 100), .normal)
        XCTAssertEqual(QuotaTooltipView.quotaLevel(for: 30), .normal)
        XCTAssertEqual(QuotaTooltipView.quotaLevel(for: 29), .warning)
        XCTAssertEqual(QuotaTooltipView.quotaLevel(for: 10), .warning)
        XCTAssertEqual(QuotaTooltipView.quotaLevel(for: 9), .critical)
        XCTAssertEqual(QuotaTooltipView.quotaLevel(for: 0), .critical)
        XCTAssertEqual(QuotaTooltipView.quotaLevel(for: nil), .normal)
    }

    func testSharedTooltipContentCoversBoundariesAndPartialResetData() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetDate = now.addingTimeInterval(2 * 86_400)
        let content = QuotaTooltipContent(
            remainingPercent: 125,
            speedMode: .turbo,
            connectionState: .reconnecting,
            resetDate: resetDate,
            windowDurationMinutes: nil,
            now: now,
            locale: Locale(identifier: "en_US"),
            calendar: calendar
        )

        XCTAssertEqual(content.progressFraction, 1)
        XCTAssertTrue(content.isStale)
        XCTAssertNil(content.dayIndicator)
        XCTAssertNotNil(content.compactResetText)
        XCTAssertFalse(content.resetCountdownText.isEmpty)

        let missing = QuotaTooltipContent(
            remainingPercent: nil,
            speedMode: .standard,
            connectionState: .disconnected,
            resetDate: nil,
            windowDurationMinutes: nil,
            now: now,
            locale: Locale(identifier: "ru_RU"),
            calendar: calendar
        )
        XCTAssertEqual(missing.progressFraction, 0)
        XCTAssertFalse(missing.isStale)
        XCTAssertNil(missing.compactResetText)
        XCTAssertNil(missing.dayIndicator)
        XCTAssertFalse(missing.accessibilitySummary.isEmpty)
    }

    @MainActor
    func testTooltipResetDateOmitsOnlyCurrentYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 2, hour: 12))
        )
        let thisYear = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 8, hour: 10, minute: 58))
        )
        let nextYear = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2027, month: 8, day: 8, hour: 10, minute: 58))
        )

        let currentParts = QuotaTooltipView.resetDateParts(
            thisYear,
            relativeTo: now,
            locale: Locale(identifier: "ru_RU"),
            calendar: calendar
        )
        let futureParts = QuotaTooltipView.resetDateParts(
            nextYear,
            relativeTo: now,
            locale: Locale(identifier: "ru_RU"),
            calendar: calendar
        )

        XCTAssertFalse(currentParts.date.contains("2026"))
        XCTAssertTrue(futureParts.date.contains("2027"))
        XCTAssertFalse(currentParts.time.isEmpty)
    }

    func testTurboAnimationIsFasterAndPulses() {
        let full = PetVisualState(remainingPercent: 100)
        let empty = PetVisualState(remainingPercent: 0)

        XCTAssertEqual(
            full.rotationSpeed(for: .turbo),
            full.rotationSpeed(for: .standard) * 1.5,
            accuracy: 0.001
        )
        XCTAssertEqual(empty.rotationSpeed(for: .standard), 0.1, accuracy: 0.001)
        XCTAssertTrue(full.shouldPulse(in: .turbo))
        XCTAssertFalse(full.shouldPulse(in: .standard))
        XCTAssertFalse(empty.shouldPulse(in: .turbo))
    }

    func testQuotaSelectsNearestSpriteState() {
        let expectations = [
            (100, 100), (95, 100), (94, 90),
            (55, 60), (54, 50),
            (25, 30), (24, 20),
            (5, 10), (4, 0), (0, 0)
        ]

        for (remainingPercent, spritePercent) in expectations {
            XCTAssertEqual(
                PetVisualState(remainingPercent: remainingPercent).spriteStatePercent,
                spritePercent
            )
        }
    }

    func testEveryQuotaStateHasSixBundledFrames() {
        let appBundle = Bundle(for: AppDelegate.self)

        for percent in stride(from: 100, through: 0, by: -10) {
            let state = PetVisualState(remainingPercent: percent)
            XCTAssertEqual(state.spriteStatePercent, percent)

            for frame in 0..<PetVisualState.spriteFrameCount {
                XCTAssertNotNil(
                    appBundle.url(
                        forResource: "quota-\(percent)-frame-\(frame)",
                        withExtension: "png",
                        subdirectory: "frames"
                    ),
                    "Missing \(percent)% frame \(frame)"
                )
            }
        }
    }

    func testQuotaConsumptionPreviewMastersAreBundledAndValid() throws {
        let appBundle = Bundle(for: AppDelegate.self)
        let expectations: [(QuotaConsumptionPreviewKind, Int, String, String)] = [
            (.small, 10, "quota-50-frame-0", "quota-50-frame-0"),
            (.medium, 20, "quota-50-frame-0", "quota-50-frame-0"),
            (.large, 30, "quota-50-frame-0", "quota-50-frame-0"),
            (.lastLight, 40, "quota-10-frame-0", "quota-0-frame-0")
        ]

        func rgba(_ image: CGImage) throws -> Data {
            let byteCount = image.width * image.height * 4
            let context = try XCTUnwrap(
                CGContext(
                    data: nil,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: image.width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            )
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
            )
            return Data(bytes: try XCTUnwrap(context.data), count: byteCount)
        }

        func bundledPNG(named name: String) throws -> Data {
            let url = try XCTUnwrap(
                appBundle.url(
                    forResource: name,
                    withExtension: "png",
                    subdirectory: "frames"
                )
            )
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            return try rgba(try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil)))
        }

        for (kind, frameCount, firstName, lastName) in expectations {
            let url = try XCTUnwrap(
                appBundle.url(
                    forResource: kind.assetName,
                    withExtension: "apng",
                    subdirectory: "frames"
                )
            )
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            XCTAssertEqual(CGImageSourceGetCount(source), frameCount)
            let container = try XCTUnwrap(
                CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
            )
            let containerPNG = try XCTUnwrap(
                container[kCGImagePropertyPNGDictionary] as? [CFString: Any]
            )
            XCTAssertEqual(
                (containerPNG[kCGImagePropertyAPNGLoopCount] as? NSNumber)?.intValue,
                1
            )

            var decoded: [Data] = []
            for index in 0..<frameCount {
                let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, index, nil))
                XCTAssertEqual(image.width, 384)
                XCTAssertEqual(image.height, 272)
                XCTAssertEqual(
                    image.colorSpace?.name.map { $0 as String },
                    CGColorSpace.sRGB as String
                )
                let properties = try XCTUnwrap(
                    CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                        as? [CFString: Any]
                )
                let png = try XCTUnwrap(
                    properties[kCGImagePropertyPNGDictionary] as? [CFString: Any]
                )
                let delay = try XCTUnwrap(
                    (png[kCGImagePropertyAPNGUnclampedDelayTime]
                        ?? png[kCGImagePropertyAPNGDelayTime]) as? NSNumber
                )
                XCTAssertEqual(
                    delay.doubleValue,
                    QuotaConsumptionPreviewAnimation.frameDuration,
                    accuracy: 0.002
                )

                let pixels = try rgba(image)
                for y in 0..<image.height {
                    for x in 0..<image.width
                    where x < 10 || x >= image.width - 10
                        || y < 10 || y >= image.height - 10 {
                        XCTAssertEqual(
                            pixels[(y * image.width + x) * 4 + 3],
                            0,
                            "Visible safe-inset pixel in \(kind.rawValue) frame \(index)"
                        )
                    }
                }
                decoded.append(pixels)
            }

            XCTAssertEqual(
                Double(frameCount) * QuotaConsumptionPreviewAnimation.frameDuration,
                Double(frameCount) / 24,
                accuracy: 0.000_001
            )
            XCTAssertEqual(decoded.first, try bundledPNG(named: firstName))
            XCTAssertEqual(decoded.last, try bundledPNG(named: lastName))
            XCTAssertEqual(
                Set(decoded).count,
                kind == .lastLight ? frameCount : frameCount - 1
            )
            let runtimeFrames = try XCTUnwrap(
                QuotaConsumptionPreviewAnimation.load(kind: kind, bundle: appBundle)?.frames
            )
            XCTAssertEqual(runtimeFrames.count, frameCount)
            XCTAssertEqual(try runtimeFrames.map(rgba), decoded)
        }

        XCTAssertNil(
            QuotaConsumptionPreviewAnimation.load(
                kind: .small,
                bundle: Bundle(for: RateLimitDecodingTests.self)
            )
        )
    }

    func testQuotaConsumptionProductionManifestAndReduceMotionAssets() throws {
        let bundle = Bundle(for: AppDelegate.self)
        let manifest = try XCTUnwrap(QuotaConsumptionManifest.load(bundle: bundle))
        XCTAssertEqual(manifest.entries.count, 264)
        XCTAssertEqual(
            Set(manifest.entries.map { "\($0.kind.rawValue)-\($0.bucket)-\($0.phase)" }).count,
            264
        )

        func rgba(_ image: CGImage) throws -> Data {
            let context = try XCTUnwrap(CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return Data(bytes: try XCTUnwrap(context.data), count: image.width * image.height * 4)
        }

        var idleCache: [String: Data] = [:]
        func idle(bucket: Int, phase: Int) throws -> Data {
            let key = "\(bucket)-\(phase)"
            if let cached = idleCache[key] { return cached }
            let url = try XCTUnwrap(bundle.url(
                forResource: "quota-\(bucket)-frame-\(phase)",
                withExtension: "png",
                subdirectory: "frames"
            ))
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let pixels = try rgba(try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil)))
            idleCache[key] = pixels
            return pixels
        }

        for entry in manifest.entries {
            XCTAssertTrue(stride(from: 0, through: 100, by: 10).contains(entry.bucket))
            XCTAssertTrue((0..<6).contains(entry.phase))
            XCTAssertEqual(entry.frameCount, entry.kind.frameCount)
            XCTAssertEqual(entry.duration, Double(entry.frameCount) / 24, accuracy: 0.000_001)
            let url = try XCTUnwrap(bundle.url(
                forResource: entry.path,
                withExtension: nil,
                subdirectory: "frames/consumption"
            ))
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            XCTAssertEqual(CGImageSourceGetCount(source), entry.frameCount)
            let container = try XCTUnwrap(
                CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
            )
            let containerPNG = try XCTUnwrap(
                container[kCGImagePropertyPNGDictionary] as? [CFString: Any]
            )
            XCTAssertEqual(
                (containerPNG[kCGImagePropertyAPNGLoopCount] as? NSNumber)?.intValue,
                1
            )
            let first = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let last = try XCTUnwrap(
                CGImageSourceCreateImageAtIndex(source, entry.frameCount - 1, nil)
            )
            XCTAssertEqual(first.width, 384)
            XCTAssertEqual(first.height, 272)
            XCTAssertEqual(
                first.colorSpace?.name.map { $0 as String },
                CGColorSpace.sRGB as String
            )
            XCTAssertEqual(try rgba(first), try idle(bucket: entry.bucket, phase: entry.phase))
            XCTAssertEqual(
                try rgba(last),
                try idle(
                    bucket: entry.kind == .lastLight ? 0 : entry.bucket,
                    phase: entry.phase
                )
            )
            for index in 0..<entry.frameCount {
                let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, index, nil))
                XCTAssertEqual(
                    image.colorSpace?.name.map { $0 as String },
                    CGColorSpace.sRGB as String
                )
                let pixels = try rgba(image)
                let activeBase = try idle(
                    bucket: entry.kind == .lastLight && index >= 32 ? 0 : entry.bucket,
                    phase: entry.phase
                )
                var insetIsClear = true
                var alphaCoversBase = true
                var shadowMatchesBase = true
                for y in 0..<image.height {
                    for x in 0..<image.width {
                        let offset = (y * image.width + x) * 4
                        if x < 10 || x >= image.width - 10
                            || y < 10 || y >= image.height - 10 {
                            insetIsClear = insetIsClear && pixels[offset + 3] == 0
                        }
                        alphaCoversBase = alphaCoversBase
                            && pixels[offset + 3] >= activeBase[offset + 3]
                        let dx = x - 192
                        let dy = y - 136
                        if dx * dx + dy * dy < 42 * 42 {
                            shadowMatchesBase = shadowMatchesBase
                                && pixels[offset..<(offset + 4)]
                                    == activeBase[offset..<(offset + 4)]
                        }
                    }
                }
                XCTAssertTrue(insetIsClear, "Inset \(entry.path) frame \(index)")
                XCTAssertTrue(alphaCoversBase, "Alpha \(entry.path) frame \(index)")
                XCTAssertTrue(shadowMatchesBase, "Shadow \(entry.path) frame \(index)")
                let properties = try XCTUnwrap(
                    CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                        as? [CFString: Any]
                )
                let png = try XCTUnwrap(
                    properties[kCGImagePropertyPNGDictionary] as? [CFString: Any]
                )
                let delay = try XCTUnwrap(
                    (png[kCGImagePropertyAPNGUnclampedDelayTime]
                        ?? png[kCGImagePropertyAPNGDelayTime]) as? NSNumber
                )
                XCTAssertEqual(delay.doubleValue, 1.0 / 24.0, accuracy: 0.002)
            }
        }

        for kind in QuotaConsumptionReactionKind.allCases {
            let event = QuotaConsumptionReactionEvent(id: 1, kind: kind, bucket: 50)
            let animation = try XCTUnwrap(
                QuotaConsumptionPreviewAnimation.load(event: event, phase: 0, reduceMotion: false, bundle: bundle)
            )
            XCTAssertEqual(animation.frames.count, kind.frameCount)
            XCTAssertEqual(animation.slotDuration, 1.0 / 24.0, accuracy: 0.002)
            XCTAssertFalse(animation.isOverlay)
        }

        let reduced = try XCTUnwrap(QuotaConsumptionPreviewAnimation.load(
            event: .init(id: 2, kind: .medium, bucket: 50),
            phase: 0,
            reduceMotion: true,
            bundle: bundle
        ))
        XCTAssertEqual(reduced.frames.count, 3)
        XCTAssertEqual(reduced.slotDuration, 0.12, accuracy: 0.002)
        XCTAssertEqual(reduced.duration, 0.36, accuracy: 0.002)
        XCTAssertTrue(reduced.isOverlay)
        XCTAssertEqual(try Set(reduced.frames.map(rgba)).count, 3)
        XCTAssertNil(QuotaConsumptionPreviewAnimation.load(
            event: .init(id: 3, kind: .lastLight, bucket: 0),
            phase: 0,
            reduceMotion: true,
            bundle: bundle
        ))
        XCTAssertNil(QuotaConsumptionPreviewAnimation.load(
            event: .init(id: 4, kind: .small, bucket: 50),
            phase: 0,
            reduceMotion: false,
            bundle: Bundle(for: RateLimitDecodingTests.self)
        ))
        for frame in reduced.frames {
            let pixels = try rgba(frame)
            for y in 0..<frame.height {
                for x in 0..<frame.width where x < 10 || x >= frame.width - 10
                    || y < 10 || y >= frame.height - 10 {
                    XCTAssertEqual(pixels[(y * frame.width + x) * 4 + 3], 0)
                }
            }
            for y in 94..<178 {
                for x in 150..<234 where (x - 192) * (x - 192) + (y - 136) * (y - 136) < 42 * 42 {
                    XCTAssertEqual(pixels[(y * frame.width + x) * 4 + 3], 0)
                }
            }
        }
    }

    func testQuotaConsumptionLoaderCancellationAndLastLightLoadingSource() throws {
        let bundle = Bundle(for: AppDelegate.self)
        let event = QuotaConsumptionReactionEvent(id: 1, kind: .lastLight, bucket: 10)
        let sourceName = QuotaConsumptionPreviewAnimation.frozenIdleSpriteName(
            activeEvent: event,
            authoritativeBucket: 0,
            phase: 4
        )
        XCTAssertEqual(sourceName, "quota-10-frame-4")
        XCTAssertNotNil(bundle.url(
            forResource: sourceName,
            withExtension: "png",
            subdirectory: "frames"
        ))
        XCTAssertEqual(
            QuotaConsumptionPreviewAnimation.frozenIdleSpriteName(
                activeEvent: nil,
                authoritativeBucket: 0,
                phase: 4
            ),
            "quota-0-frame-4"
        )

        var checks = 0
        let cancelled = QuotaConsumptionPreviewAnimation.load(
            event: event,
            phase: 4,
            reduceMotion: false,
            bundle: bundle,
            isCancelled: {
                checks += 1
                return checks == 4
            }
        )
        XCTAssertNil(cancelled)
        XCTAssertEqual(checks, 4)
    }

    func testQuotaFramesExcludeRightEdgeMasterSheetBleed() throws {
        let appBundle = Bundle(for: AppDelegate.self)

        for percent in [40, 10] {
            for frame in 0..<PetVisualState.spriteFrameCount {
                let url = try XCTUnwrap(
                    appBundle.url(
                        forResource: "quota-\(percent)-frame-\(frame)",
                        withExtension: "png",
                        subdirectory: "frames"
                    )
                )
                let bitmap = try XCTUnwrap(
                    NSBitmapImageRep(data: Data(contentsOf: url))
                )

                for y in 0..<bitmap.pixelsHigh {
                    for x in 350..<bitmap.pixelsWide {
                        XCTAssertEqual(
                            bitmap.colorAt(x: x, y: y)?.alphaComponent,
                            0,
                            "Unexpected pixel in \(percent)% frame \(frame) at (\(x), \(y))"
                        )
                    }
                }
            }
        }
    }

    func testAbsorbableObjectManifestAndSpritesAreBundled() throws {
        let appBundle = Bundle(for: AppDelegate.self)
        let catalog = try AbsorbableObjectCatalog(bundle: appBundle)

        XCTAssertEqual(catalog.manifest.canvas, .init(width: 80, height: 80))
        XCTAssertEqual(catalog.manifest.objects.count, 34)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: catalog.manifest.categories.map { ($0.id, $0.weight) }),
            ["space": 2, "animals": 2, "characters": 1]
        )
        XCTAssertEqual(
            catalog.manifest.objects.filter { $0.category == "characters" }.count,
            10
        )

        for object in catalog.manifest.objects {
            let url = try XCTUnwrap(
                appBundle.url(
                    forResource: object.asset,
                    withExtension: "png",
                    subdirectory: "objects"
                ),
                "Missing asset for \(object.id)"
            )
            let image = try XCTUnwrap(NSImage(contentsOf: url))
            let data = try XCTUnwrap(image.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
            XCTAssertEqual(bitmap.pixelsWide, 80, object.id)
            XCTAssertEqual(bitmap.pixelsHigh, 80, object.id)
            XCTAssertEqual(bitmap.colorAt(x: 0, y: 0)?.alphaComponent, 0, object.id)
            XCTAssertEqual(bitmap.colorAt(x: 79, y: 79)?.alphaComponent, 0, object.id)
        }
    }

    func testAbsorbableObjectSelectionUsesApprovedCategoryWeightsAndNoRepeat() throws {
        let catalog = try AbsorbableObjectCatalog(bundle: Bundle(for: AppDelegate.self))

        XCTAssertEqual(
            catalog.select(excluding: nil, categoryRoll: 0, objectRoll: 0)?.category,
            "space"
        )
        XCTAssertEqual(
            catalog.select(excluding: nil, categoryRoll: 0.4, objectRoll: 0)?.category,
            "animals"
        )
        XCTAssertEqual(
            catalog.select(excluding: nil, categoryRoll: 0.8, objectRoll: 0)?.category,
            "characters"
        )

        let first = try XCTUnwrap(
            catalog.select(excluding: nil, categoryRoll: 0, objectRoll: 0)
        )
        let second = try XCTUnwrap(
            catalog.select(excluding: first.id, categoryRoll: 0, objectRoll: 0)
        )
        XCTAssertNotEqual(first.id, second.id)
    }

    func testAbsorbableObjectSelectionUsesEffectiveWeightsAcrossAllValidMixes() throws {
        let catalog = try AbsorbableObjectCatalog(bundle: Bundle(for: AppDelegate.self))
        func rolls(at cumulative: Int, total: Int) -> (before: Double, boundary: Double) {
            var boundary = Double(cumulative) / Double(total)
            while boundary * Double(total) < Double(cumulative) {
                boundary = boundary.nextUp
            }
            var before = boundary.nextDown
            while before * Double(total) >= Double(cumulative) {
                before = before.nextDown
            }
            return (before, boundary)
        }

        XCTAssertEqual(
            catalog.select(
                excluding: nil,
                categoryWeights: ["space": 0, "animals": 3, "characters": 0],
                categoryRoll: 0,
                objectRoll: 0
            )?.category,
            "animals"
        )
        XCTAssertEqual(
            catalog.select(
                excluding: nil,
                categoryWeights: ["space": 3, "animals": 1, "characters": 0],
                categoryRoll: 0.749_999,
                objectRoll: 0
            )?.category,
            "space"
        )
        XCTAssertEqual(
            catalog.select(
                excluding: nil,
                categoryWeights: ["space": 3, "animals": 1, "characters": 0],
                categoryRoll: 0.75,
                objectRoll: 0
            )?.category,
            "animals"
        )
        let animals = catalog.manifest.objects.filter { $0.category == "animals" }
        for (index, animal) in animals.enumerated() {
            let roll = rolls(at: index + 1, total: animals.count)
            XCTAssertEqual(
                catalog.select(
                    excluding: nil,
                    categoryWeights: ["space": 0, "animals": 1, "characters": 0],
                    categoryRoll: 0.5,
                    objectRoll: roll.before
                )?.id,
                animal.id
            )
            XCTAssertEqual(
                catalog.select(
                    excluding: nil,
                    categoryWeights: ["space": 0, "animals": 1, "characters": 0],
                    categoryRoll: 0.5,
                    objectRoll: roll.boundary
                )?.id,
                animals[min(index + 1, animals.count - 1)].id
            )
        }

        var validMixCount = 0
        for space in 0...3 {
            for animals in 0...3 {
                for characters in 0...3 where space + animals + characters > 0 {
                    let weights = [
                        "space": space,
                        "animals": animals,
                        "characters": characters
                    ]
                    let activeCategories = catalog.manifest.categories.filter {
                        weights[$0.id, default: 0] > 0
                    }
                    let totalWeight = activeCategories.reduce(0) {
                        $0 + weights[$1.id, default: 0]
                    }
                    var cumulativeWeight = 0
                    for (index, category) in activeCategories.enumerated() {
                        cumulativeWeight += weights[category.id, default: 0]
                        let roll = rolls(at: cumulativeWeight, total: totalWeight)
                        XCTAssertEqual(
                            catalog.select(
                                excluding: nil,
                                categoryWeights: weights,
                                categoryRoll: roll.before,
                                objectRoll: 0
                            )?.category,
                            category.id
                        )
                        XCTAssertEqual(
                            catalog.select(
                                excluding: nil,
                                categoryWeights: weights,
                                categoryRoll: roll.boundary,
                                objectRoll: 0
                            )?.category,
                            activeCategories[min(index + 1, activeCategories.count - 1)].id
                        )
                    }
                    validMixCount += 1
                }
            }
        }
        XCTAssertEqual(validMixCount, 63)
    }

    func testAbsorbableObjectSelectionRepeatsOnlyAvailableModel() throws {
        let catalog = try makeAbsorbableObjectCatalog(
            categories: [("only", 1)],
            objects: [("single", "only")]
        )

        XCTAssertEqual(
            catalog.select(
                excluding: "single",
                categoryWeights: ["only": 1],
                categoryRoll: 0.5,
                objectRoll: 0.5
            )?.id,
            "single"
        )
    }

    private func makeAbsorbableObjectCatalog(
        categories: [(String, Int)],
        objects: [(String, String)]
    ) throws -> AbsorbableObjectCatalog {
        let json: [String: Any] = [
            "canvas": ["width": 80, "height": 80],
            "categories": categories.map { ["id": $0.0, "weight": $0.1] },
            "objects": objects.map {
                ["id": $0.0, "category": $0.1, "asset": $0.0]
            }
        ]
        return try AbsorbableObjectCatalog(data: JSONSerialization.data(withJSONObject: json))
    }

    func testAbsorptionPathsDeformBreakUpAndRespectReducedMotion() {
        let object = AbsorbableObjectManifest.Object(
            id: "test",
            category: "space",
            asset: "test"
        )
        let startDate = Date(timeIntervalSince1970: 1_000)
        let plan = AbsorptionPlan(
            object: object,
            startDate: startDate,
            duration: 1,
            side: .left,
            seed: 42,
            usesReducedMotion: false
        )
        let start = AbsorptionVisualState.make(
            plan: plan,
            at: startDate,
            sceneSize: BlackHoleView.size
        )
        let deformed = AbsorptionVisualState.make(
            plan: plan,
            at: startDate.addingTimeInterval(0.95),
            sceneSize: BlackHoleView.size
        )
        let finished = AbsorptionVisualState.make(
            plan: plan,
            at: startDate.addingTimeInterval(1),
            sceneSize: BlackHoleView.size
        )

        XCTAssertLessThan(start.position.x, BlackHoleView.size.width / 2)
        XCTAssertEqual(deformed.longitudinalScale, 2.5, accuracy: 0.001)
        XCTAssertEqual(deformed.transverseScale, 0.5, accuracy: 0.001)
        XCTAssertGreaterThan(deformed.breakupProgress, 0.9)
        XCTAssertEqual(finished.opacity, 0, accuracy: 0.001)
        XCTAssertEqual(finished.position.x, BlackHoleView.size.width / 2, accuracy: 1)
        XCTAssertEqual(finished.position.y, BlackHoleView.size.height / 2, accuracy: 1)

        let reducedPlan = AbsorptionPlan(
            object: object,
            startDate: startDate,
            duration: 0.225,
            side: .top,
            seed: 7,
            usesReducedMotion: true
        )
        let reduced = AbsorptionVisualState.make(
            plan: reducedPlan,
            at: startDate.addingTimeInterval(0.15),
            sceneSize: BlackHoleView.size
        )
        XCTAssertEqual(reduced.longitudinalScale, 1)
        XCTAssertEqual(reduced.transverseScale, 1)
        XCTAssertEqual(reduced.breakupProgress, 0)
        XCTAssertLessThan(reduced.opacity, 1)
    }

    func testAbsorptionUsesProportionalSizesAndStaysInsideEveryPetSize() {
        let object = AbsorbableObjectManifest.Object(
            id: "test",
            category: "animals",
            asset: "absorb-bear-cub"
        )
        let startDate = Date(timeIntervalSince1970: 1_000)
        let seeds: [UInt64] = [0, 1, 29, 42, 155, 607, 965, 988, .max]

        let expectedSizes: [(PetSize, object: CGFloat, renderField: CGFloat)] = [
            (.small, 48, 60),
            (.medium, 64, 80),
            (.large, 80, 100)
        ]

        for (petSize, expectedObjectSize, expectedRenderFieldSize) in expectedSizes {
            let sceneSize = petSize.sceneSize
            let safeFrame = CGRect(origin: .zero, size: sceneSize).insetBy(
                dx: AbsorptionVisualState.renderingInset,
                dy: AbsorptionVisualState.renderingInset
            )
            for usesReducedMotion in [false, true] {
                for side in AbsorptionSpawnSide.allCases {
                    for seed in seeds {
                        let plan = AbsorptionPlan(
                            object: object,
                            startDate: startDate,
                            duration: 1,
                            side: side,
                            seed: seed,
                            usesReducedMotion: usesReducedMotion
                        )
                        for sample in 0...40 {
                            let state = AbsorptionVisualState.make(
                                plan: plan,
                                at: startDate.addingTimeInterval(Double(sample) / 40),
                                sceneSize: sceneSize
                            )
                            XCTAssertEqual(
                                state.objectSize,
                                expectedObjectSize,
                                "\(petSize) reducedMotion=\(usesReducedMotion)"
                            )
                            XCTAssertEqual(
                                state.renderFieldSize,
                                expectedRenderFieldSize,
                                "\(petSize) reducedMotion=\(usesReducedMotion)"
                            )
                            let frame = state.renderedFrame
                            let context = "\(petSize) \(side) seed=\(seed) sample=\(sample) reducedMotion=\(usesReducedMotion)"
                            XCTAssertGreaterThanOrEqual(frame.minX, safeFrame.minX, context)
                            XCTAssertGreaterThanOrEqual(frame.minY, safeFrame.minY, context)
                            XCTAssertLessThanOrEqual(frame.maxX, safeFrame.maxX, context)
                            XCTAssertLessThanOrEqual(frame.maxY, safeFrame.maxY, context)
                        }
                    }
                }
            }
        }
    }

    func testAbsorptionRotationStaysStableOnPixelSnappedPath() {
        let object = AbsorbableObjectManifest.Object(
            id: "test",
            category: "space",
            asset: "test"
        )
        let startDate = Date(timeIntervalSince1970: 2_000)
        let plan = AbsorptionPlan(
            object: object,
            startDate: startDate,
            duration: 1,
            side: .right,
            seed: 42,
            usesReducedMotion: false
        )
        let states = (0...30).map { frame in
            AbsorptionVisualState.make(
                plan: plan,
                at: startDate.addingTimeInterval(Double(frame) / 30),
                sceneSize: BlackHoleView.size
            )
        }

        for state in states {
            XCTAssertEqual(state.position.x * 2, (state.position.x * 2).rounded())
            XCTAssertEqual(state.position.y * 2, (state.position.y * 2).rounded())
        }
        for (current, next) in zip(states, states.dropFirst()) {
            let delta = next.rotation.radians - current.rotation.radians
            let angularDistance = abs(atan2(sin(delta), cos(delta)))
            XCTAssertLessThan(angularDistance, 0.35)
        }
    }

    func testAbsorptionUsesDifferentSpawnSidesWhenAvailable() {
        XCTAssertEqual(AbsorptionPlan.spawnSide(excluding: [], roll: 0), .left)
        XCTAssertEqual(
            AbsorptionPlan.spawnSide(excluding: [.left], roll: 0),
            .top
        )
        XCTAssertEqual(
            AbsorptionPlan.spawnSide(excluding: [.left, .top, .right], roll: 0),
            .bottom
        )
    }

    func testAbsorptionClickThresholdKeepsPanelDrag() {
        let center = CGPoint(
            x: BlackHoleView.size.width / 2,
            y: BlackHoleView.size.height / 2
        )
        XCTAssertTrue(
            AbsorptionInteraction.acceptsClick(
                mouseDown: center,
                mouseUp: CGPoint(x: center.x + 6, y: center.y),
                sceneSize: BlackHoleView.size
            )
        )
        XCTAssertFalse(
            AbsorptionInteraction.acceptsClick(
                mouseDown: center,
                mouseUp: CGPoint(x: center.x + 6.01, y: center.y),
                sceneSize: BlackHoleView.size
            )
        )
        XCTAssertFalse(
            AbsorptionInteraction.acceptsClick(
                mouseDown: CGPoint(x: 0, y: 0),
                mouseUp: CGPoint(x: 0, y: 0),
                sceneSize: BlackHoleView.size
            )
        )

        let smallCenter = CGPoint(
            x: PetSize.small.sceneSize.width / 2,
            y: PetSize.small.sceneSize.height / 2
        )
        XCTAssertTrue(
            AbsorptionInteraction.acceptsClick(
                mouseDown: CGPoint(x: smallCenter.x + 33, y: smallCenter.y),
                mouseUp: CGPoint(x: smallCenter.x + 33, y: smallCenter.y),
                sceneSize: PetSize.small.sceneSize
            )
        )
        XCTAssertFalse(
            AbsorptionInteraction.acceptsClick(
                mouseDown: CGPoint(x: smallCenter.x + 34, y: smallCenter.y),
                mouseUp: CGPoint(x: smallCenter.x + 34, y: smallCenter.y),
                sceneSize: PetSize.small.sceneSize
            )
        )
    }

    func testAbsorptionFlashStaysRestrained() {
        XCTAssertGreaterThan(BlackHoleView.reactionBrightness, 0)
        XCTAssertLessThanOrEqual(BlackHoleView.reactionBrightness, 0.2)
    }

    func testSpriteFramesLoopAndTurboAdvancesFaster() {
        let state = PetVisualState(remainingPercent: 100)

        XCTAssertEqual(state.spriteFrameIndex(elapsedTime: 0, speedMode: .standard), 0)
        XCTAssertEqual(state.spriteFrameIndex(elapsedTime: 0.10, speedMode: .standard), 0)
        XCTAssertEqual(state.spriteFrameIndex(elapsedTime: 0.10, speedMode: .turbo), 1)
        XCTAssertEqual(state.spriteFrameIndex(elapsedTime: 0.14, speedMode: .standard), 1)
        XCTAssertEqual(state.spriteFrameIndex(elapsedTime: 0.85, speedMode: .standard), 0)
        XCTAssertEqual(state.frameInterval(for: .standard), 0.14, accuracy: 0.001)
        XCTAssertEqual(state.frameInterval(for: .turbo), 0.14 / 1.5, accuracy: 0.001)
        XCTAssertEqual(
            PetVisualState(remainingPercent: 0).frameInterval(for: .standard),
            1.4,
            accuracy: 0.001
        )
    }

    @MainActor
    func testPetVisibilityTogglesWithoutStartingConnection() {
        let appState = AppState()

        XCTAssertTrue(appState.isPetVisible)
        appState.togglePetVisibility()
        XCTAssertFalse(appState.isPetVisible)
        appState.togglePetVisibility()
        XCTAssertTrue(appState.isPetVisible)
    }

    @MainActor
    func testPetSizeDefaultsPersistsAndClearsAbsorption() throws {
        let suiteName = "BlackHoleQuotaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(defaults: defaults)
        XCTAssertEqual(appState.petSize, .large)

        let resetID = appState.absorptionResetID
        appState.setPetSize(.small)
        XCTAssertEqual(appState.petSize, .small)
        XCTAssertEqual(appState.absorptionResetID, resetID + 1)
        XCTAssertEqual(AppState(defaults: defaults).petSize, .small)

        defaults.set("invalid", forKey: AppConstants.petSizeKey)
        XCTAssertEqual(AppState(defaults: defaults).petSize, .large)
    }

    @MainActor
    func testAbsorptionCategoryWeightsPersistAndProtectLastActiveCategory() throws {
        let suiteName = "BlackHoleQuotaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let catalog = try AbsorbableObjectCatalog(bundle: Bundle(for: AppDelegate.self))

        var appState = AppState(defaults: defaults, absorptionCatalog: catalog)
        XCTAssertEqual(appState.absorptionCategoryWeights, [
            "space": 2,
            "animals": 2,
            "characters": 1
        ])
        XCTAssertEqual(appState.absorptionCategoryWeightsSummary, "2:2:1")

        let absorptionResetID = appState.absorptionResetID
        appState.setAbsorptionCategoryWeight(3, for: "space")
        appState.setAbsorptionCategoryWeight(0, for: "animals")
        appState.setAbsorptionCategoryWeight(0, for: "characters")
        XCTAssertEqual(appState.absorptionCategoryWeightsSummary, "3:0:0")
        XCTAssertEqual(appState.absorptionResetID, absorptionResetID)
        XCTAssertFalse(appState.canSetAbsorptionCategoryWeight(0, for: "space"))
        XCTAssertEqual(
            defaults.dictionary(forKey: AppConstants.absorptionCategoryWeightsKey)?["space"]
                as? Int,
            3
        )

        appState.setAbsorptionCategoryWeight(0, for: "space")
        appState.setAbsorptionCategoryWeight(4, for: "space")
        appState.setAbsorptionCategoryWeight(1, for: "unknown")
        XCTAssertEqual(appState.absorptionCategoryWeightsSummary, "3:0:0")

        appState = AppState(defaults: defaults, absorptionCatalog: catalog)
        XCTAssertEqual(appState.absorptionCategoryWeightsSummary, "3:0:0")
    }

    @MainActor
    func testPixelObjectMixMatrixReflectsCurrentAndLastActiveCells() throws {
        let suiteName = "BlackHoleQuotaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(defaults: defaults)

        appState.setAbsorptionCategoryWeight(3, for: "space")
        appState.setAbsorptionCategoryWeight(0, for: "animals")
        appState.setAbsorptionCategoryWeight(0, for: "characters")

        XCTAssertEqual(
            appState.absorptionCategories.prefix(PixelContextMenuView.matrixCategoryCount).map(\.id),
            ["space", "animals", "characters"]
        )
        for category in appState.absorptionCategories {
            let currentWeight = appState.absorptionCategoryWeights[category.id, default: 0]
            let cells = PixelContextMenuView.matrixWeights.map { weight in
                PixelObjectMixCellPresentation(
                    weight: weight,
                    currentWeight: currentWeight,
                    isEnabled: appState.canSetAbsorptionCategoryWeight(
                        weight,
                        for: category.id
                    )
                )
            }
            XCTAssertEqual(cells.filter(\.isSelected).count, 1)
            XCTAssertFalse(cells[currentWeight].acceptsAction)
        }

        let lastActiveZero = PixelObjectMixCellPresentation(
            weight: 0,
            currentWeight: 3,
            isEnabled: appState.canSetAbsorptionCategoryWeight(0, for: "space")
        )
        XCTAssertFalse(lastActiveZero.isEnabled)
        XCTAssertFalse(lastActiveZero.acceptsAction)

        let inactiveCurrentZero = PixelObjectMixCellPresentation(
            weight: 0,
            currentWeight: 0,
            isEnabled: appState.canSetAbsorptionCategoryWeight(0, for: "animals")
        )
        XCTAssertTrue(inactiveCurrentZero.isSelected)
        XCTAssertTrue(inactiveCurrentZero.isEnabled)
        XCTAssertFalse(inactiveCurrentZero.acceptsAction)

        appState.setAbsorptionCategoryWeight(1, for: "animals")
        XCTAssertTrue(appState.canSetAbsorptionCategoryWeight(0, for: "space"))
    }

    @MainActor
    func testAbsorptionCategoryWeightsResolveStoredSchemaChangesAndInvalidValues() throws {
        let suiteName = "BlackHoleQuotaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let catalog = try AbsorbableObjectCatalog(bundle: Bundle(for: AppDelegate.self))
        let expectedDefaults = ["space": 2, "animals": 2, "characters": 1]

        defaults.set(
            ["space": 3, "future-category": "ignored"],
            forKey: AppConstants.absorptionCategoryWeightsKey
        )
        XCTAssertEqual(
            AppState(defaults: defaults, absorptionCatalog: catalog).absorptionCategoryWeights,
            ["space": 3, "animals": 2, "characters": 1]
        )

        let invalidKnownValues: [Any] = [true, "2", 1.5, 2.0, -1, 4, Data([1])]
        for value in invalidKnownValues {
            defaults.set(
                ["space": value, "animals": 2, "characters": 1],
                forKey: AppConstants.absorptionCategoryWeightsKey
            )
            XCTAssertEqual(
                AppState(
                    defaults: defaults,
                    absorptionCatalog: catalog
                ).absorptionCategoryWeights,
                expectedDefaults,
                "Accepted invalid known value \(value)"
            )
        }

        defaults.set(
            ["space": 0, "animals": 0, "characters": 0],
            forKey: AppConstants.absorptionCategoryWeightsKey
        )
        XCTAssertEqual(
            AppState(defaults: defaults, absorptionCatalog: catalog).absorptionCategoryWeights,
            expectedDefaults
        )
        defaults.set(["malformed"], forKey: AppConstants.absorptionCategoryWeightsKey)
        XCTAssertEqual(
            AppState(defaults: defaults, absorptionCatalog: catalog).absorptionCategoryWeights,
            expectedDefaults
        )

        let changedCatalog = try makeAbsorbableObjectCatalog(
            categories: [("space", 2), ("new-category", 3)],
            objects: [("space-object", "space"), ("new-object", "new-category")]
        )
        defaults.set(
            ["space": 1, "removed-category": false],
            forKey: AppConstants.absorptionCategoryWeightsKey
        )
        let migrated = AppState(defaults: defaults, absorptionCatalog: changedCatalog)
        XCTAssertEqual(
            migrated.absorptionCategoryWeights,
            ["space": 1, "new-category": 3]
        )
        XCTAssertEqual(migrated.absorptionCategoryWeightsSummary, "1:3")
    }

    @MainActor
    func testTooltipStyleDefaultsPersistsAndFallsBackFromInvalidValue() throws {
        let suiteName = "BlackHoleQuotaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(defaults: defaults)
        XCTAssertEqual(appState.tooltipStyle, .smooth)

        appState.setTooltipStyle(.pixel)
        XCTAssertEqual(appState.tooltipStyle, .pixel)
        XCTAssertEqual(defaults.string(forKey: AppConstants.tooltipStyleKey), "pixel")
        XCTAssertEqual(AppState(defaults: defaults).tooltipStyle, .pixel)

        defaults.set("future-invalid-style", forKey: AppConstants.tooltipStyleKey)
        XCTAssertEqual(AppState(defaults: defaults).tooltipStyle, .smooth)
    }

    @MainActor
    func testOpenTooltipSwitchesStyleInPlaceWithoutQuotaTraffic() throws {
        let suiteName = "BlackHoleQuotaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appServer = FakeAppServer()
        let appState = AppState(defaults: defaults, appServer: appServer)
        let controller = PetPanelController()
        controller.show(appState: appState)
        let hostingViewIdentity = try XCTUnwrap(controller.tooltipHostingViewIdentity)
        XCTAssertFalse(controller.isTooltipPresentationActive)
        controller.setTooltipVisible(true)
        XCTAssertTrue(controller.isTooltipPresentationActive)

        let petFrame = try XCTUnwrap(controller.petFrame)
        XCTAssertEqual(
            controller.tooltipFrame?.size,
            QuotaTooltipView.panelSize(for: .large, showsHistory: true)
        )

        appState.setTooltipStyle(.pixel)
        controller.updateTooltipStyle()

        XCTAssertTrue(controller.isTooltipVisible)
        XCTAssertTrue(controller.isTooltipPresentationActive)
        XCTAssertEqual(controller.tooltipHostingViewIdentity, hostingViewIdentity)
        XCTAssertEqual(
            controller.tooltipFrame?.size,
            QuotaTooltipView.panelSize(
                for: .large,
                style: .pixel,
                showsHistory: true
            )
        )
        XCTAssertEqual(controller.petFrame, petFrame)
        XCTAssertEqual(appServer.rateLimitRefreshCount, 0)
        controller.setTooltipVisible(false)
        XCTAssertFalse(controller.isTooltipPresentationActive)
        XCTAssertEqual(controller.tooltipHostingViewIdentity, hostingViewIdentity)
        controller.hide()
    }

    @MainActor
    func testPixelTooltipDisablesWindowAnimationWithoutChangingSmooth() throws {
        let suiteName = "BlackHoleQuotaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(defaults: defaults)
        let controller = PetPanelController()
        controller.show(appState: appState)

        XCTAssertEqual(controller.tooltipAnimationBehavior, .default)
        appState.setTooltipStyle(.pixel)
        controller.updateTooltipStyle()
        XCTAssertEqual(controller.tooltipAnimationBehavior, NSWindow.AnimationBehavior.none)
        controller.hide()
    }

    @MainActor
    func testTooltipLayoutPreservesPreferredSideWhenNewStyleFits() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)
        let petFrame = CGRect(x: 600, y: 390, width: 400, height: 220)
        let layout = PetPanelController.tooltipLayout(
            petFrame: petFrame,
            visibleFrame: visibleFrame,
            tooltipStyle: .pixel,
            preferredPlacement: .left
        )

        XCTAssertEqual(layout.placement, .left)
        XCTAssertEqual(layout.size, PixelQuotaTooltipView.largePanelSize)
        XCTAssertTrue(visibleFrame.contains(CGRect(origin: layout.origin, size: layout.size)))
    }

    func testSmallAbsorptionSpawnPointsKeepObjectsInsideScene() {
        let object = AbsorbableObjectManifest.Object(
            id: "test",
            category: "space",
            asset: "test"
        )
        let startDate = Date(timeIntervalSince1970: 3_000)
        let inset: CGFloat = 24

        for (index, side) in AbsorptionSpawnSide.allCases.enumerated() {
            let plan = AbsorptionPlan(
                object: object,
                startDate: startDate,
                duration: 1,
                side: side,
                seed: UInt64(index),
                usesReducedMotion: false
            )
            let state = AbsorptionVisualState.make(
                plan: plan,
                at: startDate,
                sceneSize: PetSize.small.sceneSize
            )
            XCTAssertGreaterThanOrEqual(state.position.x, inset)
            XCTAssertLessThanOrEqual(
                state.position.x,
                PetSize.small.sceneSize.width - inset
            )
            XCTAssertGreaterThanOrEqual(state.position.y, inset)
            XCTAssertLessThanOrEqual(
                state.position.y,
                PetSize.small.sceneSize.height - inset
            )
        }
    }

    @MainActor
    func testPanelHidesAndRestores() throws {
        let suiteName = "BlackHoleQuotaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(defaults: defaults)
        let controller = PetPanelController()

        controller.show(appState: appState)
        XCTAssertTrue(controller.isVisible)
        controller.setTooltipVisible(true)
        XCTAssertTrue(controller.isTooltipVisible)

        controller.hide()
        XCTAssertFalse(controller.isVisible)
        XCTAssertFalse(controller.isTooltipVisible)

        controller.show(appState: appState)
        XCTAssertTrue(controller.isVisible)
        controller.hide()
    }

    @MainActor
    func testResetCountdownUpdatesOnlyWhileTooltipIsVisible() async throws {
        let suiteName = "BlackHoleQuotaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appServer = FakeAppServer()
        let appState = AppState(
            defaults: defaults,
            appServer: appServer,
            historyStore: QuotaHistoryStore(fileURL: nil)
        )
        let controller = PetPanelController()
        appState.start()
        appServer.send(
            snapshot: Self.snapshot(
                remainingPercent: 80,
                resetsAt: Int64(Date().addingTimeInterval(30 * 60).timeIntervalSince1970)
            )
        )
        await Self.waitUntil { appState.quota?.primary?.resetDate != nil }

        controller.show(appState: appState)
        let refreshCount = appServer.rateLimitRefreshCount
        controller.setTooltipVisible(true)
        XCTAssertTrue(controller.isResetCountdownUpdateActive)
        XCTAssertEqual(appServer.rateLimitRefreshCount, refreshCount)

        controller.setTooltipVisible(false)
        XCTAssertFalse(controller.isResetCountdownUpdateActive)

        controller.setTooltipVisible(true)
        let petFrame = try XCTUnwrap(controller.petFrame)
        controller.showContextMenu(at: CGPoint(x: petFrame.midX, y: petFrame.midY))
        XCTAssertFalse(controller.isResetCountdownUpdateActive)
        XCTAssertEqual(appServer.rateLimitRefreshCount, refreshCount)

        controller.hide()
        appState.stop()
    }

    @MainActor
    func testPanelUsesAndAppliesSelectedPetSize() throws {
        let suiteName = "BlackHoleQuotaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(defaults: defaults)
        appState.setPetSize(.medium)
        let controller = PetPanelController()
        controller.show(appState: appState)
        XCTAssertEqual(controller.petFrame?.size, PetSize.medium.sceneSize)

        let originalCenter = controller.petFrame.map {
            CGPoint(x: $0.midX, y: $0.midY)
        }
        appState.setPetSize(.small)
        controller.resize(to: .small)
        XCTAssertEqual(controller.petFrame?.size, PetSize.small.sceneSize)
        XCTAssertEqual(
            controller.petFrame.map { CGPoint(x: $0.midX, y: $0.midY) },
            originalCenter
        )
        controller.hide()
    }

    @MainActor
    func testContextMenuPanelSuppressesTooltipAndHidesWithPet() throws {
        let suiteName = "BlackHoleQuotaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(defaults: defaults)
        let controller = PetPanelController()
        controller.show(appState: appState)
        controller.setTooltipVisible(true)
        XCTAssertTrue(controller.isTooltipVisible)

        let petFrame = try XCTUnwrap(controller.petFrame)
        controller.showContextMenu(
            at: CGPoint(x: petFrame.midX, y: petFrame.midY)
        )

        XCTAssertTrue(controller.isContextMenuVisible)
        XCTAssertFalse(controller.isTooltipVisible)
        XCTAssertEqual(controller.contextMenuFrame?.size, PixelContextMenuView.panelSize)

        controller.hide()
        XCTAssertFalse(controller.isContextMenuVisible)
        XCTAssertFalse(controller.isVisible)
    }

    @MainActor
    func testContextMenuSettingTogglesKeepPanelOpen() throws {
        let suiteName = "BlackHoleQuotaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let loginService = FakeLaunchAtLoginService()
        let appState = AppState(
            defaults: defaults,
            launchAtLoginStatusProvider: { loginService.status },
            updateLaunchAtLogin: loginService.setEnabled
        )
        let controller = PetPanelController(
            isFrontmostApplicationFullScreen: { false }
        )
        controller.show(appState: appState)
        let petFrame = try XCTUnwrap(controller.petFrame)
        controller.showContextMenu(
            at: CGPoint(x: petFrame.midX, y: petFrame.midY)
        )
        let actions = controller.contextMenuActions(appState: appState)

        actions.setHidesInFullScreenApps(true)
        XCTAssertTrue(appState.hidesInFullScreenApps)
        XCTAssertTrue(controller.isContextMenuVisible)

        actions.setLaunchesAtLogin(true)
        XCTAssertTrue(appState.launchesAtLogin)
        XCTAssertTrue(controller.isContextMenuVisible)

        controller.hide()
    }

    @MainActor
    func testContextMenuObjectMixActionPersistsLiveRatioAndKeepsPanelOpen() throws {
        let suiteName = "BlackHoleQuotaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(defaults: defaults)
        let controller = PetPanelController()
        controller.show(appState: appState)
        let petFrame = try XCTUnwrap(controller.petFrame)
        controller.showContextMenu(at: CGPoint(x: petFrame.midX, y: petFrame.midY))
        let actions = controller.contextMenuActions(appState: appState)
        let absorptionResetID = appState.absorptionResetID

        actions.setAbsorptionCategoryWeight("characters", 0)
        XCTAssertEqual(appState.absorptionCategoryWeightsSummary, "2:2:0")
        XCTAssertEqual(
            defaults.dictionary(forKey: AppConstants.absorptionCategoryWeightsKey)?[
                "characters"
            ] as? Int,
            0
        )
        XCTAssertEqual(appState.absorptionResetID, absorptionResetID)
        XCTAssertTrue(controller.isContextMenuVisible)

        actions.setAbsorptionCategoryWeight("animals", 0)
        actions.setAbsorptionCategoryWeight("space", 0)
        XCTAssertEqual(appState.absorptionCategoryWeightsSummary, "2:0:0")
        XCTAssertTrue(controller.isContextMenuVisible)

        controller.hide()
    }

    @MainActor
    func testContextMenuTooltipStyleActionUpdatesPreferenceWithoutQuotaTraffic() throws {
        let suiteName = "BlackHoleQuotaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appServer = FakeAppServer()
        let appState = AppState(defaults: defaults, appServer: appServer)
        let controller = PetPanelController()
        controller.show(appState: appState)

        controller.contextMenuActions(appState: appState).setTooltipStyle(.pixel)

        XCTAssertEqual(appState.tooltipStyle, .pixel)
        XCTAssertEqual(defaults.string(forKey: AppConstants.tooltipStyleKey), "pixel")
        XCTAssertEqual(appServer.rateLimitRefreshCount, 0)
        controller.hide()
    }

    @MainActor
    func testFullScreenPreferencePersists() throws {
        let suiteName = "BlackHoleQuotaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(defaults: defaults)
        XCTAssertFalse(appState.hidesInFullScreenApps)

        appState.setHidesInFullScreenApps(true)
        XCTAssertTrue(appState.hidesInFullScreenApps)
        XCTAssertTrue(AppState(defaults: defaults).hidesInFullScreenApps)
    }

    @MainActor
    func testFullScreenSuppressionDoesNotOverrideManualVisibility() throws {
        let suiteName = "BlackHoleQuotaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var isFullScreen = false
        let appState = AppState(defaults: defaults)
        let controller = PetPanelController(
            isFrontmostApplicationFullScreen: { isFullScreen }
        )

        controller.updateVisibility(appState: appState)
        XCTAssertTrue(controller.isVisible)

        isFullScreen = true
        controller.updateVisibility(appState: appState)
        XCTAssertTrue(controller.isVisible)
        appState.previewQuotaConsumptionReaction(kind: .small, remainingPercent: 50)
        controller.updateVisibility(appState: appState)
        XCTAssertNotNil(appState.activeQuotaConsumptionReaction)

        appState.setHidesInFullScreenApps(true)
        controller.updateVisibility(appState: appState)
        XCTAssertFalse(controller.isVisible)
        XCTAssertNil(appState.activeQuotaConsumptionReaction)

        appState.togglePetVisibility()
        isFullScreen = false
        controller.updateVisibility(appState: appState)
        XCTAssertFalse(controller.isVisible)

        appState.togglePetVisibility()
        controller.updateVisibility(appState: appState)
        XCTAssertTrue(controller.isVisible)
        controller.hide()
    }

    @MainActor
    func testLaunchAtLoginUsesSystemStatusAndAction() {
        let service = FakeLaunchAtLoginService()
        let appState = AppState(
            launchAtLoginStatusProvider: { service.status },
            updateLaunchAtLogin: service.setEnabled
        )

        XCTAssertFalse(appState.launchesAtLogin)

        appState.setLaunchesAtLogin(true)
        XCTAssertTrue(appState.launchesAtLogin)
        XCTAssertNil(appState.launchAtLoginError)

        appState.setLaunchesAtLogin(false)
        XCTAssertFalse(appState.launchesAtLogin)

        service.status = .requiresApproval
        appState.refreshLaunchAtLoginStatus()
        XCTAssertTrue(appState.launchesAtLogin)
    }

    @MainActor
    func testLaunchAtLoginKeepsActualStatusAfterFailure() {
        let service = FakeLaunchAtLoginService()
        service.error = .denied
        let appState = AppState(
            launchAtLoginStatusProvider: { service.status },
            updateLaunchAtLogin: service.setEnabled
        )

        appState.setLaunchesAtLogin(true)

        XCTAssertFalse(appState.launchesAtLogin)
        XCTAssertEqual(appState.launchAtLoginError, "Login item denied")
    }

    @MainActor
    func testFailureSchedulesReconnectAndRetryNowReconnectsImmediately() async {
        let appServer = FakeAppServer()
        let appState = AppState(
            appServer: appServer,
            retryDelays: [60],
            historyStore: QuotaHistoryStore(fileURL: nil)
        )

        appState.start()
        XCTAssertEqual(appServer.startCount, 1)
        XCTAssertEqual(appState.connectionState, .connecting)

        appServer.fail(with: "Connection lost")
        await Self.waitUntil { appState.connectionState == .reconnecting }
        XCTAssertEqual(appState.connectionState, .reconnecting)
        XCTAssertEqual(appState.errorMessage, "Connection lost")

        appState.retryNow()
        XCTAssertEqual(appServer.startCount, 2)
        XCTAssertEqual(appState.connectionState, .connecting)

        appServer.send(snapshot: Self.snapshot(remainingPercent: 80))
        await Self.waitUntil { appState.connectionState == .connected }
        XCTAssertEqual(appState.quota?.primary?.remainingPercent, 80)
        XCTAssertEqual(appState.connectionState, .connected)
        XCTAssertNil(appState.errorMessage)

        appState.stop()
    }

    @MainActor
    func testAutomaticReconnectUsesSingleActiveAttempt() async {
        let appServer = FakeAppServer()
        let appState = AppState(
            appServer: appServer,
            retryDelays: [0],
            historyStore: QuotaHistoryStore(fileURL: nil)
        )

        appState.start()
        appServer.fail(with: "Connection lost")
        appServer.fail(with: "Duplicate failure")
        await Self.waitUntil { appServer.startCount == 2 }

        XCTAssertEqual(appServer.startCount, 2)
        XCTAssertEqual(appState.connectionState, .reconnecting)
        appState.stop()
    }

    @MainActor
    func testQuotaConsumptionLifecycleSignalsCancelAndSuppressPresentation() async throws {
        let server = FakeAppServer()
        var now = Date(timeIntervalSince1970: 80_000)
        let reset = Int64(now.addingTimeInterval(10_000).timeIntervalSince1970)
        let suiteName = "QuotaConsumptionLifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(
            defaults: defaults,
            appServer: server,
            retryDelays: [60],
            now: { now },
            historyStore: QuotaHistoryStore(fileURL: nil)
        )
        appState.start()
        appState.setQuotaConsumptionPanelPresented(true)

        func send(_ remaining: Int) async {
            now.addTimeInterval(1)
            server.send(snapshot: Self.snapshot(remainingPercent: remaining, resetsAt: reset))
            await Self.waitUntil { appState.quota?.primary?.remainingPercent == remaining }
        }

        await send(80)
        await send(79)
        XCTAssertNotNil(appState.activeQuotaConsumptionReaction)
        let unaffectedEventID = appState.activeQuotaConsumptionReaction?.id
        appState.setTooltipStyle(.pixel)
        appState.setShowsQuotaDynamics(false)
        appState.setPetPositionLocked(true)
        appState.setPassesPointerInputThrough(true)
        appState.clearQuotaHistory()
        server.send(speedMode: .turbo)
        await Self.waitUntil { appState.speedMode == .turbo }
        XCTAssertEqual(appState.activeQuotaConsumptionReaction?.id, unaffectedEventID)

        appState.setQuotaConsumptionDragging(true)
        XCTAssertNil(appState.activeQuotaConsumptionReaction)
        await send(78)
        XCTAssertNil(appState.activeQuotaConsumptionReaction)
        appState.setQuotaConsumptionDragging(false)
        await send(77)
        XCTAssertNotNil(appState.activeQuotaConsumptionReaction)

        appState.setQuotaConsumptionResizing(true)
        XCTAssertNil(appState.activeQuotaConsumptionReaction)
        appState.setQuotaConsumptionResizing(false)
        await send(76)
        XCTAssertNotNil(appState.activeQuotaConsumptionReaction)

        appState.setQuotaConsumptionContextMenuPresented(true)
        XCTAssertNil(appState.activeQuotaConsumptionReaction)
        await send(75)
        XCTAssertNil(appState.activeQuotaConsumptionReaction)
        appState.setQuotaConsumptionContextMenuPresented(false)
        await send(74)
        XCTAssertNotNil(appState.activeQuotaConsumptionReaction)

        appState.setQuotaConsumptionFullScreenSuppressed(true)
        XCTAssertNil(appState.activeQuotaConsumptionReaction)
        appState.setQuotaConsumptionFullScreenSuppressed(false)
        await send(73)
        XCTAssertNotNil(appState.activeQuotaConsumptionReaction)

        appState.quotaConsumptionAbsorptionDidStart()
        XCTAssertNil(appState.activeQuotaConsumptionReaction)
        await send(72)
        XCTAssertNil(appState.activeQuotaConsumptionReaction)
        appState.quotaConsumptionAbsorptionDidStart()
        appState.quotaConsumptionAbsorptionDidStart()
        appState.quotaConsumptionAbsorptionDidFinish()
        await send(71)
        XCTAssertNil(appState.activeQuotaConsumptionReaction)
        appState.quotaConsumptionAbsorptionDidFinish()
        await send(70)
        XCTAssertNil(appState.activeQuotaConsumptionReaction)
        appState.quotaConsumptionAbsorptionDidFinish()
        await send(69)
        XCTAssertNotNil(appState.activeQuotaConsumptionReaction)

        appState.setQuotaConsumptionReduceMotion(true)
        XCTAssertNil(appState.activeQuotaConsumptionReaction)
        appState.setQuotaConsumptionReduceMotion(false)
        await send(68)
        XCTAssertNotNil(appState.activeQuotaConsumptionReaction)

        appState.setPetSize(.small)
        XCTAssertNil(appState.activeQuotaConsumptionReaction)
        await send(67)
        XCTAssertNotNil(appState.activeQuotaConsumptionReaction)

        appState.setQuotaConsumptionPanelPresented(false)
        XCTAssertNil(appState.activeQuotaConsumptionReaction)
        await send(66)
        XCTAssertNil(appState.activeQuotaConsumptionReaction)
        appState.setQuotaConsumptionPanelPresented(true)
        await send(65)
        XCTAssertNotNil(appState.activeQuotaConsumptionReaction)

        appState.togglePetVisibility()
        XCTAssertNil(appState.activeQuotaConsumptionReaction)
        await send(64)
        XCTAssertNil(appState.activeQuotaConsumptionReaction)
        appState.togglePetVisibility()
        await send(63)
        XCTAssertNotNil(appState.activeQuotaConsumptionReaction)

        server.fail(with: "Disconnected")
        await Self.waitUntil { appState.connectionState == .reconnecting }
        XCTAssertNil(appState.activeQuotaConsumptionReaction)
        XCTAssertEqual(appState.quotaConsumptionReaction.cadencePosition, 0)
        appState.stop()
    }

    func testReconnectBackoffIsBounded() {
        XCTAssertEqual(AppState.reconnectDelays, [1, 2, 5, 10, 30])
    }

    @MainActor
    func testQuotaRefreshesOnlyAfterSnapshotBecomesStale() async {
        let appServer = FakeAppServer()
        var now = Date(timeIntervalSince1970: 1_000)
        let appState = AppState(
            appServer: appServer,
            now: { now },
            historyStore: QuotaHistoryStore(fileURL: nil)
        )

        appState.start()
        appState.refreshQuotaIfStale(maxAge: 0)
        XCTAssertEqual(appServer.rateLimitRefreshCount, 0)

        appServer.send(snapshot: Self.snapshot(remainingPercent: 90))
        await Self.waitUntil { appState.connectionState == .connected }

        appState.refreshQuotaIfStale()
        XCTAssertEqual(appServer.rateLimitRefreshCount, 0)

        appState.refreshQuotaIfStale(maxAge: 0)
        XCTAssertEqual(appServer.rateLimitRefreshCount, 1)
        appServer.send(snapshot: Self.snapshot(remainingPercent: 90))
        await Self.waitUntil { appState.quota?.primary?.remainingPercent == 90 }

        now.addTimeInterval(AppState.quotaRefreshMaxAge)
        appState.refreshQuotaIfStale()
        XCTAssertEqual(appServer.rateLimitRefreshCount, 2)

        appServer.send(snapshot: Self.snapshot(remainingPercent: 89))
        await Self.waitUntil { appState.quota?.primary?.remainingPercent == 89 }
        appState.refreshQuotaIfStale()
        XCTAssertEqual(appServer.rateLimitRefreshCount, 2)

        appState.stop()
    }

    func testPassiveQuotaPollingUsesOneMinuteInterval() {
        XCTAssertEqual(CodexAppServer.rateLimitRefreshInterval, 60)
    }

    private static func snapshot(
        remainingPercent: Int,
        resetsAt: Int64? = nil
    ) -> QuotaSnapshot {
        QuotaSnapshot(
            limitId: "codex",
            limitName: nil,
            planType: "pro",
            primary: QuotaWindow(
                usedPercent: 100 - remainingPercent,
                windowDurationMins: nil,
                resetsAt: resetsAt
            ),
            secondary: nil
        )
    }

    @MainActor
    private static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
    }
}

final class QuotaTransitionClassifierTests: XCTestCase {
    func testConsumptionCadenceAndMergedPendingState() {
        var state = QuotaConsumptionReactionState()
        state.acceptConsumption(
            delta: 1,
            remainingPercent: 79,
            isLastLight: false,
            isPresentationEligible: true,
            reduceMotion: false
        )
        let active = state.active
        XCTAssertEqual(active?.kind, .small)
        XCTAssertEqual(state.cadencePosition, 1)

        state.acceptConsumption(
            delta: 4,
            remainingPercent: 75,
            isLastLight: false,
            isPresentationEligible: true,
            reduceMotion: false
        )
        XCTAssertEqual(state.active, active)
        XCTAssertEqual(state.pending?.kind, .medium)

        state.acceptConsumption(
            delta: 5,
            remainingPercent: 70,
            isLastLight: false,
            isPresentationEligible: true,
            reduceMotion: false
        )
        XCTAssertEqual(state.active, active)
        XCTAssertEqual(state.pending?.kind, .large)
        XCTAssertEqual(state.pending?.bucket, 70)
        XCTAssertEqual(state.cadencePosition, 10)

        state.complete(eventID: active!.id)
        XCTAssertEqual(state.active?.kind, .large)
        XCTAssertNil(state.pending)
        state.cancelPresentation()
        XCTAssertNil(state.active)
        XCTAssertEqual(state.cadencePosition, 10)
        state.complete(eventID: active!.id)
        XCTAssertNil(state.active)
        XCTAssertNil(state.pending)

        state.acceptConsumption(
            delta: 4,
            remainingPercent: 66,
            isLastLight: false,
            isPresentationEligible: false,
            reduceMotion: false
        )
        XCTAssertNil(state.active)
        XCTAssertEqual(state.cadencePosition, 14)
        state.acceptConsumption(
            delta: 1,
            remainingPercent: 65,
            isLastLight: false,
            isPresentationEligible: true,
            reduceMotion: false
        )
        XCTAssertEqual(state.active?.kind, .medium)
    }

    func testLastLightAndContinuityResetContracts() {
        var state = QuotaConsumptionReactionState()
        state.acceptConsumption(
            delta: 3,
            remainingPercent: 10,
            isLastLight: true,
            isPresentationEligible: true,
            reduceMotion: false
        )
        XCTAssertEqual(state.active?.kind, .lastLight)
        XCTAssertEqual(state.active?.bucket, 10)
        state.resetContinuity()
        XCTAssertEqual(state.cadencePosition, 0)
        XCTAssertNil(state.active)
        XCTAssertNil(state.pending)

        state.acceptConsumption(
            delta: 1,
            remainingPercent: 0,
            isLastLight: true,
            isPresentationEligible: true,
            reduceMotion: true
        )
        XCTAssertEqual(state.cadencePosition, 1)
        XCTAssertNil(state.active)
    }

    func testSharedTransitionClassifierSeparatesConsumptionFromUnsafeChanges() {
        let start = Date(timeIntervalSince1970: 10_000)
        let reset = Int64(start.addingTimeInterval(3_600).timeIntervalSince1970)
        let previous = Self.sample(
            remainingPercent: 80,
            observedAt: start,
            resetsAt: reset
        )

        XCTAssertEqual(
            Self.transition(
                from: previous,
                to: Self.sample(
                    remainingPercent: 80,
                    observedAt: start.addingTimeInterval(1),
                    resetsAt: reset
                )
            ),
            .duplicate
        )
        XCTAssertEqual(
            Self.transition(
                from: previous,
                to: Self.sample(
                    remainingPercent: 77,
                    observedAt: start.addingTimeInterval(1),
                    resetsAt: reset
                )
            ),
            .consumption(delta: 3)
        )
        XCTAssertEqual(
            Self.transition(
                from: previous,
                to: Self.sample(
                    remainingPercent: 81,
                    observedAt: start.addingTimeInterval(1),
                    resetsAt: reset
                )
            ),
            .correction
        )

        let resetPrevious = Self.sample(
            remainingPercent: 20,
            observedAt: start,
            resetsAt: Int64(start.addingTimeInterval(30).timeIntervalSince1970)
        )
        XCTAssertEqual(
            Self.transition(
                from: resetPrevious,
                to: Self.sample(
                    remainingPercent: 100,
                    observedAt: start.addingTimeInterval(60),
                    resetsAt: Int64(start.addingTimeInterval(3_660).timeIntervalSince1970)
                )
            ),
            .reset
        )

        let discontinuities = [
            Self.sample(
                remainingPercent: 79,
                observedAt: start.addingTimeInterval(1),
                resetsAt: nil
            ),
            Self.sample(
                remainingPercent: 79,
                observedAt: start.addingTimeInterval(1),
                resetsAt: reset,
                duration: 60
            ),
            Self.sample(
                remainingPercent: 79,
                observedAt: start.addingTimeInterval(1),
                resetsAt: reset,
                limitId: "other"
            ),
            Self.sample(
                remainingPercent: 79,
                observedAt: start.addingTimeInterval(1),
                resetsAt: reset,
                limitName: "Codex Team"
            ),
            Self.sample(
                remainingPercent: 79,
                observedAt: start.addingTimeInterval(1),
                resetsAt: reset,
                planType: "team"
            ),
            Self.sample(
                remainingPercent: nil,
                observedAt: start.addingTimeInterval(1),
                resetsAt: reset
            ),
            Self.sample(
                remainingPercent: 80,
                observedAt: start.addingTimeInterval(
                    QuotaHistoryClassifier.maximumComparableGap + 1
                ),
                resetsAt: reset
            ),
            Self.sample(
                remainingPercent: 79,
                observedAt: start,
                resetsAt: reset
            )
        ]
        for current in discontinuities {
            XCTAssertEqual(Self.transition(from: previous, to: current), .discontinuity)
        }
        XCTAssertEqual(
            Self.transition(
                from: previous,
                to: Self.sample(
                    remainingPercent: 79,
                    observedAt: start.addingTimeInterval(1),
                    resetsAt: reset
                ),
                forceGap: true
            ),
            .discontinuity
        )

        let nilDurationPrevious = Self.sample(
            remainingPercent: 80,
            observedAt: start,
            resetsAt: reset,
            duration: nil
        )
        XCTAssertEqual(
            Self.transition(
                from: nilDurationPrevious,
                to: Self.sample(
                    remainingPercent: 79,
                    observedAt: start.addingTimeInterval(1),
                    resetsAt: reset,
                    duration: nil
                )
            ),
            .consumption(delta: 1)
        )
    }

    func testResetClassifierRequiresExactCredibleBoundaryForAnyDelta() {
        let start = Date(timeIntervalSince1970: 40_000)
        let oldReset = Int64(start.addingTimeInterval(30).timeIntervalSince1970)
        let newReset = oldReset + 18_000
        let previous = Self.sample(
            remainingPercent: 20,
            observedAt: start,
            resetsAt: oldReset
        )

        for source in 0...99 {
            XCTAssertEqual(
                Self.transition(
                    from: Self.sample(
                        remainingPercent: source,
                        observedAt: start,
                        resetsAt: oldReset
                    ),
                    to: Self.sample(
                        remainingPercent: 100,
                        observedAt: start.addingTimeInterval(30),
                        resetsAt: newReset
                    )
                ),
                .reset
            )
        }

        for remainingPercent in [100, 20, 7] {
            XCTAssertEqual(
                Self.transition(
                    from: previous,
                    to: Self.sample(
                        remainingPercent: remainingPercent,
                        observedAt: start.addingTimeInterval(30),
                        resetsAt: newReset
                    )
                ),
                .reset
            )
        }
        XCTAssertEqual(
            Self.transition(
                from: Self.sample(
                    remainingPercent: 43,
                    observedAt: start,
                    resetsAt: newReset
                ),
                to: Self.sample(
                    remainingPercent: 100,
                    observedAt: start.addingTimeInterval(1),
                    resetsAt: newReset
                )
            ),
            .correction
        )
        XCTAssertEqual(
            Self.transition(
                from: Self.sample(
                    remainingPercent: 100,
                    observedAt: start,
                    resetsAt: newReset
                ),
                to: Self.sample(
                    remainingPercent: 100,
                    observedAt: start.addingTimeInterval(1),
                    resetsAt: newReset
                )
            ),
            .duplicate
        )

        XCTAssertEqual(
            Self.transition(
                from: previous,
                to: Self.sample(
                    remainingPercent: 100,
                    observedAt: start.addingTimeInterval(29),
                    resetsAt: newReset
                )
            ),
            .discontinuity
        )
        XCTAssertEqual(
            Self.transition(
                from: Self.sample(
                    remainingPercent: 20,
                    observedAt: start,
                    resetsAt: Int64(start.timeIntervalSince1970)
                ),
                to: Self.sample(
                    remainingPercent: 100,
                    observedAt: start.addingTimeInterval(1),
                    resetsAt: newReset
                )
            ),
            .discontinuity
        )
        XCTAssertEqual(
            Self.transition(
                from: previous,
                to: Self.sample(
                    remainingPercent: 100,
                    observedAt: start.addingTimeInterval(30),
                    resetsAt: newReset,
                    duration: nil
                )
            ),
            .discontinuity
        )
        XCTAssertEqual(
            Self.transition(
                from: previous,
                to: Self.sample(
                    remainingPercent: 100,
                    observedAt: start.addingTimeInterval(30),
                    resetsAt: nil
                )
            ),
            .discontinuity
        )
    }

    private static func transition(
        from previous: QuotaHistorySample,
        to current: QuotaHistorySample,
        forceGap: Bool = false
    ) -> QuotaSnapshotTransition {
        QuotaHistoryClassifier.transition(
            previousSample: previous,
            currentSample: current,
            previousWindow: previous.primary,
            currentWindow: current.primary,
            forceGap: forceGap
        )
    }

    private static func sample(
        remainingPercent: Int?,
        observedAt: Date,
        resetsAt: Int64?,
        duration: Int64? = 300,
        limitId: String = "codex",
        limitName: String? = "Codex",
        planType: String? = "pro"
    ) -> QuotaHistorySample {
        QuotaHistorySample(
            snapshot: snapshot(
                remainingPercent: remainingPercent,
                resetsAt: resetsAt,
                duration: duration,
                limitId: limitId,
                limitName: limitName,
                planType: planType
            ),
            observedAt: observedAt
        )
    }

    private static func snapshot(
        remainingPercent: Int?,
        resetsAt: Int64?,
        duration: Int64? = 300,
        limitId: String = "codex",
        limitName: String? = "Codex",
        planType: String? = "pro"
    ) -> QuotaSnapshot {
        QuotaSnapshot(
            limitId: limitId,
            limitName: limitName,
            planType: planType,
            primary: remainingPercent.map {
                QuotaWindow(
                    usedPercent: 100 - $0,
                    windowDurationMins: duration,
                    resetsAt: resetsAt
                )
            },
            secondary: nil
        )
    }

}

final class PositionLockClickThroughTests: XCTestCase {
    @MainActor
    func testPreferencesAcceptOnlyStoredBooleansAndPersistIndependently() throws {
        let suiteName = "PositionLockClickThroughTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var appState = AppState(defaults: defaults)
        XCTAssertFalse(appState.isPetPositionLocked)
        XCTAssertFalse(appState.passesPointerInputThrough)

        appState.setPetPositionLocked(true)
        appState.setPassesPointerInputThrough(true)
        appState = AppState(defaults: defaults)
        XCTAssertTrue(appState.isPetPositionLocked)
        XCTAssertTrue(appState.passesPointerInputThrough)

        let invalidValues: [Any] = [0, 1, 2, "true", ["true"], Data([1])]
        for value in invalidValues {
            defaults.set(value, forKey: AppConstants.petPositionLockedKey)
            defaults.set(value, forKey: AppConstants.passesPointerInputThroughKey)
            appState = AppState(defaults: defaults)
            XCTAssertFalse(appState.isPetPositionLocked, "Accepted invalid \(value)")
            XCTAssertFalse(appState.passesPointerInputThrough, "Accepted invalid \(value)")
        }
    }

    @MainActor
    func testEffectiveInputPolicyCoversEveryPreferenceCombinationAndContextMenu() {
        XCTAssertEqual(
            PetPanelController.inputPolicy(
                isPositionLocked: false,
                passesPointerInputThrough: false,
                hasContextMenu: false
            ),
            PetPanelInputPolicy(allowsPointer: true, allowsDrag: true)
        )
        XCTAssertEqual(
            PetPanelController.inputPolicy(
                isPositionLocked: true,
                passesPointerInputThrough: false,
                hasContextMenu: false
            ),
            PetPanelInputPolicy(allowsPointer: true, allowsDrag: false)
        )
        XCTAssertEqual(
            PetPanelController.inputPolicy(
                isPositionLocked: false,
                passesPointerInputThrough: true,
                hasContextMenu: false
            ),
            PetPanelInputPolicy(allowsPointer: false, allowsDrag: false)
        )
        XCTAssertEqual(
            PetPanelController.inputPolicy(
                isPositionLocked: true,
                passesPointerInputThrough: true,
                hasContextMenu: false
            ),
            PetPanelInputPolicy(allowsPointer: false, allowsDrag: false)
        )
        XCTAssertEqual(
            PetPanelController.inputPolicy(
                isPositionLocked: false,
                passesPointerInputThrough: false,
                hasContextMenu: true
            ),
            PetPanelInputPolicy(allowsPointer: true, allowsDrag: false)
        )
        XCTAssertFalse(
            PetPanelController.shouldClearHoverRearm(
                passesPointerInputThrough: true,
                cursorIsInsideHoverTarget: false
            )
        )
        XCTAssertFalse(
            PetPanelController.shouldClearHoverRearm(
                passesPointerInputThrough: false,
                cursorIsInsideHoverTarget: true
            )
        )
        XCTAssertTrue(
            PetPanelController.shouldClearHoverRearm(
                passesPointerInputThrough: false,
                cursorIsInsideHoverTarget: false
            )
        )
        XCTAssertTrue(
            PetPanelController.hoverRearmRequired(
                currentlyRequired: true,
                passesPointerInputThrough: true,
                cursorIsInsideHoverTarget: false
            )
        )
        XCTAssertTrue(
            PetPanelController.hoverRearmRequired(
                currentlyRequired: true,
                passesPointerInputThrough: false,
                cursorIsInsideHoverTarget: true
            )
        )
        XCTAssertFalse(
            PetPanelController.hoverRearmRequired(
                currentlyRequired: true,
                passesPointerInputThrough: false,
                cursorIsInsideHoverTarget: false
            )
        )
    }

    @MainActor
    func testControllerAppliesLockClickThroughAndContextMenuRecovery() throws {
        let suiteName = "PositionLockClickThroughTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let frameName = "PositionLockClickThroughTests.\(UUID().uuidString)"
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(frameName)")
        }
        let appState = AppState(defaults: defaults)
        let controller = PetPanelController(frameName: frameName)
        controller.show(appState: appState)
        XCTAssertTrue(controller.isPanelMovableByWindowBackground)
        XCTAssertFalse(controller.isPanelIgnoringMouseEvents)

        appState.setPetPositionLocked(true)
        controller.positionLockDidChange()
        XCTAssertFalse(controller.isPanelMovableByWindowBackground)

        let frame = try XCTUnwrap(controller.petFrame)
        controller.showContextMenu(at: CGPoint(x: frame.midX, y: frame.midY))
        XCTAssertTrue(controller.isContextMenuVisible)
        controller.contextMenuActions(appState: appState).setPetPositionLocked(false)
        XCTAssertTrue(controller.isContextMenuVisible)
        XCTAssertFalse(controller.isPanelMovableByWindowBackground)

        controller.contextMenuActions(appState: appState)
            .setPassesPointerInputThrough(true)
        XCTAssertFalse(controller.isContextMenuVisible)
        XCTAssertTrue(controller.isPanelIgnoringMouseEvents)
        XCTAssertFalse(controller.isPanelMovableByWindowBackground)

        appState.setPassesPointerInputThrough(false)
        controller.pointerClickThroughDidChange()
        XCTAssertFalse(controller.isPanelIgnoringMouseEvents)
        XCTAssertTrue(controller.isPanelMovableByWindowBackground)
        controller.hide()
    }

    @MainActor
    func testClickThroughClearsTransientInputSuppression() throws {
        let suiteName = "PositionLockClickThroughTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let frameName = "PositionLockClickThroughTests.\(UUID().uuidString)"
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(frameName)")
        }
        let appState = AppState(defaults: defaults)
        let controller = PetPanelController(frameName: frameName)
        controller.show(appState: appState)
        let absorptionResetID = appState.absorptionResetID

        controller.setTooltipVisible(true)
        XCTAssertTrue(controller.isTooltipVisible)
        XCTAssertTrue(controller.isResetCountdownUpdateActive)
        appState.setPassesPointerInputThrough(true)
        controller.pointerClickThroughDidChange()
        XCTAssertFalse(controller.isTooltipVisible)
        XCTAssertFalse(controller.isResetCountdownUpdateActive)

        appState.setPassesPointerInputThrough(false)
        controller.pointerClickThroughDidChange()
        controller.beginDragTracking()
        XCTAssertTrue(controller.isDragTrackingActive)
        appState.setPassesPointerInputThrough(true)
        controller.pointerClickThroughDidChange()
        XCTAssertFalse(controller.isDragTrackingActive)

        appState.setPassesPointerInputThrough(false)
        controller.pointerClickThroughDidChange()
        let frame = try XCTUnwrap(controller.petFrame)
        controller.showContextMenu(at: CGPoint(x: frame.midX, y: frame.midY))
        XCTAssertTrue(controller.isContextMenuVisible)
        controller.contextMenuActions(appState: appState)
            .setPassesPointerInputThrough(true)
        XCTAssertFalse(controller.isContextMenuVisible)
        XCTAssertEqual(appState.absorptionResetID, absorptionResetID)
        controller.hide()
    }

    @MainActor
    func testLockedPanelRestoresNamedFrameAndUnlockedLaunchIgnoresIt() throws {
        let suiteName = "PositionLockClickThroughTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let frameName = "PositionLockClickThroughTests.\(UUID().uuidString)"
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(frameName)")
        }
        let visibleFrame = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let savedFrame = CGRect(
            x: visibleFrame.minX + 48,
            y: visibleFrame.minY + 48,
            width: PetSize.large.sceneSize.width,
            height: PetSize.large.sceneSize.height
        )
        let seedPanel = NSPanel(
            contentRect: savedFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        seedPanel.saveFrame(usingName: frameName)

        let appState = AppState(defaults: defaults)
        appState.setPetPositionLocked(true)
        let lockedController = PetPanelController(frameName: frameName)
        lockedController.show(appState: appState)
        XCTAssertEqual(lockedController.petFrame, savedFrame)
        lockedController.hide()

        appState.setPetPositionLocked(false)
        let unlockedController = PetPanelController(frameName: frameName)
        unlockedController.show(appState: appState)
        XCTAssertNotEqual(unlockedController.petFrame, savedFrame)
        unlockedController.hide()
    }

    @MainActor
    func testHiddenLockedResizePersistsAndRelockOverwritesCurrentFrame() throws {
        let suiteName = "PositionLockClickThroughTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let frameName = "PositionLockClickThroughTests.\(UUID().uuidString)"
        let frameDefaultsKey = "NSWindow Frame \(frameName)"
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            UserDefaults.standard.removeObject(forKey: frameDefaultsKey)
        }
        let appState = AppState(defaults: defaults)
        appState.setPetPositionLocked(true)
        let controller = PetPanelController(frameName: frameName)
        controller.show(appState: appState)
        let originalFrame = try XCTUnwrap(controller.petFrame)
        let originalCenter = CGPoint(x: originalFrame.midX, y: originalFrame.midY)
        controller.hide()

        appState.setPetSize(.medium)
        controller.resize(to: .medium)
        let hiddenLockedFrame = try XCTUnwrap(controller.petFrame)
        XCTAssertFalse(controller.isVisible)
        XCTAssertEqual(hiddenLockedFrame.size, PetSize.medium.sceneSize)
        XCTAssertEqual(
            CGPoint(x: hiddenLockedFrame.midX, y: hiddenLockedFrame.midY),
            originalCenter
        )
        let lockedRecord = try XCTUnwrap(
            UserDefaults.standard.string(forKey: frameDefaultsKey)
        )

        let restoredController = PetPanelController(frameName: frameName)
        restoredController.show(appState: appState)
        XCTAssertEqual(restoredController.petFrame, hiddenLockedFrame)
        restoredController.hide()

        appState.setPetPositionLocked(false)
        controller.positionLockDidChange()
        appState.setPetSize(.small)
        controller.resize(to: .small)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: frameDefaultsKey),
            lockedRecord
        )

        appState.setPetPositionLocked(true)
        controller.positionLockDidChange()
        let relockedRecord = try XCTUnwrap(
            UserDefaults.standard.string(forKey: frameDefaultsKey)
        )
        XCTAssertNotEqual(relockedRecord, lockedRecord)

        let relockedController = PetPanelController(frameName: frameName)
        relockedController.show(appState: appState)
        XCTAssertEqual(relockedController.petFrame, controller.petFrame)
        relockedController.hide()
    }

    @MainActor
    func testFrameResolutionPreservesCenterChoosesPositiveIntersectionAndClamps() throws {
        let main = PetDisplayGeometry(
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 24, width: 1_440, height: 876)
        )
        let left = PetDisplayGeometry(
            frame: CGRect(x: -1_200, y: 0, width: 1_200, height: 1_920),
            visibleFrame: CGRect(x: -1_200, y: 0, width: 1_200, height: 1_880)
        )
        let above = PetDisplayGeometry(
            frame: CGRect(x: 0, y: 900, width: 1_080, height: 1_920),
            visibleFrame: CGRect(x: 0, y: 900, width: 1_080, height: 1_880)
        )
        let displays = [main, left, above]

        for size in PetSize.allCases.map(\.sceneSize) {
            let candidate = CGRect(x: -900, y: 700, width: 400, height: 220)
            let resolved = try XCTUnwrap(
                PetPanelController.resolvedPetFrame(
                    candidate: candidate,
                    size: size,
                    displays: displays,
                    fallbackVisibleFrame: main.visibleFrame
                )
            )
            XCTAssertEqual(resolved.size, size)
            XCTAssertEqual(resolved.midX, candidate.midX)
            XCTAssertTrue(left.visibleFrame.contains(resolved))
        }

        let removedDisplayFrame = try XCTUnwrap(
            PetPanelController.resolvedPetFrame(
                candidate: CGRect(x: 5_000, y: -3_000, width: 400, height: 220),
                size: PetSize.large.sceneSize,
                displays: displays,
                fallbackVisibleFrame: main.visibleFrame
            )
        )
        XCTAssertTrue(main.visibleFrame.contains(removedDisplayFrame))

        XCTAssertNil(
            PetPanelController.resolvedPetFrame(
                candidate: CGRect(x: CGFloat.nan, y: 0, width: 400, height: 220),
                size: PetSize.large.sceneSize,
                displays: displays,
                fallbackVisibleFrame: main.visibleFrame
            )
        )
    }

    func testPointerThresholdAndPixelMenuGeometryMatchFreeze() {
        let size = PetSize.large.sceneSize
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        XCTAssertTrue(
            ContextMenuInteraction.acceptsClick(
                mouseDown: center,
                mouseUp: CGPoint(x: center.x + 6, y: center.y),
                sceneSize: size
            )
        )
        XCTAssertFalse(
            ContextMenuInteraction.acceptsClick(
                mouseDown: center,
                mouseUp: CGPoint(x: center.x + 6.01, y: center.y),
                sceneSize: size
            )
        )
        XCTAssertEqual(PixelContextMenuView.panelSize, CGSize(width: 462, height: 474))
    }

    func testEnglishAndRussianToggleLocalizationsAreBundled() throws {
        let appBundle = Bundle(for: AppDelegate.self)
        let english = try XCTUnwrap(
            appBundle.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
        )
        let russian = try XCTUnwrap(
            appBundle.path(forResource: "ru", ofType: "lproj").flatMap(Bundle.init(path:))
        )
        let translations = [
            "menu.lock_position": ("Lock Position", "Закрепить положение"),
            "menu.pass_pointer_input_through": (
                "Pass Pointer Input Through",
                "Пропускать ввод указателя"
            ),
            "accessibility.toggle.on": ("On", "Включено"),
            "accessibility.toggle.off": ("Off", "Выключено")
        ]
        for (key, value) in translations {
            XCTAssertEqual(english.localizedString(forKey: key, value: nil, table: nil), value.0)
            XCTAssertEqual(russian.localizedString(forKey: key, value: nil, table: nil), value.1)
        }
        XCTAssertNotEqual(
            english.localizedString(
                forKey: "menu.pass_pointer_input_through.help",
                value: nil,
                table: nil
            ),
            "menu.pass_pointer_input_through.help"
        )
        XCTAssertNotEqual(
            russian.localizedString(
                forKey: "menu.pass_pointer_input_through.help",
                value: nil,
                table: nil
            ),
            "menu.pass_pointer_input_through.help"
        )
    }
}

private final class FakeAppServer: CodexAppServerClient {
    private var onSnapshot: ((QuotaSnapshot) -> Void)?
    private var onSpeedMode: ((SpeedMode) -> Void)?
    private var onFailure: ((String) -> Void)?
    private(set) var startCount = 0
    private(set) var rateLimitRefreshCount = 0

    func start(
        onSnapshot: @escaping (QuotaSnapshot) -> Void,
        onSpeedMode: @escaping (SpeedMode) -> Void,
        onFailure: @escaping (String) -> Void
    ) throws {
        startCount += 1
        self.onSnapshot = onSnapshot
        self.onSpeedMode = onSpeedMode
        self.onFailure = onFailure
    }

    func stop() {
        onSnapshot = nil
        onSpeedMode = nil
        onFailure = nil
    }

    func refreshRateLimits() {
        rateLimitRefreshCount += 1
    }

    func fail(with message: String) {
        onFailure?(message)
    }

    func send(snapshot: QuotaSnapshot) {
        onSnapshot?(snapshot)
    }

    func send(speedMode: SpeedMode) {
        onSpeedMode?(speedMode)
    }
}

private final class FakeLaunchAtLoginService {
    enum Failure: LocalizedError {
        case denied

        var errorDescription: String? { "Login item denied" }
    }

    var status: SMAppService.Status = .notRegistered
    var error: Failure?

    func setEnabled(_ isEnabled: Bool) throws {
        if let error { throw error }
        status = isEnabled ? .enabled : .notRegistered
    }
}
