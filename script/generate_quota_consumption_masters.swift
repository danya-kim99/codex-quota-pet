#!/usr/bin/swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let canvasSize = CGSize(width: 384, height: 272)
private let anchor = CGPoint(x: 192, y: 136)
private let frameDelay = 1.0 / 24.0
private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private let framesDirectory = root.appendingPathComponent("Assets/Sprites/frames", isDirectory: true)
private let consumptionDirectory = framesDirectory.appendingPathComponent("consumption", isDirectory: true)

private enum MasterKind: String, CaseIterable {
    case small
    case medium
    case large
    case lastLight = "last-light"

    var frameCount: Int {
        switch self {
        case .small: 10
        case .medium: 20
        case .large: 30
        case .lastLight: 40
        }
    }
}

private extension MasterKind {
    var keyframes: [ContourKeyframe] {
        switch self {
        case .small: smallKeyframes
        case .medium: mediumKeyframes
        case .large: largeKeyframes
        case .lastLight: lastLightKeyframes
        }
    }
}

private struct PixelColor {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    static let white = Self(red: 1.0, green: 0.96, blue: 0.69)
    static let gold = Self(red: 1.0, green: 0.76, blue: 0.31)
    static let amber = Self(red: 1.0, green: 0.50, blue: 0.12)
    static let orange = Self(red: 1.0, green: 0.22, blue: 0.10)
    static let redshift = Self(red: 0.86, green: 0.10, blue: 0.05)
    static let magenta = Self(red: 0.88, green: 0.27, blue: 0.73)
    static let violet = Self(red: 0.68, green: 0.27, blue: 0.94)
}

private func loadImage(named name: String) throws -> CGImage {
    let url = framesDirectory.appendingPathComponent(name)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          image.width == Int(canvasSize.width),
          image.height == Int(canvasSize.height) else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return image
}

private func makeContext() throws -> CGContext {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil,
        width: Int(canvasSize.width),
        height: Int(canvasSize.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw CocoaError(.coderInvalidValue)
    }
    context.interpolationQuality = .none
    context.setShouldAntialias(false)
    return context
}

private func drawBase(_ image: CGImage, in context: CGContext) {
    context.draw(image, in: CGRect(origin: .zero, size: canvasSize))
}

private func restoreShadow(from base: CGImage, in context: CGContext) {
    context.saveGState()
    context.addEllipse(in: CGRect(x: 148, y: 92, width: 88, height: 88))
    context.clip()
    drawBase(base, in: context)
    context.restoreGState()
}

private typealias PixelPoint = (x: Int, y: Int)

private struct ContourKeyframe {
    let wedge: [PixelPoint]
    let primary: [PixelPoint]
    let lowerLens: [PixelPoint]
    let equator: [PixelPoint]
    let secondary: [PixelPoint]
    let loop: [PixelPoint]
    let primaryWidth: CGFloat
    let lowerWidth: CGFloat
    let equatorWidth: CGFloat
    let secondaryWidth: CGFloat
    let loopWidth: CGFloat
    let brightness: CGFloat
    let lowerBrightness: CGFloat
    let secondaryBrightness: CGFloat
    let loopBrightness: CGFloat
    let bodyColor: PixelColor
    let highlightColor: PixelColor
    let lowerBodyColor: PixelColor
    let lowerHighlightColor: PixelColor
    let secondaryBodyColor: PixelColor
    let secondaryHighlightColor: PixelColor
    let loopBodyColor: PixelColor
    let loopHighlightColor: PixelColor

    init(
        wedge: [PixelPoint] = [],
        primary: [PixelPoint] = [],
        lowerLens: [PixelPoint] = [],
        equator: [PixelPoint] = [],
        primaryWidth: CGFloat = 0,
        lowerWidth: CGFloat = 0,
        brightness: CGFloat = 0,
        lowerBrightness: CGFloat = 0,
        secondary: [PixelPoint] = [],
        loop: [PixelPoint] = [],
        equatorWidth: CGFloat = 4,
        secondaryWidth: CGFloat = 0,
        loopWidth: CGFloat = 0,
        secondaryBrightness: CGFloat = 0,
        loopBrightness: CGFloat = 0,
        bodyColor: PixelColor = .gold,
        highlightColor: PixelColor = .white,
        lowerBodyColor: PixelColor = .orange,
        lowerHighlightColor: PixelColor = .amber,
        secondaryBodyColor: PixelColor = .amber,
        secondaryHighlightColor: PixelColor = .gold,
        loopBodyColor: PixelColor = .gold,
        loopHighlightColor: PixelColor = .white
    ) {
        self.wedge = wedge
        self.primary = primary
        self.lowerLens = lowerLens
        self.equator = equator
        self.secondary = secondary
        self.loop = loop
        self.primaryWidth = primaryWidth
        self.lowerWidth = lowerWidth
        self.equatorWidth = equatorWidth
        self.secondaryWidth = secondaryWidth
        self.loopWidth = loopWidth
        self.brightness = brightness
        self.lowerBrightness = lowerBrightness
        self.secondaryBrightness = secondaryBrightness
        self.loopBrightness = loopBrightness
        self.bodyColor = bodyColor
        self.highlightColor = highlightColor
        self.lowerBodyColor = lowerBodyColor
        self.lowerHighlightColor = lowerHighlightColor
        self.secondaryBodyColor = secondaryBodyColor
        self.secondaryHighlightColor = secondaryHighlightColor
        self.loopBodyColor = loopBodyColor
        self.loopHighlightColor = loopHighlightColor
    }

    static let idle = Self()
}

// Every contour below is a separately drawn frame. Coordinates are source pixels;
// there is no trajectory, interpolation, easing function, or generated in-between.
private let smallKeyframes: [ContourKeyframe] = [
    .idle,
    .init(
        wedge: [(222, 133), (232, 132), (243, 133), (250, 136), (243, 139), (232, 140), (222, 138)],
        primary: [(222, 136), (232, 134), (242, 134), (249, 136)],
        primaryWidth: 2, brightness: 0.62
    ),
    .init(
        wedge: [(220, 132), (232, 130), (244, 131), (252, 136), (245, 142), (231, 142), (220, 139)],
        primary: [(220, 136), (232, 133), (244, 133), (251, 136)],
        primaryWidth: 4, brightness: 0.82
    ),
    .init(
        primary: [(222, 136), (227, 130), (236, 125), (245, 125), (251, 130), (251, 136)],
        lowerLens: [(222, 136), (230, 141), (240, 144), (250, 140), (251, 136)],
        equator: [(204, 136), (222, 136), (238, 134), (254, 136), (280, 136)],
        primaryWidth: 6, lowerWidth: 3, brightness: 0.82, lowerBrightness: 0.36
    ),
    .init(
        primary: [(224, 136), (229, 127), (239, 121), (249, 123), (256, 130), (256, 137)],
        lowerLens: [(224, 136), (232, 143), (243, 147), (253, 142), (256, 137)],
        equator: [(202, 136), (224, 136), (240, 133), (258, 136), (282, 136)],
        primaryWidth: 7, lowerWidth: 3, brightness: 0.90, lowerBrightness: 0.40
    ),
    .init(
        primary: [(226, 136), (231, 127), (240, 121), (250, 123), (258, 130), (259, 138), (254, 146), (244, 149), (235, 144)],
        equator: [(202, 136), (226, 136), (242, 133), (260, 136), (284, 136)],
        primaryWidth: 8, brightness: 0.96, bodyColor: .gold
    ),
    .init(
        primary: [(227, 136), (233, 126), (242, 120), (252, 123), (260, 131), (260, 139), (254, 147), (244, 148), (236, 143)],
        equator: [(202, 136), (227, 136), (244, 132), (262, 136), (284, 136)],
        primaryWidth: 8, brightness: 0.94, bodyColor: .amber
    ),
    .init(
        primary: [(230, 136), (237, 128), (247, 126), (254, 132), (254, 139), (247, 144), (236, 141)],
        equator: [(204, 136), (230, 136), (246, 134), (260, 136), (282, 136)],
        primaryWidth: 7, brightness: 0.76, bodyColor: .orange, highlightColor: .amber
    ),
    .init(
        primary: [(234, 136), (242, 131), (249, 134), (248, 139), (240, 141), (236, 139)],
        equator: [(208, 136), (234, 136), (248, 135), (262, 136), (280, 136)],
        primaryWidth: 5, brightness: 0.52, bodyColor: .redshift, highlightColor: .orange
    ),
    .idle
]

