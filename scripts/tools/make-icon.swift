import AppKit
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let rect = NSRect(x: 50, y: 50, width: 924, height: 924)
NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.13, alpha: 1).setFill()
NSBezierPath(roundedRect: rect, xRadius: 210, yRadius: 210).fill()
let circle = NSBezierPath(ovalIn: NSRect(x: 192, y: 192, width: 640, height: 640))
NSColor(calibratedRed: 0.78, green: 0.88, blue: 0.69, alpha: 1).setFill()
circle.fill()
let text = "m" as NSString
let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 540, weight: .light), .foregroundColor: NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.13, alpha: 1)]
let size = text.size(withAttributes: attributes)
text.draw(at: NSPoint(x: (1024-size.width)/2, y: (1024-size.height)/2+45), withAttributes: attributes)
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
