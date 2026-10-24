// Re-create the original app icon using only the macOS SDK.
// Run from the project root: swift scripts/draw-icon.swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("FolioVoice/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
}

func drawIcon(size: Int) -> Data {
    let bitmap = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                           bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let context = NSGraphicsContext(cgContext: bitmap, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    let canvas = NSRect(x: 0, y: 0, width: 1024, height: 1024)
    NSGradient(starting: color(0.13, 0.12, 0.25), ending: color(0.06, 0.06, 0.12))!
        .draw(in: canvas, angle: 270)

    // The page block subtly tilts behind a crisp, front-facing book.
    let back = NSBezierPath(roundedRect: NSRect(x: 274, y: 221, width: 501, height: 618), xRadius: 72, yRadius: 72)
    var transform = AffineTransform()
    transform.translate(x: 512, y: 512)
    transform.rotate(byDegrees: -9)
    transform.translate(x: -512, y: -512)
    back.transform(using: transform)
    color(0.40, 0.30, 0.68).setFill()
    back.fill()

    let cover = NSBezierPath(roundedRect: NSRect(x: 235, y: 195, width: 530, height: 636), xRadius: 72, yRadius: 72)
    NSGradient(starting: color(0.70, 0.57, 1.0), ending: color(0.45, 0.30, 0.89))!
        .draw(in: cover, angle: 270)

    let spine = NSBezierPath()
    spine.move(to: NSPoint(x: 315, y: 244))
    spine.line(to: NSPoint(x: 315, y: 779))
    spine.lineWidth = 9
    spine.lineCapStyle = .round
    color(0.79, 0.71, 1).withAlphaComponent(0.52).setStroke()
    spine.stroke()

    let paper = NSBezierPath(roundedRect: NSRect(x: 278, y: 223, width: 445, height: 57), xRadius: 27, yRadius: 27)
    color(0.94, 0.91, 1).setFill()
    paper.fill()
    let paperLine = NSBezierPath()
    paperLine.move(to: NSPoint(x: 308, y: 248))
    paperLine.line(to: NSPoint(x: 695, y: 248))
    paperLine.lineWidth = 4
    color(0.67, 0.58, 0.83).setStroke()
    paperLine.stroke()

    let heights: [CGFloat] = [74, 140, 245, 186, 105]
    for (index, height) in heights.enumerated() {
        let bar = NSBezierPath(roundedRect: NSRect(x: 383 + CGFloat(index) * 61,
                                                   y: 530 - height / 2,
                                                   width: 30, height: height),
                               xRadius: 15, yRadius: 15)
        color(1, 0.98, 1).setFill()
        bar.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    let result = NSMutableData()
    let destination = CGImageDestinationCreateWithData(result, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, bitmap.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
    return result as Data
}

let specifications: [(String, String, Int)] = [
    ("20x20", "2x", 40), ("20x20", "3x", 60),
    ("29x29", "2x", 58), ("29x29", "3x", 87),
    ("40x40", "2x", 80), ("40x40", "3x", 120),
    ("60x60", "2x", 120), ("60x60", "3x", 180)
]
var images: [[String: String]] = []
for (pointSize, scale, pixels) in specifications {
    let filename = "Icon-\(pointSize)-\(scale).png"
    try drawIcon(size: pixels).write(to: output.appendingPathComponent(filename))
    images.append(["idiom": "iphone", "size": pointSize, "scale": scale, "filename": filename])
}
let marketingName = "Icon-1024.png"
try drawIcon(size: 1024).write(to: output.appendingPathComponent(marketingName))
images.append(["idiom": "ios-marketing", "size": "1024x1024", "scale": "1x", "filename": marketingName])
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.appendingPathComponent("Contents.json"))
print("Created all iPhone app icon sizes.")
