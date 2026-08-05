import AppKit
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

    func testPetSizeOptionsUseApprovedDimensions() {
        XCTAssertEqual(PetSize.allCases, [.small, .medium, .large])
        XCTAssertEqual(PetSize.small.label, "S")
        XCTAssertEqual(PetSize.medium.label, "M")
        XCTAssertEqual(PetSize.large.label, "L")
        XCTAssertEqual(PetSize.small.sceneSize, CGSize(width: 240, height: 132))
        XCTAssertEqual(PetSize.medium.sceneSize, CGSize(width: 320, height: 176))
        XCTAssertEqual(PetSize.large.sceneSize, CGSize(width: 400, height: 220))
        XCTAssertEqual(AbsorptionVisualState.objectSize, 48)
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
            russian.localizedString(forKey: "reset.days.remaining", value: nil, table: nil),
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

        let menuTranslations = [
            "menu.quota.short": ("Quota", "Квота"),
            "menu.retry": ("Retry Now", "Повторить сейчас"),
            "menu.hide_pet": ("Hide Pet", "Скрыть питомца"),
            "menu.show_pet": ("Show Pet", "Показать питомца"),
            "menu.size": ("Size", "Размер"),
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
    }

    @MainActor
    func testTooltipProgressPresentationUsesRealSpeedMode() {
        XCTAssertEqual(
            QuotaTooltipView.progressPresentation(for: .standard),
            .standard
        )
        XCTAssertEqual(
            QuotaTooltipView.progressPresentation(for: .turbo),
            .turbo
        )
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
    func testTooltipQuotaLevelsUseRequestedBoundaries() {
        XCTAssertEqual(QuotaTooltipView.quotaLevel(for: 100), .normal)
        XCTAssertEqual(QuotaTooltipView.quotaLevel(for: 30), .normal)
        XCTAssertEqual(QuotaTooltipView.quotaLevel(for: 29), .warning)
        XCTAssertEqual(QuotaTooltipView.quotaLevel(for: 10), .warning)
        XCTAssertEqual(QuotaTooltipView.quotaLevel(for: 9), .critical)
        XCTAssertEqual(QuotaTooltipView.quotaLevel(for: 0), .critical)
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

        XCTAssertEqual(catalog.manifest.canvas, .init(width: 64, height: 64))
        XCTAssertEqual(catalog.manifest.objects.count, 31)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: catalog.manifest.categories.map { ($0.id, $0.weight) }),
            ["space": 2, "animals": 2, "characters": 1]
        )
        XCTAssertEqual(
            catalog.manifest.objects.filter { $0.category == "characters" }.count,
            7
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
            XCTAssertEqual(bitmap.pixelsWide, 64, object.id)
            XCTAssertEqual(bitmap.pixelsHigh, 64, object.id)
            XCTAssertEqual(bitmap.colorAt(x: 0, y: 0)?.alphaComponent, 0, object.id)
            XCTAssertEqual(bitmap.colorAt(x: 63, y: 63)?.alphaComponent, 0, object.id)
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

    func testAbsorptionRenderingStaysInsideEveryPetSize() {
        let object = AbsorbableObjectManifest.Object(
            id: "test",
            category: "animals",
            asset: "absorb-bear-cub"
        )
        let startDate = Date(timeIntervalSince1970: 1_000)
        let seeds: [UInt64] = [0, 1, 29, 42, 155, 607, 965, 988, .max]

        for petSize in PetSize.allCases {
            let sceneSize = petSize.sceneSize
            let safeFrame = CGRect(origin: .zero, size: sceneSize).insetBy(
                dx: AbsorptionVisualState.renderingInset,
                dy: AbsorptionVisualState.renderingInset
            )
            for side in AbsorptionSpawnSide.allCases {
                for seed in seeds {
                    let plan = AbsorptionPlan(
                        object: object,
                        startDate: startDate,
                        duration: 1,
                        side: side,
                        seed: seed,
                        usesReducedMotion: false
                    )
                    for sample in 0...40 {
                        let state = AbsorptionVisualState.make(
                            plan: plan,
                            at: startDate.addingTimeInterval(Double(sample) / 40),
                            sceneSize: sceneSize
                        )
                        let frame = state.renderedFrame
                        let context = "\(petSize) \(side) seed=\(seed) sample=\(sample)"
                        XCTAssertGreaterThanOrEqual(frame.minX, safeFrame.minX, context)
                        XCTAssertGreaterThanOrEqual(frame.minY, safeFrame.minY, context)
                        XCTAssertLessThanOrEqual(frame.maxX, safeFrame.maxX, context)
                        XCTAssertLessThanOrEqual(frame.maxY, safeFrame.maxY, context)
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

    func testSmallAbsorptionSpawnPointsKeepObjectsInsideScene() {
        let object = AbsorbableObjectManifest.Object(
            id: "test",
            category: "space",
            asset: "test"
        )
        let startDate = Date(timeIntervalSince1970: 3_000)
        let inset = AbsorptionVisualState.objectSize / 2

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
    func testPanelHidesAndRestores() {
        let appState = AppState()
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
        let appState = AppState()
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
        appState.setHidesInFullScreenApps(true)

        controller.updateVisibility(appState: appState)
        XCTAssertTrue(controller.isVisible)

        isFullScreen = true
        controller.updateVisibility(appState: appState)
        XCTAssertFalse(controller.isVisible)

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
        let appState = AppState(appServer: appServer, retryDelays: [60])

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
        let appState = AppState(appServer: appServer, retryDelays: [0])

        appState.start()
        appServer.fail(with: "Connection lost")
        appServer.fail(with: "Duplicate failure")
        await Self.waitUntil { appServer.startCount == 2 }

        XCTAssertEqual(appServer.startCount, 2)
        XCTAssertEqual(appState.connectionState, .reconnecting)
        appState.stop()
    }

    func testReconnectBackoffIsBounded() {
        XCTAssertEqual(AppState.reconnectDelays, [1, 2, 5, 10, 30])
    }

    @MainActor
    func testQuotaRefreshesOnlyAfterSnapshotBecomesStale() async {
        let appServer = FakeAppServer()
        var now = Date(timeIntervalSince1970: 1_000)
        let appState = AppState(appServer: appServer, now: { now })

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

    private static func snapshot(remainingPercent: Int) -> QuotaSnapshot {
        QuotaSnapshot(
            limitId: "codex",
            limitName: nil,
            planType: "pro",
            primary: QuotaWindow(
                usedPercent: 100 - remainingPercent,
                windowDurationMins: nil,
                resetsAt: nil
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

private final class FakeAppServer: CodexAppServerClient {
    private var onSnapshot: ((QuotaSnapshot) -> Void)?
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
        self.onFailure = onFailure
    }

    func stop() {
        onSnapshot = nil
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
