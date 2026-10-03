import AppKit
import SwiftUI

/// Presentation-only state. Moving or enlarging the preview never commits a choice.
struct CompanionPickerNavigation: Equatable {
    private(set) var categoryID: String
    private(set) var previewID: String?
    var zoom = 2

    init(objects: [AbsorbableObjectManifest.Object], selectedID: String?) {
        let initial = objects.first { $0.id == selectedID } ?? objects.first
        categoryID = initial?.category ?? "space"
        previewID = initial?.id
    }

    mutating func showCategory(_ category: String, objects: [AbsorbableObjectManifest.Object], selectedID: String?) {
        let items = objects.filter { $0.category == category }
        guard !items.isEmpty else { return }
        categoryID = category
        previewID = (items.first { $0.id == selectedID } ?? items[0]).id
    }

    mutating func preview(_ id: String, objects: [AbsorbableObjectManifest.Object]) {
        guard objects.contains(where: { $0.id == id && $0.category == categoryID }) else { return }
        previewID = id
    }

    func movedID(from id: String, by offset: Int, objects: [AbsorbableObjectManifest.Object]) -> String? {
        let items = objects.filter { $0.category == categoryID }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items[min(items.count - 1, max(0, index + offset))].id
    }

    var columns: Int { categoryID == "characters" ? 3 : 6 }
    var previewSize: CGFloat { [80, 120, 160][min(2, max(0, zoom))] }
}

/// Losslessly extracted source sheets and the exact fractional crops in the approved mockup.
struct CompanionPreview: Decodable {
    let id: String
    let source: String
    let sourceSize: [CGFloat]
    let crop: [CGFloat]

    static func load(bundle: Bundle = .main) -> [CompanionPreview] {
        guard let url = bundle.url(forResource: "manifest", withExtension: "json", subdirectory: "CompanionPreviews"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Self].self, from: data) else { return [] }
        return entries.filter { $0.isValid }
    }

    var isValid: Bool {
        sourceSize.count == 2 && crop.count == 4
            && (sourceSize + crop).allSatisfy { $0.isFinite && $0 >= 0 }
            && crop[2] > 0 && crop[3] > 0
            && crop[0] + crop[2] <= sourceSize[0] && crop[1] + crop[3] <= sourceSize[1]
    }

    func scale(for size: CGFloat) -> CGFloat { size / max(crop[2], crop[3]) }
}

private enum CompanionImages {
    static let previews = Dictionary(uniqueKeysWithValues: CompanionPreview.load().map { ($0.id, $0) })
    private static let cache = NSCache<NSString, NSImage>()