private let mediumKeyframes: [ContourKeyframe] = [
    .idle,
    .init(
        wedge: [(218, 133), (229, 132), (242, 132), (252, 136), (242, 140), (228, 140), (218, 138)],
        primary: [(218, 136), (229, 134), (241, 134), (249, 136)],
        lowerLens: [], equator: [], primaryWidth: 2, lowerWidth: 0,
        brightness: 0.62, lowerBrightness: 0, bodyColor: .gold, highlightColor: .white
    ),
    .init(
        wedge: [(214, 132), (226, 130), (243, 131), (254, 136), (243, 142), (226, 142), (214, 139)],
        primary: [(214, 136), (227, 133), (242, 133), (252, 136)],
        lowerLens: [], equator: [], primaryWidth: 3, lowerWidth: 0,
        brightness: 0.82, lowerBrightness: 0, bodyColor: .gold, highlightColor: .white
    ),
    .init(
        wedge: [],
        primary: [(252, 136), (245, 133), (238, 128), (236, 122), (240, 116), (247, 113), (252, 115), (249, 120), (241, 124), (235, 130), (232, 136)],
        lowerLens: [],
        equator: [(190, 136), (212, 136), (225, 136), (238, 134), (252, 136), (286, 136)],
        primaryWidth: 8, lowerWidth: 0, brightness: 0.82, lowerBrightness: 0,
        bodyColor: .gold, highlightColor: .white
    ),
    .init(
        wedge: [],
        primary: [(252, 136), (246, 131), (239, 124), (237, 115), (242, 107), (251, 103), (258, 105), (258, 110), (252, 115), (244, 118), (236, 124), (229, 132), (224, 136)],
        lowerLens: [],
        equator: [(184, 136), (198, 136), (216, 137), (232, 134), (250, 136), (286, 136)],
        primaryWidth: 10, lowerWidth: 0, brightness: 0.90, lowerBrightness: 0,
        bodyColor: .gold, highlightColor: .white
    ),
    .init(
        wedge: [],
        primary: [(250, 136), (245, 129), (239, 119), (240, 109), (247, 101), (257, 98), (264, 101), (265, 107), (258, 113), (248, 116), (238, 121), (228, 129), (212, 136)],
        lowerLens: [],
        equator: [(176, 136), (184, 136), (205, 138), (226, 134), (250, 136), (286, 136)],
        primaryWidth: 12, lowerWidth: 0, brightness: 0.96, lowerBrightness: 0,
        bodyColor: .gold, highlightColor: .white
    ),
    .init(
        wedge: [],
        primary: [(170, 136), (172, 117), (178, 101), (187, 90), (200, 84), (216, 84), (231, 91), (241, 108), (244, 136)],
        lowerLens: [(170, 136), (178, 153), (190, 168), (207, 176), (225, 171), (239, 154), (244, 136)],
        equator: [(65, 136), (110, 136), (150, 137), (170, 136), (185, 139), (207, 135), (229, 133), (244, 136), (278, 136), (319, 136)],
        primaryWidth: 11, lowerWidth: 6, brightness: 0.96, lowerBrightness: 0.46,
        bodyColor: .gold, highlightColor: .white
    ),
    .init(
        wedge: [],
        primary: [(170, 136), (172, 115), (179, 97), (189, 86), (203, 80), (219, 82), (234, 91), (243, 110), (244, 136)],
        lowerLens: [(170, 136), (180, 155), (193, 171), (210, 179), (228, 172), (240, 154), (244, 136)],
        equator: [(65, 136), (110, 136), (150, 138), (170, 136), (184, 140), (205, 136), (228, 132), (244, 136), (278, 136), (319, 136)],
        primaryWidth: 12, lowerWidth: 6, brightness: 1.0, lowerBrightness: 0.50,
        bodyColor: .gold, highlightColor: .white
    ),
    .init(
        wedge: [],
        primary: [(170, 136), (173, 113), (181, 94), (192, 82), (207, 77), (224, 80), (238, 93), (246, 113), (244, 136)],
        lowerLens: [(170, 136), (182, 157), (196, 174), (214, 181), (231, 172), (241, 153), (244, 136)],
        equator: [(65, 136), (110, 136), (150, 138), (170, 136), (182, 141), (203, 137), (227, 132), (244, 136), (278, 136), (319, 136)],
        primaryWidth: 13, lowerWidth: 6, brightness: 1.0, lowerBrightness: 0.52,
        bodyColor: .gold, highlightColor: .white
    ),
    .init(
        wedge: [],
        primary: [(170, 136), (175, 114), (184, 94), (196, 81), (212, 78), (228, 82), (240, 96), (247, 115), (244, 136)],
        lowerLens: [(170, 136), (184, 158), (199, 175), (216, 180), (232, 170), (242, 151), (244, 136)],
        equator: [(65, 136), (110, 136), (150, 139), (170, 136), (183, 141), (204, 136), (228, 131), (244, 136), (278, 136), (319, 136)],
        primaryWidth: 13, lowerWidth: 6, brightness: 0.98, lowerBrightness: 0.48,
        bodyColor: .gold, highlightColor: .white
    ),
    .init(
        wedge: [],
        primary: [(171, 136), (184, 130), (195, 115), (207, 96), (221, 82), (237, 84), (248, 99), (252, 117), (245, 136)],
        lowerLens: [(171, 136), (185, 154), (201, 172), (220, 179), (238, 166), (248, 147), (245, 136)],
        equator: [(65, 136), (110, 136), (150, 139), (170, 136), (181, 142), (202, 139), (226, 132), (245, 136), (278, 136), (319, 136)],
        primaryWidth: 13, lowerWidth: 6, brightness: 0.98, lowerBrightness: 0.45,
        bodyColor: .gold, highlightColor: .white
    ),
    .init(
        wedge: [],
        primary: [(173, 136), (190, 131), (203, 117), (216, 97), (231, 84), (245, 89), (253, 104), (255, 121), (247, 136)],
        lowerLens: [(173, 136), (190, 153), (208, 170), (226, 176), (242, 162), (252, 145), (247, 136)],
        equator: [(65, 136), (110, 136), (150, 140), (172, 136), (181, 143), (202, 140), (227, 131), (247, 136), (280, 136), (319, 136)],
        primaryWidth: 14, lowerWidth: 6, brightness: 1.0, lowerBrightness: 0.42,
        bodyColor: .gold, highlightColor: .white
    ),
    .init(
        wedge: [],
        primary: [(176, 136), (196, 131), (211, 118), (224, 99), (238, 88), (250, 94), (257, 109), (258, 124), (249, 136)],
        lowerLens: [(176, 136), (196, 152), (215, 167), (233, 171), (247, 158), (255, 143), (249, 136)],
        equator: [(65, 136), (110, 136), (150, 140), (176, 136), (183, 144), (204, 140), (229, 131), (249, 136), (281, 136), (319, 136)],
        primaryWidth: 14, lowerWidth: 6, brightness: 1.0, lowerBrightness: 0.38,
        bodyColor: .amber, highlightColor: .white
    ),
    .init(
        wedge: [],
        primary: [(160, 136), (176, 132), (191, 119), (205, 105), (221, 98), (237, 104), (247, 118), (251, 136), (248, 151), (239, 165), (224, 173), (208, 169), (197, 157), (191, 143), (186, 136)],
        lowerLens: [],
        equator: [(65, 136), (110, 136), (150, 140), (160, 136), (183, 144), (204, 141), (230, 131), (256, 136), (284, 136), (319, 136)],
        primaryWidth: 14, lowerWidth: 0, brightness: 1.0, lowerBrightness: 0,
        bodyColor: .amber, highlightColor: .white
    ),
    .init(
        wedge: [],
        primary: [(166, 136), (181, 130), (196, 115), (211, 102), (228, 98), (243, 107), (251, 121), (254, 136), (251, 152), (242, 166), (228, 174), (214, 170), (203, 158), (198, 144), (193, 136)],
        lowerLens: [],
        equator: [(65, 136), (110, 136), (150, 140), (166, 136), (184, 145), (205, 142), (231, 130), (257, 136), (285, 136), (319, 136)],
        primaryWidth: 16, lowerWidth: 0, brightness: 1.0, lowerBrightness: 0,
        bodyColor: .amber, highlightColor: .white
    ),
    .init(
        wedge: [],
        primary: [(176, 136), (190, 127), (204, 111), (220, 101), (237, 103), (249, 113), (256, 127), (257, 140), (252, 155), (242, 168), (229, 173), (217, 166), (209, 153), (205, 142), (201, 136)],
        lowerLens: [],
        equator: [(65, 136), (110, 136), (150, 139), (176, 136), (185, 145), (207, 143), (232, 130), (258, 136), (286, 136), (319, 136)],
        primaryWidth: 16, lowerWidth: 0, brightness: 1.0, lowerBrightness: 0,
        bodyColor: .amber, highlightColor: .white
    ),
    .init(
        wedge: [],
        primary: [(190, 136), (202, 125), (216, 112), (232, 107), (247, 113), (255, 126), (256, 140), (250, 154), (239, 163), (228, 162), (218, 153), (214, 143), (211, 136)],
        lowerLens: [],
        equator: [(65, 136), (110, 136), (150, 138), (190, 136), (187, 143), (210, 142), (234, 132), (258, 136), (286, 136), (319, 136)],
        primaryWidth: 14, lowerWidth: 0, brightness: 0.88, lowerBrightness: 0,
        bodyColor: .orange, highlightColor: .amber
    ),
    .init(
        wedge: [],
        primary: [(208, 136), (218, 126), (231, 118), (244, 120), (252, 130), (252, 141), (246, 151), (236, 156), (227, 151), (223, 142), (221, 136)],
        lowerLens: [],
        equator: [(65, 136), (112, 136), (152, 137), (190, 136), (213, 140), (236, 133), (257, 136), (286, 136), (319, 136)],
        primaryWidth: 10, lowerWidth: 0, brightness: 0.70, lowerBrightness: 0,
        bodyColor: .orange, highlightColor: .redshift
    ),
    .init(
        wedge: [(222, 133), (232, 128), (244, 130), (250, 136), (244, 143), (232, 144), (222, 139)],
        primary: [(222, 136), (233, 132), (244, 133), (248, 136)],
        lowerLens: [],
        equator: [(65, 136), (112, 136), (154, 136), (176, 136), (208, 137), (238, 135), (252, 136), (286, 136), (319, 136)],
        primaryWidth: 3, lowerWidth: 0, brightness: 0.48, lowerBrightness: 0,
        bodyColor: .redshift, highlightColor: .orange
    ),
    .idle
]

