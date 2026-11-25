// Draws the app icon (a ship's wheel on a dark tile, with a green status dot) and writes
// App/Assets.xcassets/AppIcon.appiconset. Run with `make icon`.
// Drawn from scratch: SF Symbols aren't licensed for app icons.
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "App/Assets.xcassets/AppIcon.appiconset"

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func draw(_ ctx: CGContext) {
    // macOS icon grid: 824pt tile centered in 1024, ~185pt corner radius.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(shape); ctx.setFillColor(color(0x1B2433)); ctx.fillPath()
    ctx.restoreGState()

    // Background gradient.
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                        colors: [color(0x2E3B52), color(0x121822)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    // Ship's wheel: rim, hub and eight spokes ending in handles.
    let c = CGPoint(x: 512, y: 512)
    let white = color(0xF2F5FA)
    ctx.setStrokeColor(white); ctx.setFillColor(white); ctx.setLineCap(.round)

    ctx.setLineWidth(46)
    ctx.addArc(center: c, radius: 205, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    for i in 0..<8 {
        let a = CGFloat(i) * .pi / 4 + .pi / 8
        let p = { (r: CGFloat) in CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r) }
        ctx.setLineWidth(34)
        ctx.move(to: p(70)); ctx.addLine(to: p(205)); ctx.strokePath()
        ctx.setLineWidth(48)
        ctx.move(to: p(250)); ctx.addLine(to: p(318)); ctx.strokePath()
    }
    ctx.fillEllipse(in: CGRect(x: c.x - 82, y: c.y - 82, width: 164, height: 164))
    ctx.setFillColor(color(0x1B2433))
    ctx.fillEllipse(in: CGRect(x: c.x - 34, y: c.y - 34, width: 68, height: 68))

    // Status dot, top right, with a ring in the tile color so it reads over the wheel.
    let dot = CGPoint(x: 778, y: 778)
    ctx.setFillColor(color(0x1A2230))
    ctx.fillEllipse(in: CGRect(x: dot.x - 88, y: dot.y - 88, width: 176, height: 176))
    ctx.setFillColor(color(0x34C759))
    ctx.fillEllipse(in: CGRect(x: dot.x - 64, y: dot.y - 64, width: 128, height: 128))
}

func png(size: Int) -> Data {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    draw(ctx)
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
var images: [String] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        try png(size: pt * scale).write(to: URL(fileURLWithPath: "\(out)/\(name)"))
        images.append(#"{"idiom":"mac","size":"\#(pt)x\#(pt)","scale":"\#(scale)x","filename":"\#(name)"}"#)
    }
}
let json = "{\"images\":[\n  \(images.joined(separator: ",\n  "))\n],\"info\":{\"version\":1,\"author\":\"xcode\"}}\n"
try json.write(toFile: "\(out)/Contents.json", atomically: true, encoding: .utf8)
try #"{"info":{"version":1,"author":"xcode"}}"#.appending("\n")
    .write(toFile: "\(out)/../Contents.json", atomically: true, encoding: .utf8)
print("wrote \(out)")
