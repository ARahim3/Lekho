// Generate the input-menu icon: the app logo (white অ on vermillion), 16×16 pt,
// as a TIFF with 1x and 2x bitmaps. Info.plist sets TISIconIsTemplate to false.
//
// It must be a bitmap, not a PDF. macOS 26 draws a PDF input-menu icon as a
// one-color template whatever TISIconIsTemplate says, so the PDF logo shipped
// in v0.4.0 showed up as a blank filled square. The same logo as a TIFF keeps
// its colors (checked in the real menu bar on macOS 26.7, 2026-10-08).
//
//   swift scripts/generate_menu_icon.swift Lekho/Resources/MenuIcon.tiff [preview-dir]
//
// The glyph is drawn as outlines, so rendering never depends on an installed font.
import Cocoa
import CoreText

let side: CGFloat = 16
let vermillion = CGColor(srgbRed: 192 / 255, green: 57 / 255, blue: 43 / 255, alpha: 1)  // #C0392B, as on the site

func glyphPath(_ text: String, font: CTFont) -> CGPath {
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: text, attributes: [.font: font]))
    let path = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let count = CTRunGetGlyphCount(run)
        let runFont = (CTRunGetAttributes(run) as Dictionary)[kCTFontAttributeName] as! CTFont
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
        for i in 0..<count {
            guard let outline = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
            path.addPath(outline, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
        }
    }
    return path
}

func draw(in ctx: CGContext) {
    let badge = CGRect(x: 0.5, y: 0.5, width: side - 1, height: side - 1)
    ctx.addPath(CGPath(roundedRect: badge, cornerWidth: 3.5, cornerHeight: 3.5, transform: nil))
    ctx.setFillColor(vermillion)
    ctx.fillPath()

    let font = CTFontCreateWithName("KohinoorBangla-Semibold" as CFString, 11.5, nil)
    let glyph = glyphPath("অ", font: font)
    let box = glyph.boundingBoxOfPath
    // Center the outline itself, not the font's line box.
    var move = CGAffineTransform(translationX: (side - box.width) / 2 - box.minX,
                                 y: (side - box.height) / 2 - box.minY)
    ctx.addPath(glyph.copy(using: &move)!)
    ctx.setFillColor(.white)
    ctx.fillPath()
}

/// A bitmap of `width`×`height` pt at `scale`, with `paint` drawing in points.
func bitmap(width: CGFloat, height: CGFloat, scale: CGFloat, _ paint: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: scale, y: scale)
    paint(ctx)
    return rep
}

let args = CommandLine.arguments
let output = args.count > 1 ? args[1] : "MenuIcon.tiff"

// 16 px at 72 dpi, then 32 px at 144 dpi, the layout of Apple's own input-menu TIFFs.
let tiff = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, "public.tiff" as CFString, 2, nil)!
for scale: CGFloat in [1, 2] {
    let dpi = 72 * scale
    CGImageDestinationAddImage(tiff, bitmap(width: side, height: side, scale: scale, draw).cgImage!,
                               [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
}
precondition(CGImageDestinationFinalize(tiff), "could not write \(output)")
print("Menu icon written to \(output)")

// Optional: 2x PNG previews on light and dark menu-bar backgrounds.
if args.count > 2 {
    for (name, bg) in [("light", CGColor(gray: 0.93, alpha: 1)), ("dark", CGColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1))] {
        let width: CGFloat = 60, height: CGFloat = 24
        let rep = bitmap(width: width, height: height, scale: 2) { ctx in
            ctx.setFillColor(bg)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.translateBy(x: (width - side) / 2, y: (height - side) / 2)
            draw(in: ctx)
        }
        let url = URL(fileURLWithPath: args[2]).appendingPathComponent("menuicon-\(name).png")
        try! rep.representation(using: .png, properties: [:])!.write(to: url)
        print("Preview: \(url.path)")
    }
}