private let largeKeyframes: [ContourKeyframe] = [
    .idle,
    // F2-F5: disturbance A is one connected right-hand wedge.
    .init(
        wedge: [(216, 133), (228, 131), (244, 132), (254, 136), (244, 140), (228, 140), (216, 138)],
        primary: [(216, 136), (229, 134), (243, 134), (252, 136)],
        primaryWidth: 2, brightness: 0.62
    ),
    .init(
        wedge: [(214, 132), (228, 129), (246, 131), (256, 136), (246, 142), (227, 142), (214, 139)],
        primary: [(214, 136), (229, 133), (245, 133), (254, 136)],
        primaryWidth: 4, brightness: 0.76
    ),
    .init(
        wedge: [(212, 131), (228, 127), (248, 130), (258, 136), (248, 143), (227, 144), (212, 140)],
        primary: [(212, 136), (228, 132), (246, 132), (257, 136)],
        equator: [(190, 136), (212, 136), (232, 133), (260, 136), (288, 136)],
        primaryWidth: 5, brightness: 0.86
    ),
    .init(
        wedge: [(210, 130), (227, 125), (250, 129), (260, 136), (250, 145), (226, 146), (210, 140)],
        primary: [(210, 136), (228, 131), (248, 131), (259, 136)],
        equator: [(188, 136), (210, 136), (233, 132), (262, 136), (290, 136)],
        primaryWidth: 6, brightness: 0.94
    ),
    // F6-F9: A separates into asymmetric upper and compressed lower images.
    .init(
        primary: [(216, 136), (222, 126), (233, 119), (246, 121), (255, 129), (256, 136)],
        lowerLens: [(216, 136), (226, 143), (239, 147), (251, 142), (256, 136)],
        equator: [(184, 136), (216, 136), (238, 132), (260, 136), (292, 136)],
        primaryWidth: 7, lowerWidth: 3, brightness: 0.92, lowerBrightness: 0.34
    ),
    .init(
        primary: [(216, 136), (222, 123), (234, 114), (248, 118), (258, 128), (258, 136)],
        lowerLens: [(216, 136), (227, 145), (241, 150), (254, 143), (258, 136)],
        equator: [(182, 136), (216, 136), (239, 131), (262, 136), (294, 136)],
        primaryWidth: 8, lowerWidth: 4, brightness: 0.98, lowerBrightness: 0.38
    ),
    .init(
        primary: [(216, 136), (224, 121), (237, 112), (251, 117), (260, 128), (259, 136)],
        lowerLens: [(216, 136), (229, 146), (244, 151), (256, 143), (259, 136)],
        equator: [(180, 136), (216, 136), (240, 130), (264, 136), (296, 136)],
        primaryWidth: 9, lowerWidth: 4, brightness: 1.0, lowerBrightness: 0.40
    ),
    .init(
        primary: [(216, 136), (225, 122), (239, 113), (252, 119), (261, 130), (259, 136)],
        lowerLens: [(216, 136), (230, 147), (246, 151), (257, 142), (259, 136)],
        equator: [(178, 136), (216, 136), (241, 130), (265, 136), (296, 136)],
        primaryWidth: 9, lowerWidth: 4, brightness: 0.98, lowerBrightness: 0.38
    ),
    // F10-F13: disturbance B appears at the opposite connected disk root.
    .init(
        primary: [(216, 136), (225, 122), (239, 114), (252, 120), (260, 130), (259, 136)],
        equator: [(92, 136), (130, 136), (168, 137), (192, 134), (216, 136), (242, 131), (266, 136), (300, 136)],
        primaryWidth: 9, brightness: 0.96,
        secondary: [(168, 136), (158, 132), (146, 132), (136, 135), (130, 136)],
        secondaryWidth: 4, secondaryBrightness: 0.58
    ),
    .init(
        primary: [(216, 136), (226, 121), (240, 113), (253, 120), (261, 131), (259, 136)],
        equator: [(88, 136), (130, 136), (168, 138), (192, 133), (216, 136), (243, 130), (267, 136), (302, 136)],
        primaryWidth: 9, brightness: 0.98,
        secondary: [(168, 136), (159, 129), (147, 126), (136, 131), (130, 136)],
        secondaryWidth: 6, secondaryBrightness: 0.70
    ),
    .init(
        primary: [(216, 136), (227, 120), (241, 112), (254, 121), (262, 132), (259, 136)],
        equator: [(86, 136), (130, 136), (168, 139), (192, 132), (216, 136), (244, 129), (268, 136), (304, 136)],
        primaryWidth: 10, brightness: 1.0,
        secondary: [(168, 136), (160, 126), (148, 122), (136, 128), (130, 136)],
        secondaryWidth: 7, secondaryBrightness: 0.80, secondaryBodyColor: .amber
    ),
    .init(
        primary: [(216, 136), (228, 121), (242, 113), (255, 122), (262, 132), (259, 136)],
        equator: [(84, 136), (130, 136), (168, 140), (192, 132), (216, 136), (245, 129), (270, 136), (306, 136)],
        primaryWidth: 10, brightness: 0.98,
        secondary: [(168, 136), (160, 124), (147, 120), (135, 127), (130, 136)],
        secondaryWidth: 8, secondaryBrightness: 0.86, secondaryBodyColor: .amber
    ),
    // F14-F18: exactly one upper physical loop and one dim compressed lens.
    .init(
        primary: [(216, 136), (228, 122), (242, 116), (255, 124), (260, 136)],
        lowerLens: [(158, 136), (174, 153), (194, 164), (218, 161), (238, 149), (246, 136)],
        equator: [(82, 136), (130, 136), (158, 136), (192, 132), (216, 136), (246, 136), (274, 136), (308, 136)],
        primaryWidth: 9, lowerWidth: 4, brightness: 0.96, lowerBrightness: 0.30,
        secondary: [(168, 136), (158, 124), (145, 121), (133, 128), (130, 136)],
        loop: [(158, 136), (166, 112), (181, 92), (200, 82), (220, 86), (238, 105), (246, 136)],
        secondaryWidth: 8, loopWidth: 7, secondaryBrightness: 0.82, loopBrightness: 0.74
    ),
    .init(
        primary: [(216, 136), (229, 121), (244, 114), (257, 124), (261, 136)],
        lowerLens: [(158, 136), (174, 156), (195, 168), (220, 164), (240, 150), (246, 136)],
        equator: [(80, 136), (130, 136), (158, 136), (192, 131), (216, 136), (246, 136), (276, 136), (310, 136)],
        primaryWidth: 10, lowerWidth: 4, brightness: 0.98, lowerBrightness: 0.32,
        secondary: [(168, 136), (158, 122), (144, 119), (132, 127), (130, 136)],
        loop: [(158, 136), (165, 108), (180, 87), (200, 78), (221, 83), (239, 103), (246, 136)],
        secondaryWidth: 9, loopWidth: 8, secondaryBrightness: 0.86, loopBrightness: 0.84
    ),
    .init(
        primary: [(216, 136), (230, 120), (245, 113), (258, 124), (262, 136)],
        lowerLens: [(158, 136), (175, 158), (196, 170), (221, 166), (241, 150), (246, 136)],
        equator: [(78, 136), (130, 136), (158, 136), (192, 130), (216, 136), (246, 136), (278, 136), (312, 136)],
        primaryWidth: 10, lowerWidth: 4, brightness: 1.0, lowerBrightness: 0.34,
        secondary: [(168, 136), (157, 121), (143, 118), (131, 127), (130, 136)],
        loop: [(158, 136), (164, 105), (179, 84), (200, 76), (222, 81), (240, 102), (246, 136)],
        secondaryWidth: 9, loopWidth: 9, secondaryBrightness: 0.90, loopBrightness: 0.92
    ),
    .init(
        primary: [(216, 136), (231, 120), (246, 113), (259, 125), (262, 136)],
        lowerLens: [(158, 136), (176, 159), (198, 171), (223, 167), (242, 150), (246, 136)],
        equator: [(76, 136), (130, 136), (158, 136), (192, 129), (216, 136), (246, 136), (280, 136), (314, 136)],
        primaryWidth: 11, lowerWidth: 5, brightness: 1.0, lowerBrightness: 0.35,
        secondary: [(168, 136), (157, 120), (142, 118), (130, 127), (130, 136)],
        loop: [(158, 136), (164, 103), (179, 82), (201, 76), (223, 81), (241, 103), (246, 136)],
        secondaryWidth: 10, loopWidth: 9, secondaryBrightness: 0.92, loopBrightness: 0.96
    ),
    .init(
        primary: [(216, 136), (231, 121), (247, 114), (260, 126), (262, 136)],
        lowerLens: [(158, 136), (177, 158), (199, 170), (224, 166), (243, 149), (246, 136)],
        equator: [(74, 136), (130, 136), (158, 136), (192, 129), (216, 136), (246, 136), (282, 136), (316, 136)],
        primaryWidth: 11, lowerWidth: 5, brightness: 0.98, lowerBrightness: 0.34,
        secondary: [(168, 136), (156, 120), (141, 119), (129, 128), (130, 136)],
        loop: [(158, 136), (165, 104), (180, 82), (202, 77), (224, 82), (242, 104), (246, 136)],
        secondaryWidth: 10, loopWidth: 9, secondaryBrightness: 0.94, loopBrightness: 0.94
    ),
    // F19-F22: asymmetric climax; F20-F21 hold different sheared pixels.
    .init(
        primary: [(216, 136), (232, 119), (249, 112), (262, 125), (264, 136)],
        lowerLens: [(158, 136), (179, 158), (202, 169), (227, 164), (244, 148), (246, 136)],
        equator: [(72, 136), (130, 136), (158, 137), (192, 127), (216, 136), (246, 135), (284, 136), (318, 136)],
        primaryWidth: 12, lowerWidth: 5, brightness: 1.0, lowerBrightness: 0.32,
        secondary: [(168, 136), (155, 118), (139, 119), (127, 130), (130, 136)],
        loop: [(158, 136), (165, 102), (181, 80), (204, 76), (226, 83), (243, 105), (246, 136)],
        secondaryWidth: 11, loopWidth: 10, secondaryBrightness: 0.96, loopBrightness: 1.0,
        secondaryBodyColor: .orange
    ),
    .init(
        primary: [(216, 136), (233, 118), (250, 112), (263, 126), (264, 136)],
        lowerLens: [(158, 136), (180, 159), (203, 169), (228, 163), (245, 147), (246, 136)],
        equator: [(70, 136), (130, 136), (158, 138), (192, 126), (216, 136), (246, 134), (286, 136), (320, 136)],
        primaryWidth: 12, lowerWidth: 5, brightness: 1.0, lowerBrightness: 0.31,
        secondary: [(168, 136), (154, 117), (138, 120), (126, 131), (130, 136)],
        loop: [(158, 136), (166, 101), (183, 79), (206, 76), (228, 84), (244, 106), (246, 136)],
        secondaryWidth: 11, loopWidth: 10, secondaryBrightness: 0.98, loopBrightness: 1.0,
        secondaryBodyColor: .orange
    ),
    .init(
        primary: [(216, 136), (234, 118), (251, 113), (264, 127), (264, 136)],
        lowerLens: [(158, 136), (181, 158), (205, 168), (230, 162), (245, 146), (246, 136)],
        equator: [(68, 136), (130, 136), (158, 139), (192, 126), (216, 136), (246, 133), (288, 136), (322, 136)],
        primaryWidth: 12, lowerWidth: 5, brightness: 0.98, lowerBrightness: 0.30,
        secondary: [(168, 136), (153, 117), (137, 121), (125, 132), (130, 136)],
        loop: [(158, 136), (167, 102), (184, 80), (207, 77), (229, 85), (244, 107), (246, 136)],
        secondaryWidth: 11, loopWidth: 10, secondaryBrightness: 1.0, loopBrightness: 0.98,
        secondaryBodyColor: .orange
    ),
    .init(
        primary: [(216, 136), (235, 119), (252, 115), (265, 128), (264, 136)],
        lowerLens: [(158, 136), (182, 157), (206, 167), (231, 160), (245, 145), (246, 136)],
        equator: [(68, 136), (130, 136), (158, 140), (192, 127), (216, 136), (246, 132), (288, 136), (322, 136)],
        primaryWidth: 11, lowerWidth: 5, brightness: 0.94, lowerBrightness: 0.28,
        secondary: [(168, 136), (152, 118), (136, 123), (125, 133), (130, 136)],
        loop: [(158, 136), (168, 104), (185, 82), (208, 79), (230, 87), (244, 109), (246, 136)],
        secondaryWidth: 11, loopWidth: 9, secondaryBrightness: 0.96, loopBrightness: 0.94,
        secondaryBodyColor: .orange
    ),
    // F23-F27: the one loop flattens; both disturbances become rooted crescents.
    .init(
        primary: [(216, 136), (230, 125), (248, 122), (260, 130), (262, 136), (255, 144), (240, 145), (226, 138)],
        lowerLens: [(158, 136), (181, 151), (205, 158), (229, 153), (246, 136)],
        equator: [(70, 136), (130, 136), (158, 141), (192, 128), (216, 136), (246, 131), (286, 136), (320, 136)],
        primaryWidth: 10, lowerWidth: 4, brightness: 0.90, lowerBrightness: 0.25,
        secondary: [(168, 136), (158, 124), (142, 122), (130, 130), (128, 136), (136, 144), (151, 146), (164, 139)],
        loop: [(158, 136), (174, 111), (193, 94), (214, 91), (233, 107), (246, 136)],
        secondaryWidth: 10, loopWidth: 8, secondaryBrightness: 0.90, loopBrightness: 0.82,
        bodyColor: .amber, highlightColor: .gold, secondaryBodyColor: .orange
    ),
    .init(
        primary: [(218, 136), (232, 127), (249, 125), (259, 132), (260, 136), (253, 143), (239, 143), (228, 138)],
        lowerLens: [(158, 136), (182, 148), (206, 153), (230, 149), (246, 136)],
        equator: [(72, 136), (130, 136), (158, 140), (192, 130), (218, 136), (246, 132), (284, 136), (318, 136)],
        primaryWidth: 9, lowerWidth: 4, brightness: 0.84, lowerBrightness: 0.23,
        secondary: [(166, 136), (156, 126), (142, 125), (131, 131), (130, 136), (138, 143), (151, 144), (162, 139)],
        loop: [(158, 136), (176, 116), (195, 102), (216, 100), (234, 114), (246, 136)],
        secondaryWidth: 9, loopWidth: 7, secondaryBrightness: 0.84, loopBrightness: 0.72,
        bodyColor: .amber, highlightColor: .gold, secondaryBodyColor: .orange
    ),
    .init(
        primary: [(220, 136), (234, 129), (250, 128), (258, 134), (259, 136), (251, 142), (239, 141), (230, 137)],
        lowerLens: [(160, 136), (184, 145), (207, 149), (231, 146), (246, 136)],
        equator: [(76, 136), (132, 136), (160, 139), (192, 131), (220, 136), (246, 133), (282, 136), (316, 136)],
        primaryWidth: 8, lowerWidth: 3, brightness: 0.76, lowerBrightness: 0.20,
        secondary: [(164, 136), (154, 128), (142, 128), (133, 133), (132, 136), (140, 142), (152, 142), (160, 138)],
        loop: [(160, 136), (178, 121), (197, 111), (217, 110), (235, 121), (246, 136)],
        secondaryWidth: 8, loopWidth: 6, secondaryBrightness: 0.76, loopBrightness: 0.60,
        bodyColor: .orange, highlightColor: .amber, secondaryBodyColor: .orange
    ),
    .init(
        primary: [(222, 136), (236, 131), (250, 131), (257, 135), (257, 137), (249, 141), (239, 139), (232, 136)],
        lowerLens: [(164, 136), (186, 142), (208, 145), (231, 143), (246, 136)],
        equator: [(80, 136), (134, 136), (164, 138), (192, 132), (222, 136), (246, 134), (280, 136), (312, 136)],
        primaryWidth: 7, lowerWidth: 3, brightness: 0.66, lowerBrightness: 0.18,
        secondary: [(162, 136), (151, 130), (141, 131), (135, 135), (136, 138), (145, 141), (156, 139)],
        loop: [(164, 136), (182, 126), (201, 120), (220, 120), (237, 128), (246, 136)],
        secondaryWidth: 7, loopWidth: 5, secondaryBrightness: 0.66, loopBrightness: 0.48,
        bodyColor: .orange, highlightColor: .amber, secondaryBodyColor: .orange
    ),
    .init(
        primary: [(226, 136), (239, 133), (251, 134), (255, 136), (249, 140), (239, 138), (232, 136)],
        lowerLens: [(170, 136), (190, 140), (211, 142), (232, 140), (246, 136)],
        equator: [(86, 136), (138, 136), (170, 137), (192, 133), (226, 136), (246, 135), (276, 136), (306, 136)],
        primaryWidth: 6, lowerWidth: 2, brightness: 0.56, lowerBrightness: 0.14,
        secondary: [(158, 136), (148, 133), (140, 134), (138, 136), (144, 139), (154, 138)],
        loop: [(170, 136), (188, 131), (207, 128), (225, 130), (240, 134), (246, 136)],
        secondaryWidth: 6, loopWidth: 4, secondaryBrightness: 0.56, loopBrightness: 0.36,
        bodyColor: .orange, highlightColor: .amber, secondaryBodyColor: .orange
    ),
    // F28-F29: both disturbances retract into opposite disk roots.
    .init(
        primary: [(230, 136), (241, 133), (251, 135), (253, 136), (246, 139), (237, 138), (232, 136)],
        equator: [(92, 136), (142, 136), (176, 136), (192, 134), (230, 136), (252, 136), (272, 136), (302, 136)],
        primaryWidth: 5, brightness: 0.46,
        secondary: [(154, 136), (146, 134), (138, 136), (145, 138), (152, 137)],
        secondaryWidth: 5, secondaryBrightness: 0.46,
        bodyColor: .redshift, highlightColor: .orange, secondaryBodyColor: .orange, secondaryHighlightColor: .amber
    ),
    .init(
        primary: [(236, 136), (244, 134), (250, 136), (244, 138), (238, 136)],
        equator: [(100, 136), (148, 136), (180, 136), (192, 135), (236, 136), (250, 136), (268, 136), (296, 136)],
        primaryWidth: 3, brightness: 0.32,
        secondary: [(150, 136), (144, 135), (140, 136), (145, 137), (150, 136)],
        secondaryWidth: 3, secondaryBrightness: 0.32,
        bodyColor: .redshift, highlightColor: .orange, secondaryBodyColor: .orange, secondaryHighlightColor: .amber
    ),
    .idle
]

