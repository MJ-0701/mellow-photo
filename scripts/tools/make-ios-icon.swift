import AppKit
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.13, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
NSColor(calibratedRed: 0.78, green: 0.88, blue: 0.69, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 180, y: 180, width: 664, height: 664)).fill()
let text = "m" as NSString
let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 540, weight: .light), .foregroundColor: NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.13, alpha: 1)]
let size = text.size(withAttributes: attributes)
text.draw(at: NSPoint(x: (1024-size.width)/2, y: (1024-size.height)/2+45), withAttributes: attributes)
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
