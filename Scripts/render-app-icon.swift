// Renders Talos/Assets.xcassets/AppIcon.appiconset from code, so the icon is
// reproducible: swiftc -O -o /tmp/render Scripts/render-app-icon.swift &&
//   /tmp/render Talos/Assets.xcassets/AppIcon.appiconset

import AppKit

// Talos app icon: a neutral squircle (the app's Reader-mode greys) with a
// heavy rounded T. Same family as the old Candoa "C", new letter.
func draw(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.clear(CGRect(x: 0, y: 0, width: size, height: size))
    let u = size / 1024.0

    // macOS icon grid: the tile is ~80% of the canvas, corner radius ~22.4% of the tile.
    let tile = CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    let radius = 185 * u
    let path = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Soft drop shadow under the tile.
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -12 * u), blur: 40 * u,
                 color: CGColor(gray: 0, alpha: 0.28))
    cg.addPath(path); cg.setFillColor(CGColor(gray: 0.95, alpha: 1)); cg.fillPath()
    cg.restoreGState()

    // Vertical gradient: #f7f7f9 at the top to #e6e6e9 at the bottom.
    cg.saveGState()
    cg.addPath(path); cg.clip()
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let g = CGGradient(colorsSpace: space, colors: [
        CGColor(colorSpace: space, components: [0xf7/255, 0xf7/255, 0xf9/255, 1])!,
        CGColor(colorSpace: space, components: [0xe6/255, 0xe6/255, 0xe9/255, 1])!] as CFArray,
        locations: [0, 1])!
    cg.drawLinearGradient(g, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
    // A faint top highlight and a 1px hairline edge, like the system's own tiles.
    let hl = CGGradient(colorsSpace: space, colors: [
        CGColor(gray: 1, alpha: 0.55), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(hl, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.maxY - 180 * u), options: [])
    cg.restoreGState()
    cg.saveGState()
    cg.addPath(path); cg.setStrokeColor(CGColor(gray: 0, alpha: 0.10)); cg.setLineWidth(max(1, 2 * u)); cg.strokePath()
    cg.restoreGState()

    // The T: crossbar and stem, rounded terminals, #1d1d1f.
    let ink = CGColor(colorSpace: space, components: [0x1d/255, 0x1d/255, 0x1f/255, 1])!
    cg.setFillColor(ink)
    let barH = 118 * u, stemW = 118 * u, r = 44 * u
    let cross = CGRect(x: 268 * u, y: 1024 * u - 388 * u, width: 488 * u, height: barH)
    let stem = CGRect(x: 512 * u - stemW / 2, y: 1024 * u - 748 * u, width: stemW, height: 748 * u - 270 * u)
    cg.addPath(CGPath(roundedRect: cross, cornerWidth: r, cornerHeight: r, transform: nil)); cg.fillPath()
    cg.addPath(CGPath(roundedRect: stem, cornerWidth: r, cornerHeight: r, transform: nil)); cg.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments[1]
for s in [16, 32, 64, 128, 256, 512, 1024] {
    let rep = draw(size: CGFloat(s))
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(out)/icon_\(s).png"))
}
print("rendered")