private let lastLightKeyframes: [ContourKeyframe] = [
    .idle,
    // F2-F6: one tethered white-gold bulge grows from the right disk root.
    .init(
        wedge: [(220, 133), (232, 131), (244, 132), (252, 136), (244, 140), (232, 140), (220, 138)],
        primary: [(220, 136), (232, 134), (244, 134), (251, 136)],
        primaryWidth: 2, brightness: 0.60
    ),
    .init(
        wedge: [(218, 132), (232, 129), (247, 131), (254, 136), (247, 142), (231, 142), (218, 139)],
        primary: [(218, 136), (232, 133), (246, 133), (253, 136)],
        primaryWidth: 4, brightness: 0.72
    ),
    .init(
        wedge: [(216, 131), (232, 127), (249, 130), (256, 136), (249, 144), (231, 144), (216, 140)],
        primary: [(216, 136), (231, 132), (248, 132), (255, 136)],
        equator: [(196, 136), (216, 136), (238, 133), (258, 136), (284, 136)],
        primaryWidth: 5, brightness: 0.82
    ),
    .init(
        wedge: [(214, 130), (231, 125), (250, 129), (258, 136), (250, 145), (230, 146), (214, 140)],
        primary: [(214, 136), (231, 131), (249, 131), (257, 136)],
        equator: [(194, 136), (214, 136), (239, 132), (260, 136), (286, 136)],
        primaryWidth: 6, brightness: 0.90
    ),
    .init(
        wedge: [(212, 129), (230, 124), (251, 128), (260, 136), (251, 146), (229, 147), (212, 140)],
        primary: [(212, 136), (230, 130), (250, 130), (259, 136)],
        equator: [(192, 136), (212, 136), (240, 131), (262, 136), (288, 136)],
        primaryWidth: 7, brightness: 0.96
    ),
    // F7-F12: an approaching orbital ribbon remains rooted at the equator.
    .init(
        primary: [(220, 136), (228, 126), (240, 120), (252, 122), (260, 130), (260, 136)],
        lowerLens: [(220, 136), (231, 143), (244, 146), (256, 141), (260, 136)],
        equator: [(188, 136), (220, 136), (242, 132), (264, 136), (292, 136)],
        primaryWidth: 7, lowerWidth: 3, brightness: 0.94, lowerBrightness: 0.30
    ),
    .init(
        primary: [(218, 136), (225, 123), (238, 114), (252, 117), (262, 128), (262, 136)],
        lowerLens: [(218, 136), (230, 145), (245, 149), (258, 142), (262, 136)],
        equator: [(186, 136), (218, 136), (242, 131), (266, 136), (294, 136)],
        primaryWidth: 8, lowerWidth: 3, brightness: 0.98, lowerBrightness: 0.32
    ),
    .init(
        primary: [(216, 136), (222, 119), (236, 108), (252, 112), (264, 126), (264, 136)],
        lowerLens: [(216, 136), (229, 147), (246, 152), (260, 143), (264, 136)],
        equator: [(184, 136), (216, 136), (242, 130), (268, 136), (296, 136)],
        primaryWidth: 9, lowerWidth: 4, brightness: 1.0, lowerBrightness: 0.34
    ),
    .init(
        primary: [(214, 136), (219, 116), (233, 103), (250, 106), (264, 123), (266, 136)],
        lowerLens: [(214, 136), (228, 149), (246, 155), (262, 144), (266, 136)],
        equator: [(182, 136), (214, 136), (241, 129), (270, 136), (298, 136)],
        primaryWidth: 10, lowerWidth: 4, brightness: 1.0, lowerBrightness: 0.36,
        bodyColor: .gold, highlightColor: .white
    ),
    .init(
        primary: [(212, 136), (216, 112), (230, 98), (248, 101), (264, 120), (268, 136)],
        lowerLens: [(212, 136), (227, 151), (247, 158), (264, 145), (268, 136)],
        equator: [(180, 136), (212, 136), (240, 128), (272, 136), (300, 136)],
        primaryWidth: 10, lowerWidth: 4, brightness: 0.98, lowerBrightness: 0.36,
        bodyColor: .amber, highlightColor: .gold
    ),
    .init(
        primary: [(210, 136), (213, 108), (227, 93), (246, 96), (264, 117), (270, 136)],
        lowerLens: [(210, 136), (226, 153), (248, 160), (266, 146), (270, 136)],
        equator: [(178, 136), (210, 136), (239, 127), (274, 136), (302, 136)],
        primaryWidth: 11, lowerWidth: 4, brightness: 0.96, lowerBrightness: 0.35,
        bodyColor: .amber, highlightColor: .gold
    ),
    // F13-F18: the same tether passes the far side as unequal upper/lower images.
    .init(
        primary: [(246, 136), (254, 116), (250, 98), (238, 83), (221, 74), (202, 72), (184, 80)],
        lowerLens: [(246, 136), (238, 151), (224, 162), (207, 166), (190, 159), (180, 148)],
        equator: [(82, 136), (130, 136), (180, 136), (210, 132), (246, 136), (276, 136), (308, 136)],
        primaryWidth: 11, lowerWidth: 4, brightness: 0.94, lowerBrightness: 0.34,
        bodyColor: .amber, highlightColor: .gold
    ),
    .init(
        primary: [(246, 136), (255, 114), (250, 94), (236, 79), (218, 70), (198, 69), (178, 78), (170, 88)],
        lowerLens: [(246, 136), (238, 153), (223, 165), (204, 169), (186, 161), (174, 148)],
        equator: [(80, 136), (128, 136), (174, 136), (208, 131), (246, 136), (278, 136), (310, 136)],
        primaryWidth: 12, lowerWidth: 4, brightness: 0.92, lowerBrightness: 0.34,
        bodyColor: .amber, highlightColor: .gold
    ),
    .init(
        primary: [(246, 136), (256, 112), (250, 91), (234, 75), (214, 67), (192, 68), (172, 78), (160, 92)],
        lowerLens: [(246, 136), (238, 155), (222, 168), (202, 172), (182, 162), (166, 147)],
        equator: [(78, 136), (126, 136), (166, 136), (206, 130), (246, 136), (280, 136), (312, 136)],
        primaryWidth: 12, lowerWidth: 5, brightness: 0.90, lowerBrightness: 0.33,
        bodyColor: .amber, highlightColor: .gold
    ),
    .init(
        primary: [(246, 136), (257, 110), (250, 88), (232, 72), (210, 65), (187, 68), (166, 80), (151, 98), (148, 136)],
        lowerLens: [(246, 136), (238, 157), (220, 171), (199, 175), (178, 164), (160, 148), (148, 136)],
        equator: [(76, 136), (124, 136), (148, 136), (204, 129), (246, 136), (282, 136), (314, 136)],
        primaryWidth: 13, lowerWidth: 5, brightness: 0.88, lowerBrightness: 0.32,
        bodyColor: .amber, highlightColor: .gold
    ),
    .init(
        primary: [(248, 136), (258, 109), (251, 86), (232, 70), (209, 64), (185, 69), (163, 82), (148, 101), (146, 136)],
        lowerLens: [(248, 136), (239, 158), (220, 173), (197, 176), (175, 164), (157, 147), (146, 136)],
        equator: [(74, 136), (122, 136), (146, 136), (202, 128), (248, 136), (284, 136), (316, 136)],
        primaryWidth: 13, lowerWidth: 5, brightness: 0.84, lowerBrightness: 0.30,
        bodyColor: .orange, highlightColor: .amber
    ),
    .init(
        primary: [(250, 136), (259, 108), (252, 85), (233, 69), (209, 64), (183, 70), (160, 84), (145, 104), (144, 136)],
        lowerLens: [(250, 136), (240, 159), (220, 174), (195, 177), (172, 164), (154, 146), (144, 136)],
        equator: [(72, 136), (120, 136), (144, 136), (200, 128), (250, 136), (286, 136), (318, 136)],
        primaryWidth: 13, lowerWidth: 5, brightness: 0.80, lowerBrightness: 0.28,
        bodyColor: .orange, highlightColor: .amber
    ),
    // F19-F24: a receding orange-red crescent lengthens around the disk.
    .init(
        primary: [(254, 136), (252, 110), (240, 86), (219, 69), (194, 63), (169, 69), (148, 85), (134, 108), (131, 136), (137, 161), (151, 180), (170, 192)],
        lowerLens: [(254, 136), (247, 153), (236, 169), (220, 180)],
        equator: [(68, 136), (116, 136), (132, 136), (194, 127), (254, 136), (288, 136), (320, 136)],
        primaryWidth: 13, lowerWidth: 4, brightness: 0.76, lowerBrightness: 0.24,
        bodyColor: .orange, highlightColor: .amber
    ),
    .init(
        primary: [(256, 136), (254, 108), (241, 83), (219, 66), (193, 60), (166, 67), (144, 84), (130, 108), (127, 137), (134, 164), (150, 185), (172, 198), (193, 201)],
        lowerLens: [(256, 136), (249, 154), (237, 171), (220, 183)],
        equator: [(66, 136), (114, 136), (128, 136), (192, 126), (256, 136), (290, 136), (322, 136)],
        primaryWidth: 13, lowerWidth: 4, brightness: 0.72, lowerBrightness: 0.22,
        bodyColor: .orange, highlightColor: .amber
    ),
    .init(
        primary: [(258, 136), (256, 106), (242, 80), (219, 63), (192, 58), (164, 66), (141, 84), (126, 110), (124, 139), (132, 167), (149, 189), (173, 202), (198, 204), (220, 197)],
        lowerLens: [(258, 136), (251, 155), (239, 173), (221, 186)],
        equator: [(64, 136), (112, 136), (126, 136), (190, 125), (258, 136), (292, 136), (324, 136)],
        primaryWidth: 14, lowerWidth: 4, brightness: 0.68, lowerBrightness: 0.20,
        bodyColor: .orange, highlightColor: .amber
    ),
    .init(
        primary: [(260, 136), (258, 104), (243, 78), (219, 61), (191, 57), (162, 65), (138, 84), (123, 111), (121, 141), (130, 170), (148, 192), (174, 205), (201, 206), (225, 197), (243, 182)],
        lowerLens: [(260, 136), (253, 156), (240, 175), (222, 188)],
        equator: [(62, 136), (110, 136), (124, 136), (188, 124), (260, 136), (294, 136), (326, 136)],
        primaryWidth: 14, lowerWidth: 4, brightness: 0.64, lowerBrightness: 0.18,
        bodyColor: .orange, highlightColor: .redshift
    ),
    .init(
        primary: [(262, 136), (260, 102), (244, 75), (219, 59), (190, 56), (160, 64), (136, 84), (120, 112), (119, 143), (128, 172), (147, 195), (175, 208), (203, 208), (228, 198), (247, 180), (258, 158)],
        lowerLens: [(262, 136), (255, 158), (242, 177), (223, 190)],
        equator: [(60, 136), (108, 136), (122, 136), (186, 123), (262, 136), (296, 136), (328, 136)],
        primaryWidth: 14, lowerWidth: 4, brightness: 0.60, lowerBrightness: 0.16,
        bodyColor: .redshift, highlightColor: .orange
    ),
    .init(
        primary: [(264, 136), (261, 100), (245, 73), (219, 58), (189, 55), (158, 64), (133, 85), (117, 114), (117, 145), (127, 175), (147, 198), (176, 211), (205, 211), (231, 199), (250, 179), (261, 156)],
        lowerLens: [(264, 136), (257, 159), (244, 179), (224, 192)],
        equator: [(58, 136), (106, 136), (120, 136), (184, 122), (264, 136), (298, 136), (330, 136)],
        primaryWidth: 14, lowerWidth: 4, brightness: 0.56, lowerBrightness: 0.14,
        bodyColor: .redshift, highlightColor: .orange
    ),
    // F25-F30: the tethered crescent reaches 85-90% orbit and redshifts.
    .init(
        primary: [(266, 136), (263, 98), (246, 71), (219, 56), (188, 54), (156, 64), (131, 86), (115, 116), (115, 148), (126, 178), (147, 201), (177, 214), (207, 213), (234, 200), (253, 178), (264, 153)],
        equator: [(56, 136), (104, 136), (118, 136), (182, 122), (266, 136), (300, 136), (332, 136)],
        primaryWidth: 15, brightness: 0.64, bodyColor: .magenta, highlightColor: .orange,
        lowerBodyColor: .magenta, lowerHighlightColor: .orange
    ),
    .init(
        primary: [(268, 136), (265, 96), (247, 69), (219, 54), (187, 53), (154, 64), (128, 87), (112, 118), (113, 151), (125, 181), (147, 204), (178, 217), (209, 215), (237, 201), (256, 177), (267, 151)],
        equator: [(54, 136), (102, 136), (116, 136), (180, 121), (268, 136), (302, 136), (334, 136)],
        primaryWidth: 15, brightness: 0.68, bodyColor: .magenta, highlightColor: .redshift
    ),
    .init(
        primary: [(270, 136), (267, 94), (248, 67), (219, 53), (186, 52), (152, 64), (126, 88), (110, 120), (112, 153), (124, 184), (147, 207), (179, 220), (211, 218), (240, 202), (259, 176), (269, 149)],
        equator: [(52, 136), (100, 136), (114, 136), (178, 120), (270, 136), (304, 136), (334, 136)],
        primaryWidth: 16, brightness: 0.72, bodyColor: .magenta, highlightColor: .violet
    ),
    .init(
        primary: [(272, 136), (269, 92), (249, 65), (219, 52), (185, 51), (150, 64), (124, 89), (108, 122), (110, 156), (123, 187), (147, 210), (180, 223), (213, 220), (242, 203), (262, 175), (271, 147)],
        equator: [(50, 136), (98, 136), (112, 136), (176, 119), (272, 136), (306, 136), (334, 136)],
        primaryWidth: 16, brightness: 0.76, bodyColor: .violet, highlightColor: .magenta
    ),
    .init(
        primary: [(274, 136), (271, 90), (250, 63), (219, 51), (184, 50), (148, 64), (122, 90), (106, 124), (108, 158), (122, 190), (147, 213), (181, 226), (215, 222), (245, 204), (265, 174), (273, 145)],
        equator: [(50, 136), (96, 136), (110, 136), (174, 118), (274, 136), (308, 136), (334, 136)],
        primaryWidth: 16, brightness: 0.80, bodyColor: .violet, highlightColor: .magenta
    ),
    .init(
        primary: [(275, 136), (272, 89), (251, 62), (220, 50), (184, 51), (148, 65), (121, 91), (105, 125), (108, 160), (122, 191), (148, 214), (182, 227), (216, 223), (246, 205), (266, 175), (274, 145)],
        equator: [(50, 136), (95, 136), (109, 136), (173, 117), (275, 136), (309, 136), (334, 136)],
        primaryWidth: 16, brightness: 0.80, bodyColor: .violet, highlightColor: .magenta
    ),
    // F31-F35: one broad connected equatorial ribbon covers the source-to-zero handoff.
    .init(
        primary: [(274, 136), (263, 113), (248, 99), (235, 105), (242, 126), (256, 142)],
        equator: [(50, 136), (102, 136), (150, 133), (192, 140), (236, 132), (282, 136), (334, 136)],
        primaryWidth: 14, brightness: 0.88, equatorWidth: 18,
        bodyColor: .violet, highlightColor: .magenta
    ),
    .init(
        primary: [(272, 136), (261, 114), (247, 101), (234, 107), (241, 128), (255, 142)],
        equator: [(50, 136), (101, 136), (149, 132), (192, 141), (237, 131), (283, 136), (334, 136)],
        primaryWidth: 14, brightness: 0.90, equatorWidth: 18,
        bodyColor: .violet, highlightColor: .magenta
    ),
    .init(
        primary: [(270, 136), (259, 116), (246, 103), (233, 109), (240, 129), (253, 142)],
        equator: [(50, 136), (100, 136), (148, 131), (192, 142), (238, 130), (284, 136), (334, 136)],
        primaryWidth: 13, brightness: 0.92, equatorWidth: 18,
        bodyColor: .violet, highlightColor: .magenta
    ),
    .init(
        primary: [(268, 136), (257, 118), (245, 105), (232, 111), (239, 131), (251, 142)],
        equator: [(50, 136), (99, 136), (147, 130), (192, 143), (239, 129), (285, 136), (334, 136)],
        primaryWidth: 12, brightness: 0.88, equatorWidth: 17,
        bodyColor: .violet, highlightColor: .magenta
    ),
    .init(
        primary: [(266, 136), (255, 120), (244, 108), (231, 113), (238, 132), (249, 141)],
        equator: [(52, 136), (100, 136), (146, 130), (192, 142), (240, 129), (286, 136), (332, 136)],
        primaryWidth: 11, brightness: 0.82, equatorWidth: 16,
        bodyColor: .violet, highlightColor: .magenta
    ),
    // F36-F39: the covered ribbon retracts into the canonical zero disk.
    .init(
        primary: [(262, 136), (252, 121), (241, 111), (230, 116), (237, 133), (247, 140)],
        equator: [(56, 136), (104, 136), (148, 131), (192, 141), (238, 130), (282, 136), (328, 136)],
        primaryWidth: 10, brightness: 0.74, equatorWidth: 14,
        bodyColor: .violet, highlightColor: .magenta
    ),
    .init(
        primary: [(258, 136), (249, 123), (239, 114), (229, 119), (236, 134), (245, 139)],
        equator: [(62, 136), (110, 136), (152, 132), (192, 140), (236, 131), (278, 136), (322, 136)],
        primaryWidth: 9, brightness: 0.64, equatorWidth: 12,
        bodyColor: .violet, highlightColor: .magenta
    ),
    .init(
        primary: [(250, 136), (244, 126), (235, 120), (228, 123), (234, 135), (242, 138)],
        equator: [(72, 136), (118, 136), (158, 133), (192, 139), (232, 132), (272, 136), (314, 136)],
        primaryWidth: 7, brightness: 0.52, bodyColor: .violet, highlightColor: .magenta
    ),
    .init(
        primary: [(240, 136), (235, 130), (229, 128), (226, 132), (231, 136), (237, 137)],
        equator: [(84, 136), (128, 136), (166, 134), (192, 138), (228, 133), (264, 136), (304, 136)],
        primaryWidth: 4, brightness: 0.34, bodyColor: .violet, highlightColor: .magenta
    ),
    .idle
]

