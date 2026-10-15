import AppKit

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let rect = NSRect(x: 64, y: 64, width: 896, height: 896)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 208, yRadius: 208)
        NSColor(srgbRed: 0.075, green: 0.13, blue: 0.14, alpha: 1).setFill()
        shape.fill()
        let accent = NSColor(srgbRed: 0.72, green: 0.95, blue: 0.81, alpha: 1)
        for (radius, opacity, thickness) in [(330.0, 0.2, 9.0), (252.0, 0.4, 10.0), (174.0, 0.65, 11.0)] {
            accent.withAlphaComponent(opacity).setStroke()
            let circle = NSBezierPath(ovalIn: NSRect(x: 512 - radius, y: 512 - radius, width: 2 * radius, height: 2 * radius))
            circle.lineWidth = thickness
            circle.stroke()
        }
        accent.setFill()
        NSBezierPath(ovalIn: NSRect(x: 404, y: 404, width: 216, height: 216)).fill()
        NSColor(srgbRed: 0.075, green: 0.13, blue: 0.14, alpha: 1).setFill()
        let play = NSBezierPath()
        play.move(to: NSPoint(x: 490, y: 464))
        play.line(to: NSPoint(x: 490, y: 560))
        play.line(to: NSPoint(x: 563, y: 512))
        play.close()
        play.fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination).appendingPathComponent(filename))
    }
}
