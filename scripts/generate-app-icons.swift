import AppKit

// Derive every iPhone size from the approved artwork; never redraw the retired logo.
guard CommandLine.arguments.count == 3 else {
    fatalError("Uso: swift generate-app-icons.swift imagen-aprobada.png directorio.appiconset")
}
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
guard let source = NSImage(contentsOf: sourceURL) else { fatalError("No se pudo abrir la imagen") }
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var images: [[String: String]] = []
func render(_ pixels: Int, filename: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.white.setFill()
    let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    rect.fill()
    source.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
}
for size in [20, 29, 40, 60] {
    for scale in [2, 3] {
        let filename = "LenaraIcon-\(size)@\(scale)x.png"
        try render(size * scale, filename: filename)
        images.append(["idiom": "iphone", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename])
    }
}
try render(1024, filename: "lenara-1024.png")
images.append(["idiom": "ios-marketing", "size": "1024x1024", "scale": "1x", "filename": "lenara-1024.png"])
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