private func pixelPath(_ points: [PixelPoint], closes: Bool = false) -> CGPath {
    let path = CGMutablePath()
    guard let first = points.first else { return path }
    path.move(to: CGPoint(x: first.x, y: Int(canvasSize.height) - first.y))
    for point in points.dropFirst() {
        path.addLine(to: CGPoint(x: point.x, y: Int(canvasSize.height) - point.y))
    }
    if closes { path.closeSubpath() }
    return path
}

private func drawPixelBand(
    _ points: [PixelPoint],
    width: CGFloat,
    brightness: CGFloat,
    bodyColor: PixelColor,
    highlightColor: PixelColor,
    in context: CGContext
) {
    guard points.count > 1, width >= 2, brightness > 0 else { return }
    context.setLineCap(.butt)
    context.setLineJoin(.miter)

    context.addPath(pixelPath(points))
    context.setStrokeColor(
        red: bodyColor.red,
        green: bodyColor.green,
        blue: bodyColor.blue,
        alpha: 0.16 * brightness
    )
    context.setLineWidth(width + 6)
    context.strokePath()

    context.addPath(pixelPath(points))
    context.setStrokeColor(
        red: bodyColor.red,
        green: bodyColor.green,
        blue: bodyColor.blue,
        alpha: 0.88 * brightness
    )
    context.setLineWidth(width)
    context.strokePath()

    context.addPath(pixelPath(points))
    context.setStrokeColor(
        red: highlightColor.red,
        green: highlightColor.green,
        blue: highlightColor.blue,
        alpha: 0.94 * brightness
    )
    context.setLineWidth(2)
    context.strokePath()
}

