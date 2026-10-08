import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Dice.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let p = CGFloat(pixels), inset = p * 0.09
        NSColor(calibratedRed: 0.96, green: 0.35, blue: 0.10, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: inset,y: inset,width: p-2*inset,height: p-2*inset), xRadius: p*0.18,yRadius: p*0.18).fill()
        NSColor.white.setFill()
        for (x,y) in [(0.32,0.32),(0.68,0.32),(0.5,0.5),(0.32,0.68),(0.68,0.68)] {
            NSBezierPath(ovalIn: NSRect(x: p*x-p*0.052,y: p*y-p*0.052,width: p*0.104,height: p*0.104)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
    }
}
