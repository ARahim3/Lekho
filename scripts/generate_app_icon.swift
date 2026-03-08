// Generate macOS app icon (.icns) with Bengali "অ" on a terracotta background
import Cocoa

func generateIcon(size: Int, scale: Int) -> NSImage {
    let pixelSize = size * scale
    let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize), flipped: false) { rect in
        let cornerRadius = rect.width * 0.22  // macOS icon corner radius

        // Background — terracotta/brownish-red
        let bgColor = NSColor(red: 0.64, green: 0.25, blue: 0.20, alpha: 1.0)
        let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                   xRadius: cornerRadius, yRadius: cornerRadius)
        bgColor.setFill()
        bgPath.fill()

        // Subtle inner shadow / gradient overlay for depth
        let gradientColor = NSColor(white: 1.0, alpha: 0.06)
        let topRect = NSRect(x: rect.origin.x, y: rect.midY,
                             width: rect.width, height: rect.height / 2)
        let gradPath = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                     xRadius: cornerRadius, yRadius: cornerRadius)
        gradientColor.setFill()
        // Clip to top half for subtle highlight
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: topRect).setClip()
        gradPath.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        // "অ" character — white, centered
        let fontSize = CGFloat(pixelSize) * 0.55
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let str = "অ" as NSString
        let strSize = str.size(withAttributes: attrs)
        let point = NSPoint(
            x: (rect.width - strSize.width) / 2,
            y: (rect.height - strSize.height) / 2 - CGFloat(pixelSize) * 0.01
        )
        str.draw(at: point, withAttributes: attrs)

        return true
    }
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG for \(path)")
        return
    }
    try! png.write(to: URL(fileURLWithPath: path))
}

// Output directory
let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "."
let iconsetDir = "\(outputDir)/AppIcon.iconset"

// Create iconset directory
try! FileManager.default.createDirectory(atPath: iconsetDir,
                                          withIntermediateDirectories: true)

// Generate all required sizes
let sizes = [16, 32, 128, 256, 512]
for size in sizes {
    let img1x = generateIcon(size: size, scale: 1)
    savePNG(img1x, to: "\(iconsetDir)/icon_\(size)x\(size).png")

    let img2x = generateIcon(size: size, scale: 2)
    savePNG(img2x, to: "\(iconsetDir)/icon_\(size)x\(size)@2x.png")
}

print("Iconset generated at \(iconsetDir)")
print("Run: iconutil -c icns \(iconsetDir)")