private func drawPixelWedge(_ keyframe: ContourKeyframe, in context: CGContext) {
    guard keyframe.wedge.count > 2 else { return }
    context.addPath(pixelPath(keyframe.wedge, closes: true))
    context.setFillColor(
        red: keyframe.bodyColor.red,
        green: keyframe.bodyColor.green,
        blue: keyframe.bodyColor.blue,
        alpha: 0.88 * keyframe.brightness
    )
    context.fillPath()
}

private func authoredContourFrame(
    index: Int,
    keyframes: [ContourKeyframe],
    base: CGImage
) throws -> CGImage {
    guard index > 0, index < keyframes.count - 1 else { return base }
    let keyframe = keyframes[index]
    let context = try makeContext()
    drawBase(base, in: context)
    drawPixelWedge(keyframe, in: context)
    drawPixelBand(
        keyframe.equator,
        width: keyframe.equatorWidth,
        brightness: keyframe.brightness,
        bodyColor: keyframe.bodyColor,
        highlightColor: keyframe.highlightColor,
        in: context
    )
    drawPixelBand(
        keyframe.lowerLens,
        width: keyframe.lowerWidth,
        brightness: keyframe.lowerBrightness,
        bodyColor: keyframe.lowerBodyColor,
        highlightColor: keyframe.lowerHighlightColor,
        in: context
    )
    drawPixelBand(
        keyframe.secondary,
        width: keyframe.secondaryWidth,
        brightness: keyframe.secondaryBrightness,
        bodyColor: keyframe.secondaryBodyColor,
        highlightColor: keyframe.secondaryHighlightColor,
        in: context
    )
    drawPixelBand(
        keyframe.loop,
        width: keyframe.loopWidth,
        brightness: keyframe.loopBrightness,
        bodyColor: keyframe.loopBodyColor,
        highlightColor: keyframe.loopHighlightColor,
        in: context
    )
    drawPixelBand(
        keyframe.primary,
        width: keyframe.primaryWidth,
        brightness: keyframe.brightness,
        bodyColor: keyframe.bodyColor,
        highlightColor: keyframe.highlightColor,
        in: context
    )
    restoreShadow(from: base, in: context)
    guard let image = context.makeImage(),
          let source = CGImageSourceCreateWithData(try pngData(for: image) as CFData, nil),
          let detached = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw CocoaError(.coderInvalidValue)
    }
    return detached
}

