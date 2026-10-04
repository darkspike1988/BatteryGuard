#!/usr/bin/env swift
import Cocoa
import CoreGraphics

// Explicit bitmap dimensions keep every icon variant independent of display scale.
func renderAppIcon(size: CGFloat = 1024) -> NSImage {
    let pixels = Int(size)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels,
        pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let ctx = context.cgContext
    ctx.scaleBy(x: size / 1024, y: size / 1024)
    let base = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: base, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 30,
                  color: CGColor(gray: 0, alpha: 0.18))
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(gray: 0.94, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
        colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 0.86, alpha: 1)] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924),
                           end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()
    // One restrained battery silhouette; no lettering or small decorative details.
    ctx.setFillColor(CGColor(gray: 0.27, alpha: 1))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 282, y: 352, width: 426, height: 320),
                      cornerWidth: 64, cornerHeight: 64, transform: nil))
    ctx.fillPath()
    ctx.addPath(CGPath(roundedRect: CGRect(x: 724, y: 444, width: 40, height: 136),
                      cornerWidth: 16, cornerHeight: 16, transform: nil))
    ctx.fillPath()
    ctx.setFillColor(CGColor(gray: 0.98, alpha: 1))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 320, y: 390, width: 288, height: 244),
                      cornerWidth: 28, cornerHeight: 28, transform: nil))
    ctx.fillPath()
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: NSSize(width: size, height: size))
    image.addRepresentation(bitmap)
    return image
}

// ==========================================
// Export: 1024x1024 PNG + iconutil iconset -> .icns
// ==========================================
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path
let projectDir = URL(fileURLWithPath: scriptDir).deletingLastPathComponent().path
let resourcesDir = "\(projectDir)/Resources"

let fm = FileManager.default
try? fm.createDirectory(atPath: resourcesDir, withIntermediateDirectories: true)

print("==> Rendere Master-Icon 1024x1024...")
let masterImage = renderAppIcon(size: 1024)

guard let tiffData = masterImage.tiffRepresentation,
      let bitmapRep = NSBitmapImageRep(data: tiffData),
      let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
    fatalError("Fehler beim Erzeugen der PNG-Daten")
}

let png1024Path = "\(resourcesDir)/AppIcon-1024.png"
try pngData.write(to: URL(fileURLWithPath: png1024Path))
print("==> Master-PNG gespeichert: \(png1024Path)")

// Iconset-Ordner für iconutil anlegen
let iconsetDir = "\(resourcesDir)/AppIcon.iconset"
try? fm.removeItem(atPath: iconsetDir)
try fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let iconSizes: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

print("==> Generiere Iconset-Varianten für alle Auflösungen...")
for item in iconSizes {
    let resizedImage = renderAppIcon(size: CGFloat(item.size))
    if let resTiff = resizedImage.tiffRepresentation,
       let resRep = NSBitmapImageRep(data: resTiff),
       let resPng = resRep.representation(using: .png, properties: [:]) {
        let destPath = "\(iconsetDir)/\(item.name)"
        try resPng.write(to: URL(fileURLWithPath: destPath))
    }
}

// iconutil aufrufen
let icnsPath = "\(resourcesDir)/AppIcon.icns"
print("==> Erzeuge \(icnsPath) via iconutil...")
let iconutilProcess = Process()
iconutilProcess.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutilProcess.arguments = ["-c", "icns", iconsetDir, "-o", icnsPath]
try iconutilProcess.run()
iconutilProcess.waitUntilExit()

if iconutilProcess.terminationStatus == 0 {
    print("==> AppIcon.icns erfolgreich erzeugt!")
} else {
    fatalError("iconutil schlug fehl mit Status \(iconutilProcess.terminationStatus)")
}

// Temporären iconset-Ordner bereinigen
try? fm.removeItem(atPath: iconsetDir)
print("==> Fertig! Assets in Resources/ aktualisiert.")
