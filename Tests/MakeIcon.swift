import AppKit

let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let tile = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 190, yRadius: 190)
NSColor(calibratedRed: 0.08, green: 0.13, blue: 0.16, alpha: 1).setFill()
tile.fill()
let ring = NSBezierPath(ovalIn: NSRect(x: 242, y: 242, width: 540, height: 540))
ring.lineWidth = 22
NSColor(calibratedRed: 0.23, green: 0.79, blue: 0.69, alpha: 0.25).setStroke()
ring.stroke()
let bolt = NSBezierPath()
bolt.move(to: NSPoint(x: 570, y: 794))
bolt.line(to: NSPoint(x: 345, y: 472))
bolt.line(to: NSPoint(x: 488, y: 472))
bolt.line(to: NSPoint(x: 451, y: 239))
bolt.line(to: NSPoint(x: 689, y: 577))
bolt.line(to: NSPoint(x: 538, y: 577))
bolt.close()
NSColor(calibratedRed: 0.40, green: 0.91, blue: 0.77, alpha: 1).setFill()
bolt.fill()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
