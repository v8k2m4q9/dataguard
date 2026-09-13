import AppKit
let size = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
NSColor(calibratedRed: 0.04, green: 0.18, blue: 0.27, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
let shield = NSBezierPath()
shield.move(to: NSPoint(x: 512, y: 830))
shield.line(to: NSPoint(x: 790, y: 718))
shield.line(to: NSPoint(x: 770, y: 448))
shield.curve(to: NSPoint(x: 512, y: 180), controlPoint1: NSPoint(x: 750, y: 300), controlPoint2: NSPoint(x: 620, y: 220))
shield.curve(to: NSPoint(x: 254, y: 448), controlPoint1: NSPoint(x: 404, y: 220), controlPoint2: NSPoint(x: 274, y: 300))
shield.line(to: NSPoint(x: 234, y: 718))
shield.close()
NSColor(calibratedRed: 0.27, green: 0.86, blue: 0.78, alpha: 1).setStroke()
shield.lineWidth = 38
shield.lineJoinStyle = .round
shield.stroke()
NSColor.white.setFill()
for (x, height) in [(370, 125), (480, 225), (590, 325)] {
    NSBezierPath(roundedRect: NSRect(x: x, y: 385, width: 65, height: height), xRadius: 22, yRadius: 22).fill()
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