private func authoredFrame(
    kind: MasterKind,
    index: Int,
    base50: CGImage,
    base10: CGImage,
    base0: CGImage
) throws -> CGImage {
    switch kind {
    case .small:
        precondition(smallKeyframes.count == kind.frameCount)
        return try authoredContourFrame(index: index, keyframes: smallKeyframes, base: base50)
    case .medium:
        precondition(mediumKeyframes.count == kind.frameCount)
        return try authoredContourFrame(index: index, keyframes: mediumKeyframes, base: base50)
    case .large:
        precondition(largeKeyframes.count == kind.frameCount)
        return try authoredContourFrame(index: index, keyframes: largeKeyframes, base: base50)
    case .lastLight:
        precondition(lastLightKeyframes.count == kind.frameCount)
        let base = index >= 32 ? base0 : base10
        return try authoredContourFrame(index: index, keyframes: lastLightKeyframes, base: base)
    }
}

private struct PNGChunk {
    let type: String
    let payload: Data
}

private func appendBigEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
    var value = value.bigEndian
    withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
}

private func crc32(_ data: Data) -> UInt32 {
    var crc = UInt32.max
    for byte in data {
        crc ^= UInt32(byte)
        for _ in 0..<8 {
            crc = (crc >> 1) ^ (0xEDB8_8320 & (0 &- (crc & 1)))
        }
    }
    return ~crc
}

private func appendChunk(type: String, payload: Data, to data: inout Data) {
    let typeData = Data(type.utf8)
    appendBigEndian(UInt32(payload.count), to: &data)
    data.append(typeData)
    data.append(payload)
    appendBigEndian(crc32(typeData + payload), to: &data)
}

private func pngData(for image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    return data as Data
}

