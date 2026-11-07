// Renders haiku/kigo.svg onto a macOS icon tile: mkicon.swift <svg> <out.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let leaf = NSImage(contentsOfFile: args[1]) else {
	FileHandle.standardError.write("usage: mkicon.swift <svg> <out.png>\n".data(using: .utf8)!)
	exit(1)
}
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
	samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Apple's icon grid: an 824-point rounded square, 100 in from each edge.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.shadowBlurRadius = 24
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colors: [NSColor(red: 0.16, green: 0.18, blue: 0.20, alpha: 1),
	NSColor(red: 0.07, green: 0.08, blue: 0.09, alpha: 1)])!.draw(in: shape, angle: -90)

let inset = tile.insetBy(dx: 70, dy: 70)
leaf.draw(in: inset, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
