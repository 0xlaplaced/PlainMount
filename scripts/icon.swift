import AppKit
let output = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let rect = NSRect(x: 72, y: 72, width: 880, height: 880)
let background = NSBezierPath(roundedRect: rect, xRadius: 192, yRadius: 192)
NSGradient(starting: NSColor(red: 0.05, green: 0.25, blue: 0.34, alpha: 1), ending: NSColor(red: 0.03, green: 0.12, blue: 0.21, alpha: 1))!.draw(in: background, angle: -55)
let drive = NSBezierPath(roundedRect: NSRect(x: 226, y: 280, width: 572, height: 464), xRadius: 70, yRadius: 70)
NSColor.white.withAlphaComponent(0.95).setFill()
drive.fill()
let line = NSBezierPath(roundedRect: NSRect(x: 270, y: 412, width: 484, height: 18), xRadius: 9, yRadius: 9)
NSColor(red: 0.12, green: 0.33, blue: 0.43, alpha: 1).setFill()
line.fill()
NSColor(red: 0.1, green: 0.66, blue: 0.56, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 674, y: 332, width: 34, height: 34)).fill()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