private func chunks(in png: Data) throws -> [PNGChunk] {
    let signature = Data([137, 80, 78, 71, 13, 10, 26, 10])
    guard png.starts(with: signature) else { throw CocoaError(.fileReadCorruptFile) }
    var offset = signature.count
    var result: [PNGChunk] = []
    while offset + 12 <= png.count {
        let length = png[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let payloadStart = offset + 8
        let payloadEnd = payloadStart + Int(length)
        guard payloadEnd + 4 <= png.count,
              let type = String(data: png[(offset + 4)..<(offset + 8)], encoding: .ascii) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        result.append(PNGChunk(type: type, payload: png[payloadStart..<payloadEnd]))
        offset = payloadEnd + 4
        if type == "IEND" { break }
    }
    return result
}

private func frameControl(
    sequence: UInt32,
    delayNumerator: UInt16 = 1,
    delayDenominator: UInt16 = 24
) -> Data {
    var data = Data()
    appendBigEndian(sequence, to: &data)
    appendBigEndian(UInt32(canvasSize.width), to: &data)
    appendBigEndian(UInt32(canvasSize.height), to: &data)
    appendBigEndian(UInt32(0), to: &data)
    appendBigEndian(UInt32(0), to: &data)
    appendBigEndian(delayNumerator, to: &data)
    appendBigEndian(delayDenominator, to: &data)
    data.append(0) // Keep the previous full-canvas frame until the next slot.
    data.append(0) // Replace the canvas; every authored slot is self-contained.
    return data
}

private func apngData(
    _ frames: [CGImage],
    delayNumerator: UInt16 = 1,
    delayDenominator: UInt16 = 24
) throws -> Data {
    let encoded = try frames.map { try chunks(in: pngData(for: $0)) }
    guard let first = encoded.first,
          let header = first.first(where: { $0.type == "IHDR" }) else {
        throw CocoaError(.fileReadCorruptFile)
    }

    var output = Data([137, 80, 78, 71, 13, 10, 26, 10])
    appendChunk(type: "IHDR", payload: header.payload, to: &output)
    for chunk in first where !["IHDR", "IDAT", "IEND"].contains(chunk.type) {
        appendChunk(type: chunk.type, payload: chunk.payload, to: &output)
    }
    var animationControl = Data()
    appendBigEndian(UInt32(frames.count), to: &animationControl)
    appendBigEndian(UInt32(1), to: &animationControl)
    appendChunk(type: "acTL", payload: animationControl, to: &output)

    var sequence = UInt32(0)
    for (index, frameChunks) in encoded.enumerated() {
        appendChunk(
            type: "fcTL",
            payload: frameControl(
                sequence: sequence,
                delayNumerator: delayNumerator,
                delayDenominator: delayDenominator
            ),
            to: &output
        )
        sequence += 1
        for chunk in frameChunks where chunk.type == "IDAT" {
            if index == 0 {
                appendChunk(type: "IDAT", payload: chunk.payload, to: &output)
            } else {
                var payload = Data()
                appendBigEndian(sequence, to: &payload)
                payload.append(chunk.payload)
                appendChunk(type: "fdAT", payload: payload, to: &output)
                sequence += 1
            }
        }
    }
    appendChunk(type: "IEND", payload: Data(), to: &output)
    return output
}

private func writeAPNG(_ frames: [CGImage], kind: MasterKind) throws {
    let output = try apngData(frames)
    let url = framesDirectory.appendingPathComponent("quota-consumption-master-\(kind.rawValue).apng")
    try output.write(to: url, options: .atomic)
}

private struct Manifest: Codable {
    let version: Int
    let frameRate: Int
    let entries: [Entry]

    struct Entry: Codable {
        let kind: String
        let bucket: Int
        let phase: Int
        let path: String
        let frameCount: Int
        let duration: Double
    }
}

private func productionFrames(
    kind: MasterKind,
    bucket: Int,
    phase: Int,
    bases: [Int: [CGImage]]
) throws -> [CGImage] {
    guard let capturedBase = bases[bucket]?[phase],
          let zeroBase = bases[0]?[phase] else {
        throw CocoaError(.fileReadCorruptFile)
    }
    precondition(kind.keyframes.count == kind.frameCount)
    return try (0..<kind.frameCount).map { index in
        let base = kind == .lastLight && index >= 32 ? zeroBase : capturedBase
        return try authoredContourFrame(index: index, keyframes: kind.keyframes, base: base)
    }
}

private func productionFileName(kind: MasterKind, bucket: Int, phase: Int) -> String {
    "quota-consumption-\(kind.rawValue)-bucket-\(bucket)-phase-\(phase).apng"
}

private func bakeProduction(kinds: [MasterKind]) throws {
    try FileManager.default.createDirectory(
        at: consumptionDirectory,
        withIntermediateDirectories: true
    )
    let bases = try Dictionary(uniqueKeysWithValues: stride(from: 0, through: 100, by: 10).map { bucket in
        (bucket, try (0..<6).map { try loadImage(named: "quota-\(bucket)-frame-\($0).png") })
    })

    for kind in kinds {
        for bucket in stride(from: 0, through: 100, by: 10) {
            for phase in 0..<6 {
                let frames = try productionFrames(
                    kind: kind,
                    bucket: bucket,
                    phase: phase,
                    bases: bases
                )
                let name = productionFileName(kind: kind, bucket: bucket, phase: phase)
                try apngData(frames).write(
                    to: consumptionDirectory.appendingPathComponent(name),
                    options: .atomic
                )
            }
        }
        print("Baked \(kind.rawValue): 66 variants")
    }

    guard kinds.count == MasterKind.allCases.count else { return }
    let entries = MasterKind.allCases.flatMap { kind in
        stride(from: 0, through: 100, by: 10).flatMap { bucket in
            (0..<6).map { phase in
                let name = productionFileName(kind: kind, bucket: bucket, phase: phase)
                return Manifest.Entry(
                    kind: kind.rawValue,
                    bucket: bucket,
                    phase: phase,
                    path: name,
                    frameCount: kind.frameCount,
                    duration: Double(kind.frameCount) / 24.0
                )
            }
        }
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(Manifest(version: 1, frameRate: 24, entries: entries)).write(
        to: consumptionDirectory.appendingPathComponent("manifest.json"),
        options: .atomic
    )
}

private func reduceMotionFrames() throws -> [CGImage] {
    let levels: [CGFloat] = [0.44, 0.76, 0.52]
    return try levels.map { brightness in
        let context = try makeContext()
        let keyframe = ContourKeyframe(
            wedge: [(216, 132), (228, 129), (244, 131), (252, 136), (244, 142), (228, 143), (216, 139)],
            primary: [(216, 136), (229, 133), (244, 133), (252, 136)],
            primaryWidth: 4,
            brightness: brightness
        )
        drawPixelWedge(keyframe, in: context)
        drawPixelBand(
            keyframe.primary,
            width: keyframe.primaryWidth,
            brightness: keyframe.brightness,
            bodyColor: keyframe.bodyColor,
            highlightColor: keyframe.highlightColor,
            in: context
        )
        context.saveGState()
        context.setBlendMode(.clear)
        context.fillEllipse(in: CGRect(x: 148, y: 92, width: 88, height: 88))
        context.restoreGState()
        guard let image = context.makeImage() else { throw CocoaError(.coderInvalidValue) }
        return image
    }
}

private func writeReduceMotionOverlay() throws {
    let data = try apngData(
        reduceMotionFrames(),
        delayNumerator: 3,
        delayDenominator: 25
    )
    try data.write(
        to: framesDirectory.appendingPathComponent("quota-consumption-reduce-motion.apng"),
        options: .atomic
    )
    print("Generated reduce-motion overlay: 3 frames @ 120 ms")
}

private func validate(kind: MasterKind) throws {
    let url = framesDirectory.appendingPathComponent("quota-consumption-master-\(kind.rawValue).apng")
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          CGImageSourceGetCount(source) == kind.frameCount else {
        throw CocoaError(.fileReadCorruptFile)
    }
    for index in 0..<kind.frameCount {
        guard let image = CGImageSourceCreateImageAtIndex(source, index, nil),
              image.width == Int(canvasSize.width),
              image.height == Int(canvasSize.height),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any],
              let delay = png[kCGImagePropertyAPNGUnclampedDelayTime] as? Double,
              abs(delay - frameDelay) < 0.001 else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
}

private func main() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.first == "--bake" {
        let requested = arguments.dropFirst().compactMap(MasterKind.init(rawValue:))
        try bakeProduction(kinds: requested.isEmpty ? MasterKind.allCases : requested)
        return
    }
    if arguments == ["--reduce-motion"] {
        try writeReduceMotionOverlay()
        return
    }
    if arguments == ["--production"] {
        try bakeProduction(kinds: MasterKind.allCases)
        try writeReduceMotionOverlay()
        return
    }

    let base50 = try loadImage(named: "quota-50-frame-0.png")
    let base10 = try loadImage(named: "quota-10-frame-0.png")
    let base0 = try loadImage(named: "quota-0-frame-0.png")
    let requested = arguments.compactMap(MasterKind.init(rawValue:))
    let kinds = requested.isEmpty ? MasterKind.allCases : requested
    for kind in kinds {
        let frames = try (0..<kind.frameCount).map {
            try authoredFrame(kind: kind, index: $0, base50: base50, base10: base10, base0: base0)
        }
        try writeAPNG(frames, kind: kind)
        try validate(kind: kind)
        print("Generated \(kind.rawValue): \(kind.frameCount) frames @ 24 fps")
    }
}

do {
    try main()
} catch {
    FileHandle.standardError.write(Data("quota-consumption master generation failed: \(error)\n".utf8))
    exit(1)
}
