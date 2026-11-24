// Renders the DMG window background at 1x and 2x.
//
//     swift scripts/release/dmg/render-background.swift scripts/release/dmg
//
// Writes background.png and background@2x.png into the given directory.
// Geometry must match the Finder layout in scripts/release/dmg.sh.

import AppKit

let canvas = CGSize(width: 660, height: 420)
let card = CGRect(x: 60, y: 196, width: 540, height: 190)
let iconCenterY: CGFloat = 278
let appIconX: CGFloat = 190
let applicationsX: CGFloat = 470

let ink = NSColor(srgbRed: 0x20 / 255, green: 0x10 / 255, blue: 0x28 / 255, alpha: 1)
let skyTop = NSColor(srgbRed: 0xE6 / 255, green: 0xF3 / 255, blue: 0xF9 / 255, alpha: 1)
let skyBottom = NSColor(srgbRed: 0xFB / 255, green: 0xFD / 255, blue: 0xFE / 255, alpha: 1)
let arrowGray = NSColor(srgbRed: 0x86 / 255, green: 0x86 / 255, blue: 0x8B / 255, alpha: 1)
let captionGray = NSColor(srgbRed: 0x6E / 255, green: 0x6E / 255, blue: 0x73 / 255, alpha: 1)

func render(scale: CGFloat, to url: URL) throws {
    let pixels = CGSize(width: canvas.width * scale, height: canvas.height * scale)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { throw CocoaError(.fileWriteUnknown) }
    rep.size = canvas
    let rgb = rep.retagging(with: .sRGB) ?? rep

    guard let cg = NSGraphicsContext(bitmapImageRep: rgb)?.cgContext else {
        throw CocoaError(.fileWriteUnknown)
    }
    cg.translateBy(x: 0, y: canvas.height)
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    draw()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rgb.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: url)
}

func draw() {
    NSGradient(starting: skyTop, ending: skyBottom)?
        .draw(in: CGRect(origin: .zero, size: canvas), angle: 90)

    drawWordmark()
    drawCard()
    drawArrow()
}

func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

func drawCentered(_ text: String, attributes: [NSAttributedString.Key: Any], centerY: CGFloat) {
    let string = NSAttributedString(string: text, attributes: attributes)
    let size = string.size()
    string.draw(at: CGPoint(x: (canvas.width - size.width) / 2, y: centerY - size.height / 2))
}

func drawWordmark() {
    drawCentered("Cruftless", attributes: [
        .font: roundedFont(size: 68, weight: .bold),
        .foregroundColor: ink,
        .kern: -1.2,
    ], centerY: 88)
    drawCentered("Drag Cruftless into Applications to install", attributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .regular),
        .foregroundColor: captionGray,
    ], centerY: 140)
}

func drawCard() {
    let path = NSBezierPath(roundedRect: card, xRadius: 18, yRadius: 18)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(srgbRed: 0x20 / 255, green: 0x10 / 255, blue: 0x28 / 255, alpha: 0.10)
    shadow.shadowBlurRadius = 18
    shadow.shadowOffset = CGSize(width: 0, height: -6)
    shadow.set()
    NSColor.white.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.07).setStroke()
    path.lineWidth = 1
    path.stroke()
}

func drawArrow() {
    let configuration = NSImage.SymbolConfiguration(pointSize: 40, weight: .medium)
        .applying(.init(paletteColors: [arrowGray]))
    guard let symbol = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) else { return }
    let midX = (appIconX + applicationsX) / 2
    let rect = CGRect(
        x: midX - symbol.size.width / 2, y: iconCenterY - symbol.size.height / 2,
        width: symbol.size.width, height: symbol.size.height
    )
    symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: render-background.swift OUTPUT_DIR\n".utf8))
    exit(64)
}
let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
try render(scale: 1, to: directory.appendingPathComponent("background.png"))
try render(scale: 2, to: directory.appendingPathComponent("background@2x.png"))