    static func image(name: String, preview: Bool) -> NSImage? {
        let key = "\(preview):\(name)" as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let url = Bundle.main.url(forResource: name, withExtension: preview ? "webp" : "png",
                                        subdirectory: preview ? "CompanionPreviews" : "objects"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

struct CompanionThumbnail: View {
    let object: AbsorbableObjectManifest.Object

    var body: some View {
        if let image = CompanionImages.image(name: object.asset, preview: false) {
            Image(nsImage: image).resizable().interpolation(.none).scaledToFit()
                .accessibilityHidden(true)
        }
    }
}

struct CompanionPickerView: View {
    nonisolated static let contentWidth: CGFloat = 380
    nonisolated static let panelSize = CGSize(width: 388, height: 600)
    let appState: AppState
    var dismiss: () -> Void = {}
    var announceSelection: (String) -> Void = { _ in }
    @State private var navigation: CompanionPickerNavigation
    @FocusState private var focusedID: String?
    @AccessibilityFocusState private var accessibilityFocusedID: String?

    init(appState: AppState, dismiss: @escaping () -> Void = {}, announceSelection: @escaping (String) -> Void = { _ in }) {
        self.appState = appState
        self.dismiss = dismiss
        self.announceSelection = announceSelection
        _navigation = State(initialValue: CompanionPickerNavigation(objects: appState.companionObjects,
                                                                    selectedID: appState.selectedCompanionID))
    }

    private var pixel: Bool { appState.tooltipStyle == .pixel }
    private var text: Color { pixel ? PixelPalette.highlightText : Color(red: 0.957, green: 0.957, blue: 0.965) }
    private var secondary: Color { pixel ? PixelPalette.mutedGold : Color(white: 0.69) }
    private var accent: Color { pixel ? PixelPalette.brightGold : Color(red: 1, green: 0.76, blue: 0.31) }
    private var well: Color { pixel ? PixelPalette.cellBackground : Color(white: 0.11) }
    private var line: Color { pixel ? PixelPalette.innerBorder : Color(white: 0.24) }
    private var items: [AbsorbableObjectManifest.Object] { appState.companionObjects.filter { $0.category == navigation.categoryID } }
    private var preview: AbsorbableObjectManifest.Object? { items.first { $0.id == navigation.previewID } }
    private var selectedPreview: Bool { preview?.id != nil && preview?.id == appState.selectedCompanionID }

    var body: some View {
        ScrollViewReader { scroll in
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                header
                previewStage
                toolbar
                categories
                grid
                footer
            }
            .padding(.vertical, 3)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onChange(of: focusedID) { _, id in
            if let id {
                navigation.preview(id, objects: appState.companionObjects)
                scroll.scrollTo(id)
            }
        }
        .onChange(of: accessibilityFocusedID) { _, id in
            if let id { navigation.preview(id, objects: appState.companionObjects) }
        }
        }
        .background {
            if pixel { PixelMenuBackground() }
            else {
                RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.067, green: 0.071, blue: 0.078))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(line, lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 5, y: 3)
            }
        }
        .font(.system(size: pixel ? 12 : 13, design: pixel ? .monospaced : .rounded))
        .foregroundStyle(text)
        .tint(accent)
        .padding(.top, 8)
        .padding(.trailing, 8)
        .padding(.bottom, 4)
        .preferredColorScheme(.dark)
        .onExitCommand(perform: dismiss)
        .onAppear { focusedID = navigation.previewID }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localized("companion.title"))
    }

    private var header: some View {
        HStack {
            Text(localized("companion.title")).font(.system(size: pixel ? 12 : 14, weight: .medium, design: pixel ? .monospaced : .rounded))
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark").frame(width: 28, height: 28) }
                .buttonStyle(CompanionControlStyle(pixel: pixel))
                .accessibilityLabel(localized("companion.close"))
                .help(localized("companion.close"))
        }
        .padding(.horizontal, 14).frame(height: 44)
    }

    private var previewStage: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Color(red: 0.012, green: 0.027, blue: 0.098)
                if let object = preview, let entry = CompanionImages.previews[object.id],
                   let image = CompanionImages.image(name: entry.source, preview: true) {
                    let scale = entry.scale(for: navigation.previewSize)
                    Image(nsImage: image).resizable().interpolation(.high)
                        .frame(width: entry.sourceSize[0] * scale, height: entry.sourceSize[1] * scale)
                        .offset(x: -entry.crop[0] * scale, y: -entry.crop[1] * scale)
                        .frame(width: entry.crop[2] * scale, height: entry.crop[3] * scale, alignment: .topLeading)
                        .clipped()
                }
            }
            .frame(width: 160, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: pixel ? 0 : 12))
            .overlay(RoundedRectangle(cornerRadius: pixel ? 0 : 12).strokeBorder(line, lineWidth: 1))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(localized("absorption.category.\(navigation.categoryID)"))
                    .font(.system(size: 11, design: pixel ? .monospaced : .rounded)).foregroundStyle(secondary).padding(.bottom, 4)
                Text(preview?.companionName ?? localized("companion.none"))
                    .font(.system(size: pixel ? 17 : 19, weight: .medium, design: pixel ? .monospaced : .rounded))
                    .foregroundStyle(selectedPreview ? accent : text)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(preview?.companionDescription ?? "")
                    .font(.system(size: 11, design: pixel ? .monospaced : .rounded)).foregroundStyle(secondary)
                    .lineLimit(2).frame(height: 30, alignment: .topLeading).padding(.top, 4)
                Text(selectedPreview ? "✓ \(localized("companion.selected"))" : localized("companion.preview_status"))
                    .font(.system(size: 11, design: pixel ? .monospaced : .rounded)).foregroundStyle(selectedPreview ? accent : secondary).frame(height: 19).padding(.top, 7)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 140, alignment: .topLeading)
            .padding(.top, 20)
        }
        .frame(height: 176, alignment: .top).padding(.top, 8)
        .padding(.horizontal, 14)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("\(localized("companion.preview")) · \(["1×", "1.5×", "2×"][navigation.zoom])").font(.system(size: 11, design: pixel ? .monospaced : .rounded)).foregroundStyle(secondary)
            Spacer(minLength: 0)
            Button { navigation.zoom = max(0, navigation.zoom - 1) } label: {
                Image(systemName: "minus.magnifyingglass").frame(width: 28, height: 28)
            }
            .disabled(navigation.zoom == 0)
            .accessibilityLabel(localized("companion.zoom_out"))
            Slider(value: Binding(get: { Double(navigation.zoom) }, set: { navigation.zoom = Int($0) }), in: 0...2, step: 1)
                .frame(width: 82)
                .accessibilityLabel(localized("companion.zoom"))
                .accessibilityValue(["1×", "1.5×", "2×"][navigation.zoom])
            Button { navigation.zoom = min(2, navigation.zoom + 1) } label: {
                Image(systemName: "plus.magnifyingglass").frame(width: 28, height: 28)
            }
            .disabled(navigation.zoom == 2)
            .accessibilityLabel(localized("companion.zoom_in"))
        }
        .buttonStyle(CompanionControlStyle(pixel: pixel))
        .padding(.horizontal, 14).padding(.bottom, 10)
    }

    private var categories: some View {
        HStack(spacing: 3) {
            ForEach(appState.absorptionCategories, id: \.id) { category in
                Button {
                    navigation.showCategory(category.id, objects: appState.companionObjects, selectedID: appState.selectedCompanionID)
                } label: {
                    Text(localized("absorption.category.\(category.id)"))
                        .font(.system(size: 12, design: pixel ? .monospaced : .rounded))
                        .lineLimit(1).frame(maxWidth: .infinity).frame(height: 28)
                }
                .buttonStyle(CompanionControlStyle(pixel: pixel, selected: category.id == navigation.categoryID, bordered: true))
                .accessibilityAddTraits(category.id == navigation.categoryID ? .isSelected : [])
            }
        }
        .padding(pixel ? 0 : 3).background(well, in: RoundedRectangle(cornerRadius: pixel ? 0 : 8))
        .padding(.horizontal, 14).padding(.bottom, 12)
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: navigation.columns), spacing: 5) {
            ForEach(items) { object in
                let selected = object.id == appState.selectedCompanionID
                Button { choose(object.id) } label: {
                    VStack(spacing: navigation.categoryID == "characters" ? 2 : 1) {
                        CompanionThumbnail(object: object)
                            .frame(width: navigation.categoryID == "characters" ? 44 : 40,
                                   height: navigation.categoryID == "characters" ? 44 : 40)
                        Text(object.companionName).font(.system(size: 11, design: pixel ? .monospaced : .rounded))
                            .foregroundStyle(selected ? accent : text).lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity).frame(height: navigation.categoryID == "characters" ? 68 : 64)
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.black).frame(width: 15, height: 15)
                                .background(accent, in: RoundedRectangle(cornerRadius: pixel ? 0 : 8))
                                .padding(3).accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(CompanionControlStyle(pixel: pixel, selected: selected, focused: focusedID == object.id, tile: true))
                .id(object.id)
                .focused($focusedID, equals: object.id)
                .accessibilityFocused($accessibilityFocusedID, equals: object.id)
                .onHover { inside in if inside { navigation.preview(object.id, objects: appState.companionObjects) } }
                .accessibilityLabel(object.companionName)
                .accessibilityValue(selected ? localized("companion.selected") : "")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .help(object.companionName)
            }
        }
        .padding(.horizontal, 14)
        .onKeyPress(.leftArrow) { moveFocus(by: -1) }
        .onKeyPress(.rightArrow) { moveFocus(by: 1) }
        .onKeyPress(.upArrow) { moveFocus(by: -navigation.columns) }
        .onKeyPress(.downArrow) { moveFocus(by: navigation.columns) }
        .onKeyPress(.return) { chooseFocused() }
        .onKeyPress(.space) { chooseFocused() }
    }

    private var footer: some View {
        HStack {
            Button { choose(nil) } label: {
                HStack(spacing: 5) {
                    Image(systemName: appState.selectedCompanionID == nil ? "checkmark" : "nosign")
                    Text(localized("companion.none"))
                }.padding(.horizontal, 4).frame(height: 28)
            }
            .buttonStyle(CompanionControlStyle(pixel: pixel, selected: appState.selectedCompanionID == nil))
            .accessibilityAddTraits(appState.selectedCompanionID == nil ? .isSelected : [])
            Spacer(minLength: 4)
            Text(localized("companion.during_work")).font(.system(size: 11, design: pixel ? .monospaced : .rounded)).foregroundStyle(secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(line).frame(height: 1) }
        .padding(.top, 10)
    }

    private func choose(_ id: String?) {
        let previous = appState.selectedCompanionID
        if let id { navigation.preview(id, objects: appState.companionObjects) }
        appState.setSelectedCompanionID(id)
        if previous != appState.selectedCompanionID {
            announceSelection(String.localizedStringWithFormat(localized("companion.announcement"), appState.companionSelectionName))
        }
    }

    private func moveFocus(by offset: Int) -> KeyPress.Result {
        guard let focusedID, let next = navigation.movedID(from: focusedID, by: offset, objects: appState.companionObjects) else { return .ignored }
        self.focusedID = next
        return .handled
    }

    private func chooseFocused() -> KeyPress.Result {
        guard let focusedID, items.contains(where: { $0.id == focusedID }) else { return .ignored }
        choose(focusedID)
        return .handled
    }

    private func localized(_ key: String) -> String { NSLocalizedString(key, comment: "Companion picker") }
}

private struct CompanionControlStyle: ButtonStyle {
    let pixel: Bool
    var selected = false
    var focused = false
    var tile = false
    var bordered = false
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: pixel ? 0 : tile ? 8 : 5)
                    .fill(background(pressed: configuration.isPressed))
                    .overlay {
                        RoundedRectangle(cornerRadius: pixel ? 0 : tile ? 8 : 5)
                            .strokeBorder(focused ? Color.white : selected && tile ? accent : pixel && (tile || bordered) ? PixelPalette.innerBorder : .clear,
                                          lineWidth: focused ? 2 : 1)
                    }
            }
            .opacity(enabled ? 1 : 0.35)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
    }

    private var accent: Color { pixel ? PixelPalette.brightGold : Color(red: 1, green: 0.76, blue: 0.31) }
    private func background(pressed: Bool) -> Color {
        if pressed || hovered || selected { return pixel ? PixelPalette.hoverBackground : selected && tile ? Color(red: 0.24, green: 0.20, blue: 0.12) : Color(white: 0.19) }
        return tile ? (pixel ? PixelPalette.cellBackground : Color(white: 0.11)) : .clear
    }
}
