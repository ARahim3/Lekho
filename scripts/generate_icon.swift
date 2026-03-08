// Generate a template menu bar icon with Bengali character "অ"
// Template images: macOS auto-inverts for dark mode (black → white)
import Cocoa

let size = NSSize(width: 16, height: 16)
let image = NSImage(size: size, flipped: false) { rect in
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor.black
    ]
    let str = "অ" as NSString
    let strSize = str.size(withAttributes: attrs)
    let point = NSPoint(
        x: (rect.width - strSize.width) / 2,
        y: (rect.height - strSize.height) / 2
    )
    str.draw(at: point, withAttributes: attrs)
    return true
}

// Mark as template so macOS auto-inverts for dark menu bars
image.isTemplate = true

let tiffData = image.tiffRepresentation!
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "iconTemplate.tiff"
try! tiffData.write(to: URL(fileURLWithPath: outputPath))
print("Icon written to \(outputPath)")
