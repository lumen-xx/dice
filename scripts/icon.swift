import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Dice.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let p = CGFloat(pixels), inset = p * 0.09
        // Aurora palette from Sources/Dice/Style.swift: mint top left → cyan → indigo → violet bottom right.
        let aurora = [(0.204, 0.898, 0.722), (0.169, 0.769, 0.949), (0.369, 0.420, 1.0), (0.651, 0.361, 1.0)].map { NSColor(srgbRed: $0.0, green: $0.1, blue: $0.2, alpha: 1) }
        let body = NSBezierPath(roundedRect: NSRect(x: inset,y: inset,width: p-2*inset,height: p-2*inset), xRadius: p*0.18,yRadius: p*0.18)
        NSGradient(colors: aurora)!.draw(in: body, angle: -45)
        // A soft shade keeps the white pips legible over the light mint corner.
        NSGradient(colors: [NSColor.black.withAlphaComponent(0.18), NSColor.black.withAlphaComponent(0)])!.draw(in: body, angle: -45)
        NSColor.white.setFill()
        for (x,y) in [(0.32,0.32),(0.68,0.32),(0.5,0.5),(0.32,0.68),(0.68,0.68)] {
            NSBezierPath(ovalIn: NSRect(x: p*x-p*0.052,y: p*y-p*0.052,width: p*0.104,height: p*0.104)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
    }
}
