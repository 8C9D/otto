// Renders Otto's 1024x1024 app icon into
// Otto/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png.
// The PNG is committed; this script is how it is reproduced, not a build step:
//
//   swift scripts/make-app-icon.swift \
//     Otto/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
//
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S),
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("could not create the bitmap context")
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    guard let c = CGColor(colorSpace: cs, components: [r, g, b, a]) else {
        fatalError("could not create a color")
    }
    return c
}

func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
    color(CGFloat(r) / 255, CGFloat(g) / 255, CGFloat(b) / 255)
}

let white = color(1, 1, 1)

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    guard let g = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locations) else {
        fatalError("could not create a gradient")
    }
    return g
}

// Background: deep indigo -> violet, top-left to bottom-right.
let top = rgb(72, 84, 220)
let bottom = rgb(126, 58, 199)
let grad = gradient([top, bottom], [0, 1])
ctx.saveGState()
ctx.addRect(CGRect(x: 0, y: 0, width: S, height: S))
ctx.clip()
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])
ctx.restoreGState()

// Soft highlight in the upper-left so the flat gradient gets some depth.
let hi = gradient([color(1, 1, 1, 0.18), color(1, 1, 1, 0)], [0, 1])
ctx.drawRadialGradient(hi,
                       startCenter: CGPoint(x: S * 0.28, y: S * 0.80), startRadius: 0,
                       endCenter: CGPoint(x: S * 0.28, y: S * 0.80), endRadius: S * 0.62,
                       options: [])

// The mark: a thick ring with a gap at the top right and an arrowhead on the
// leading end - a renewal cycle, and an "O" for Otto.
let center = CGPoint(x: S / 2, y: S / 2)
let radius: CGFloat = S * 0.285
let lineWidth: CGFloat = S * 0.105

ctx.setStrokeColor(white)
ctx.setLineWidth(lineWidth)
ctx.setLineCap(.round)

// Arc runs clockwise from just past the top around to ~55 degrees, leaving the
// gap that the arrowhead fills.
ctx.addArc(center: center, radius: radius,
           startAngle: .pi / 2 - 0.46,
           endAngle: .pi / 2 + 0.46,
           clockwise: true)
ctx.strokePath()

// Arrowhead at the head of the sweep - the clockwise arc ends at pi/2 + 0.30,
// on the left side of the gap, so the head points across the gap to the right.
let headAngle: CGFloat = .pi / 2 + 0.46
let dir = CGPoint(x: cos(headAngle), y: sin(headAngle))
// Tangent of clockwise travel at that angle.
let tangent = CGPoint(x: sin(headAngle), y: -cos(headAngle))
let anchor = CGPoint(x: center.x + dir.x * radius, y: center.y + dir.y * radius)
let halfBase = lineWidth * 0.78
let length = lineWidth * 0.95
let tip = CGPoint(x: anchor.x + tangent.x * length, y: anchor.y + tangent.y * length)
let baseOuter = CGPoint(x: center.x + dir.x * (radius + halfBase),
                        y: center.y + dir.y * (radius + halfBase))
let baseInner = CGPoint(x: center.x + dir.x * (radius - halfBase),
                        y: center.y + dir.y * (radius - halfBase))
ctx.setFillColor(white)
ctx.beginPath()
ctx.move(to: tip)
ctx.addLine(to: baseOuter)
ctx.addLine(to: baseInner)
ctx.closePath()
ctx.fillPath()

// Checkmark inside: the cancellation actually stopped the charges.
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setLineWidth(S * 0.078)
ctx.beginPath()
ctx.move(to: CGPoint(x: S * 0.392, y: S * 0.508))
ctx.addLine(to: CGPoint(x: S * 0.470, y: S * 0.428))
ctx.addLine(to: CGPoint(x: S * 0.622, y: S * 0.585))
ctx.strokePath()

guard let image = ctx.makeImage() else { fatalError("could not render the image") }
guard CommandLine.arguments.count == 2 else {
    fatalError("usage: swift scripts/make-app-icon.swift <output.png>")
}
let out = URL(fileURLWithPath: CommandLine.arguments[1])
guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("could not create the PNG destination")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
print("wrote \(out.path)")
