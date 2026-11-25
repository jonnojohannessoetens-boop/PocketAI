import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let output = CommandLine.arguments.dropFirst().first ?? "Sources/PocketAI/Assets.xcassets/AppIcon.appiconset/JJSAppIcon.png"
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("Unable to create icon canvas") }

// Deep navy field; iOS applies its standard rounded app-icon mask.
context.setFillColor(CGColor(red: 0.035, green: 0.075, blue: 0.17, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

// Five-point black star centered in the upper half.
let center = CGPoint(x: 512, y: 620)
let outerRadius: CGFloat = 240
let innerRadius: CGFloat = 102
let star = CGMutablePath()
for index in 0..<10 {
    let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
    let angle = CGFloat.pi / 2 + CGFloat(index) * .pi / 5
    let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    if index == 0 { star.move(to: point) } else { star.addLine(to: point) }
}
star.closeSubpath()
context.addPath(star)
context.setFillColor(CGColor(gray: 0.015, alpha: 1))
context.fillPath()

// White JJS lettering remains legible at home-screen icon sizes.
let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 142, nil)
let attributes: [NSAttributedString.Key: Any] = [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.96, alpha: 1)
]
let line = CTLineCreateWithAttributedString(NSAttributedString(string: "JJS", attributes: attributes))
let textWidth = CGFloat(CTLineGet typographicBounds(line, nil, nil, nil))
context.textPosition = CGPoint(x: (CGFloat(size) - textWidth) / 2, y: 125)
CTLineDraw(line, context)

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Unable to create PNG icon at \(output)")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Unable to write icon PNG") }
print("Generated \(output)")
