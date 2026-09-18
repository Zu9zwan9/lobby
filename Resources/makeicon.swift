// Generates Resources/AppIcon.icns. Run: make icon
// Mark: a doorway arch, with the Wi-Fi arcs nested inside it. Both are arcs,
// so they share one geometry: an entrance you sign in through.
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024

func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
    CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}

guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no context")
}

// Squircle plate, sized to Apple's macOS icon grid (824pt inside a 1024pt canvas).
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.addPath(platePath)
ctx.clip()
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [rgb(64, 84, 214), rgb(22, 27, 82)] as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: S),
                       end: CGPoint(x: 0, y: 100), options: [])
ctx.restoreGState()

// Doorway: straight jambs rising into a semicircular head. Stroked, not filled,
// so it stays legible when the icon is drawn at 16pt in the Finder sidebar.
// Proportions are tuned so the arch sits close around the Wi-Fi arcs. Opening
// them up leaves dead space under the crown and the mark stops reading as a door.
let cx: CGFloat = 512
let halfWidth: CGFloat = 228
let sill: CGFloat = 300
let springLine: CGFloat = 470          // where the jambs meet the arch
let door = CGMutablePath()
door.move(to: CGPoint(x: cx - halfWidth, y: sill))
door.addLine(to: CGPoint(x: cx - halfWidth, y: springLine))
door.addArc(center: CGPoint(x: cx, y: springLine), radius: halfWidth,
            startAngle: .pi, endAngle: 0, clockwise: true)
door.addLine(to: CGPoint(x: cx + halfWidth, y: sill))

ctx.setStrokeColor(.white)
ctx.setLineWidth(46)
ctx.setLineCap(.round)
ctx.addPath(door)
ctx.strokePath()

// Wi-Fi arcs, struck from a point on the sill so they nest inside the doorway.
let origin = CGPoint(x: cx, y: sill + 52)
for radius in [CGFloat(66), 122, 178] {
    ctx.setLineWidth(34)
    ctx.setStrokeColor(.white)
    ctx.addArc(center: origin, radius: radius,
               startAngle: .pi / 6, endAngle: .pi * 5 / 6, clockwise: false)
    ctx.strokePath()
}
ctx.setFillColor(.white)
ctx.fillEllipse(in: CGRect(x: cx - 25, y: origin.y - 25, width: 50, height: 50))

guard let image = ctx.makeImage() else { fatalError("no image") }
let out = URL(fileURLWithPath: "Resources/icon-1024.png")
guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("no destination") }
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path)")
