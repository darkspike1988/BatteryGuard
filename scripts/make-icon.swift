#!/usr/bin/env swift
import Cocoa
import CoreGraphics

// scripts/make-icon.swift
// Erzeugt ein modernes Liquid-Glass App-Icon (1024x1024) und das iconset / AppIcon.icns für macOS.

func renderAppIcon(size: CGFloat = 1024) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let scale = size / 1024.0
    ctx.scaleBy(x: scale, y: scale)

    let colorSpace = CGColorSpaceCreateDeviceRGB()

    // ==========================================
    // 1. Äußere Geometrie (macOS Squircle / Rounded Rect)
    // ==========================================
    let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let cornerRadius: CGFloat = 185
    let squirclePath = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // A. Weicher Raumschatten (Ambient Drop Shadow)
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -30),
        blur: 48,
        color: CGColor(red: 0.0, green: 0.04, blue: 0.12, alpha: 0.65)
    )
    ctx.addPath(squirclePath)
    ctx.setFillColor(CGColor(red: 0.02, green: 0.08, blue: 0.16, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // B. Nahbereichsschatten (Contact Shadow)
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -10),
        blur: 16,
        color: CGColor(red: 0.0, green: 0.02, blue: 0.08, alpha: 0.50)
    )
    ctx.addPath(squirclePath)
    ctx.setFillColor(CGColor(red: 0.02, green: 0.08, blue: 0.16, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // ==========================================
    // 2. Hintergrund: Tiefer Blau-Türkiser Flüssigglas-Verlauf
    // ==========================================
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    // Mehrstufiger Farbverlauf: Oben Cyan/Saphir -> Mitte Ozeanblau -> Unten Nachtblau
    let bgColors: [CGColor] = [
        CGColor(red: 0.02, green: 0.36, blue: 0.56, alpha: 1.0), // Strahlendes Cyan-Blau oben
        CGColor(red: 0.02, green: 0.22, blue: 0.44, alpha: 1.0), // Königsblau
        CGColor(red: 0.01, green: 0.12, blue: 0.28, alpha: 1.0), // Tiefsee
        CGColor(red: 0.01, green: 0.04, blue: 0.12, alpha: 1.0)  // Dunkles Nachtblau unten
    ]
    let bgLocations: [CGFloat] = [0.0, 0.32, 0.70, 1.0]
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors as CFArray, locations: bgLocations) {
        ctx.drawLinearGradient(
            bgGradient,
            start: CGPoint(x: 200, y: 924),
            end: CGPoint(x: 824, y: 100),
            options: []
        )
    }

    // Zentraler Cyan-Bloom hinter dem Akku (Backlight)
    let backBloomColors: [CGColor] = [
        CGColor(red: 0.0, green: 0.95, blue: 0.95, alpha: 0.38),
        CGColor(red: 0.0, green: 0.65, blue: 0.88, alpha: 0.22),
        CGColor(red: 0.0, green: 0.20, blue: 0.45, alpha: 0.0)
    ]
    if let backGrad = CGGradient(colorsSpace: colorSpace, colors: backBloomColors as CFArray, locations: [0.0, 0.45, 1.0]) {
        ctx.drawRadialGradient(
            backGrad,
            startCenter: CGPoint(x: 500, y: 535),
            startRadius: 10,
            endCenter: CGPoint(x: 500, y: 535),
            endRadius: 420,
            options: []
        )
    }

    // Flüssigglas-Reflexionskurve oben (macOS Gloss Arc)
    ctx.saveGState()
    let arcPath = CGMutablePath()
    arcPath.move(to: CGPoint(x: 100, y: 924))
    arcPath.addLine(to: CGPoint(x: 924, y: 924))
    arcPath.addLine(to: CGPoint(x: 924, y: 650))
    arcPath.addQuadCurve(to: CGPoint(x: 100, y: 730), control: CGPoint(x: 480, y: 570))
    arcPath.closeSubpath()
    ctx.addPath(arcPath)
    ctx.clip()

    let arcColors: [CGColor] = [
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.20),
        CGColor(red: 0.4, green: 0.9, blue: 1.0, alpha: 0.06),
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0)
    ]
    if let aGrad = CGGradient(colorsSpace: colorSpace, colors: arcColors as CFArray, locations: [0.0, 0.45, 1.0]) {
        ctx.drawLinearGradient(aGrad, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 570), options: [])
    }
    ctx.restoreGState()

    // ==========================================
    // 3. Akku-Gehäuse (Liquid Glass Silhouette)
    // ==========================================
    let bodyWidth: CGFloat = 520
    let bodyHeight: CGFloat = 280
    let bodyX: CGFloat = 210
    let bodyY: CGFloat = 400
    let bodyRadius: CGFloat = 48

    let batteryBodyRect = CGRect(x: bodyX, y: bodyY, width: bodyWidth, height: bodyHeight)
    let batteryBodyPath = CGPath(roundedRect: batteryBodyRect, cornerWidth: bodyRadius, cornerHeight: bodyRadius, transform: nil)

    // Pluspol (Terminal Cap)
    let capWidth: CGFloat = 36
    let capHeight: CGFloat = 130
    let capX = batteryBodyRect.maxX + 4
    let capY = batteryBodyRect.midY - capHeight / 2
    let capRadius: CGFloat = 16
    let capRect = CGRect(x: capX, y: capY, width: capWidth, height: capHeight)
    let capPath = CGPath(roundedRect: capRect, cornerWidth: capRadius, cornerHeight: capRadius, transform: nil)

    // Tiefer Schattenwurf des Akkus auf den Hintergrund
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -22),
        blur: 38,
        color: CGColor(red: 0.0, green: 0.03, blue: 0.10, alpha: 0.75)
    )
    ctx.addPath(batteryBodyPath)
    ctx.addPath(capPath)
    ctx.setFillColor(CGColor(red: 0.01, green: 0.08, blue: 0.18, alpha: 0.9))
    ctx.fillPath()
    ctx.restoreGState()

    // Terminal Cap zeichnen (Massives mattes Glas & Glanzkante)
    ctx.saveGState()
    ctx.addPath(capPath)
    ctx.clip()
    let capColors: [CGColor] = [
        CGColor(red: 0.28, green: 0.65, blue: 0.85, alpha: 0.95),
        CGColor(red: 0.10, green: 0.35, blue: 0.55, alpha: 1.0)
    ]
    if let cGrad = CGGradient(colorsSpace: colorSpace, colors: capColors as CFArray, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(cGrad, start: CGPoint(x: capX, y: capRect.maxY), end: CGPoint(x: capX + capWidth, y: capY), options: [])
    }
    ctx.restoreGState()

    ctx.saveGState()
    ctx.setLineWidth(3.0)
    ctx.setStrokeColor(CGColor(red: 0.80, green: 0.95, blue: 1.0, alpha: 0.85))
    ctx.addPath(capPath)
    ctx.strokePath()
    ctx.restoreGState()

    // Akku-Körper Glasboden (Frosted Glass Container)
    ctx.saveGState()
    ctx.addPath(batteryBodyPath)
    ctx.clip()

    let glassBaseColors: [CGColor] = [
        CGColor(red: 0.10, green: 0.28, blue: 0.45, alpha: 0.60),
        CGColor(red: 0.02, green: 0.12, blue: 0.22, alpha: 0.80)
    ]
    if let gGrad = CGGradient(colorsSpace: colorSpace, colors: glassBaseColors as CFArray, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gGrad, start: CGPoint(x: bodyX, y: batteryBodyRect.maxY), end: CGPoint(x: bodyX, y: bodyY), options: [])
    }
    ctx.restoreGState()

    // ==========================================
    // 4. Innerer Ladebereich & Leuchtender 20–80 % Balken
    // ==========================================
    let chamberPadding: CGFloat = 16
    let chamberRect = batteryBodyRect.insetBy(dx: chamberPadding, dy: chamberPadding)
    let chamberRadius: CGFloat = 32
    let chamberPath = CGPath(roundedRect: chamberRect, cornerWidth: chamberRadius, cornerHeight: chamberRadius, transform: nil)

    // Dunkler Laderaum Hintergrund & Kante
    ctx.saveGState()
    ctx.addPath(chamberPath)
    ctx.setFillColor(CGColor(red: 0.01, green: 0.04, blue: 0.10, alpha: 0.92))
    ctx.fillPath()
    ctx.setLineWidth(1.5)
    ctx.setStrokeColor(CGColor(red: 0.20, green: 0.48, blue: 0.70, alpha: 0.50))
    ctx.addPath(chamberPath)
    ctx.strokePath()
    ctx.restoreGState()

    // Prozentuale Aufteilung (0% bis 100%)
    let chamberWidth = chamberRect.width
    let x0 = chamberRect.minX
    let x20 = x0 + chamberWidth * 0.20
    let x80 = x0 + chamberWidth * 0.80

    // Innerer Inhalt des Laderaums
    ctx.saveGState()
    ctx.addPath(chamberPath)
    ctx.clip()

    // Inaktive Zonen dezent tönen
    let zone0_20 = CGRect(x: x0, y: chamberRect.minY, width: x20 - x0, height: chamberRect.height)
    ctx.setFillColor(CGColor(red: 0.02, green: 0.08, blue: 0.16, alpha: 0.65))
    ctx.fill(zone0_20)

    let zone80_100 = CGRect(x: x80, y: chamberRect.minY, width: chamberRect.maxX - x80, height: chamberRect.height)
    ctx.setFillColor(CGColor(red: 0.02, green: 0.08, blue: 0.16, alpha: 0.65))
    ctx.fill(zone80_100)

    // Angedeutete Akkuzellen-Linien
    ctx.setLineWidth(1.5)
    ctx.setStrokeColor(CGColor(red: 0.15, green: 0.35, blue: 0.55, alpha: 0.40))
    for p in [0.07, 0.14, 0.86, 0.93] {
        let xPos = x0 + chamberWidth * CGFloat(p)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: xPos, y: chamberRect.minY + 6))
        ctx.addLine(to: CGPoint(x: xPos, y: chamberRect.maxY - 6))
        ctx.strokePath()
    }

    // 20–80 % LEUCHTENDER LADEBEREICH (Guard Zone)
    let barInsetY: CGFloat = 6
    let barRect = CGRect(
        x: x20,
        y: chamberRect.minY + barInsetY,
        width: x80 - x20,
        height: chamberRect.height - (barInsetY * 2)
    )
    let barRadius: CGFloat = 18
    let barPath = CGPath(roundedRect: barRect, cornerWidth: barRadius, cornerHeight: barRadius, transform: nil)

    // Intensiver äußerer Neon-Glow
    ctx.saveGState()
    ctx.setShadow(
        offset: .zero,
        blur: 42,
        color: CGColor(red: 0.0, green: 0.95, blue: 0.92, alpha: 0.95)
    )
    ctx.addPath(barPath)
    ctx.setFillColor(CGColor(red: 0.0, green: 0.95, blue: 0.90, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // Zweiter scharfer Nahfeld-Glow
    ctx.saveGState()
    ctx.setShadow(
        offset: .zero,
        blur: 16,
        color: CGColor(red: 0.50, green: 1.0, blue: 0.95, alpha: 0.98)
    )
    ctx.addPath(barPath)
    ctx.setFillColor(CGColor(red: 0.25, green: 0.98, blue: 0.85, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // Füllung: Lebendiger Türkis-Cyan-Gradient
    ctx.saveGState()
    ctx.addPath(barPath)
    ctx.clip()

    let barColors: [CGColor] = [
        CGColor(red: 0.0, green: 0.98, blue: 0.96, alpha: 1.0), // Strahlendes Cyan
        CGColor(red: 0.08, green: 0.92, blue: 0.70, alpha: 1.0), // Smaragd-Türkis
        CGColor(red: 0.0, green: 0.80, blue: 0.98, alpha: 1.0)  // Elektrisches Cyanblau
    ]
    if let barGrad = CGGradient(colorsSpace: colorSpace, colors: barColors as CFArray, locations: [0.0, 0.48, 1.0]) {
        ctx.drawLinearGradient(barGrad, start: CGPoint(x: barRect.minX, y: barRect.maxY), end: CGPoint(x: barRect.maxX, y: barRect.minY), options: [])
    }

    // Flüssig-Glanzkante auf der oberen Hälfte des Ladebalkens
    let barHighlightRect = CGRect(x: barRect.minX, y: barRect.midY, width: barRect.width, height: barRect.height / 2)
    ctx.saveGState()
    ctx.clip(to: barHighlightRect)
    let hlColors: [CGColor] = [
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.65),
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.08)
    ]
    if let hlGrad = CGGradient(colorsSpace: colorSpace, colors: hlColors as CFArray, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(hlGrad, start: CGPoint(x: barRect.midX, y: barRect.maxY), end: CGPoint(x: barRect.midX, y: barRect.midY), options: [])
    }
    ctx.restoreGState()
    ctx.restoreGState() // Ende barPath clip

    // Begrenzungskanten & Limit-Pins bei 20 % und 80 %
    for (xVal, isLeft) in [(x20, true), (x80, false)] {
        ctx.saveGState()
        ctx.setLineWidth(3.0)
        ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95))
        ctx.setShadow(offset: .zero, blur: 10, color: CGColor(red: 0.0, green: 0.95, blue: 1.0, alpha: 0.9))
        ctx.beginPath()
        ctx.move(to: CGPoint(x: xVal, y: chamberRect.minY + 2))
        ctx.addLine(to: CGPoint(x: xVal, y: chamberRect.maxY - 2))
        ctx.strokePath()

        // Schützende Limit-Kerben
        let notch: CGFloat = 10
        ctx.beginPath()
        ctx.move(to: CGPoint(x: xVal - (isLeft ? 0 : notch), y: chamberRect.maxY - 2))
        ctx.addLine(to: CGPoint(x: xVal + (isLeft ? notch : 0), y: chamberRect.maxY - 2))
        ctx.move(to: CGPoint(x: xVal - (isLeft ? 0 : notch), y: chamberRect.minY + 2))
        ctx.addLine(to: CGPoint(x: xVal + (isLeft ? notch : 0), y: chamberRect.minY + 2))
        ctx.strokePath()
        ctx.restoreGState()
    }

    // Zentrum: Schutzschild & Energieblitz
    ctx.saveGState()
    let symCenter = CGPoint(x: barRect.midX, y: barRect.midY)
    let sWidth: CGFloat = 64
    let sHeight: CGFloat = 80

    let shieldPath = CGMutablePath()
    shieldPath.move(to: CGPoint(x: symCenter.x, y: symCenter.y + sHeight * 0.48))
    shieldPath.addLine(to: CGPoint(x: symCenter.x + sWidth * 0.5, y: symCenter.y + sHeight * 0.32))
    shieldPath.addLine(to: CGPoint(x: symCenter.x + sWidth * 0.5, y: symCenter.y - sHeight * 0.05))
    shieldPath.addQuadCurve(
        to: CGPoint(x: symCenter.x, y: symCenter.y - sHeight * 0.50),
        control: CGPoint(x: symCenter.x + sWidth * 0.4, y: symCenter.y - sHeight * 0.35)
    )
    shieldPath.addQuadCurve(
        to: CGPoint(x: symCenter.x - sWidth * 0.5, y: symCenter.y - sHeight * 0.05),
        control: CGPoint(x: symCenter.x - sWidth * 0.4, y: symCenter.y - sHeight * 0.35)
    )
    shieldPath.addLine(to: CGPoint(x: symCenter.x - sWidth * 0.5, y: symCenter.y + sHeight * 0.32))
    shieldPath.closeSubpath()

    // Strahlender Schild
    ctx.setShadow(offset: .zero, blur: 16, color: CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.90))
    ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.98))
    ctx.addPath(shieldPath)
    ctx.fillPath()

    // Blitz im Schild
    let boltPath = CGMutablePath()
    boltPath.move(to: CGPoint(x: symCenter.x + 4, y: symCenter.y + 22))
    boltPath.addLine(to: CGPoint(x: symCenter.x - 14, y: symCenter.y + 1))
    boltPath.addLine(to: CGPoint(x: symCenter.x - 3, y: symCenter.y + 1))
    boltPath.addLine(to: CGPoint(x: symCenter.x - 6, y: symCenter.y - 22))
    boltPath.addLine(to: CGPoint(x: symCenter.x + 14, y: symCenter.y - 3))
    boltPath.addLine(to: CGPoint(x: symCenter.x + 3, y: symCenter.y - 3))
    boltPath.closeSubpath()

    ctx.setFillColor(CGColor(red: 0.01, green: 0.35, blue: 0.48, alpha: 1.0))
    ctx.addPath(boltPath)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.restoreGState() // ENDE chamberPath clip

    // Innerer Glass-Glanz über dem Akku
    ctx.saveGState()
    let glossPath = CGMutablePath()
    glossPath.move(to: CGPoint(x: batteryBodyRect.minX, y: batteryBodyRect.maxY - bodyRadius))
    glossPath.addArc(
        tangent1End: CGPoint(x: batteryBodyRect.minX, y: batteryBodyRect.maxY),
        tangent2End: CGPoint(x: batteryBodyRect.minX + bodyRadius, y: batteryBodyRect.maxY),
        radius: bodyRadius
    )
    glossPath.addLine(to: CGPoint(x: batteryBodyRect.maxX - bodyRadius, y: batteryBodyRect.maxY))
    glossPath.addArc(
        tangent1End: CGPoint(x: batteryBodyRect.maxX, y: batteryBodyRect.maxY),
        tangent2End: CGPoint(x: batteryBodyRect.maxX, y: batteryBodyRect.maxY - bodyRadius),
        radius: bodyRadius
    )
    glossPath.addLine(to: CGPoint(x: batteryBodyRect.maxX, y: batteryBodyRect.midY + 25))
    glossPath.addQuadCurve(
        to: CGPoint(x: batteryBodyRect.minX, y: batteryBodyRect.midY + 25),
        control: CGPoint(x: batteryBodyRect.midX, y: batteryBodyRect.midY - 15)
    )
    glossPath.closeSubpath()

    ctx.addPath(glossPath)
    ctx.clip()
    let glassGlossColors: [CGColor] = [
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.45),
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.08),
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0)
    ]
    if let glossGrad = CGGradient(colorsSpace: colorSpace, colors: glassGlossColors as CFArray, locations: [0.0, 0.45, 1.0]) {
        ctx.drawLinearGradient(glossGrad, start: CGPoint(x: batteryBodyRect.midX, y: batteryBodyRect.maxY), end: CGPoint(x: batteryBodyRect.midX, y: batteryBodyRect.midY), options: [])
    }
    ctx.restoreGState()

    // Akku-Gehäuse Lichtrand (Frosted Glass Border)
    ctx.saveGState()
    ctx.setLineWidth(4.0)
    ctx.setStrokeColor(CGColor(red: 0.70, green: 0.92, blue: 1.0, alpha: 0.70))
    ctx.addPath(batteryBodyPath)
    ctx.strokePath()
    ctx.restoreGState()

    // ==========================================
    // 5. Typografische Badges: 20 % und 80 % (Auf der Squircle-Ebene!)
    // ==========================================
    let badgeY: CGFloat = bodyY - 80
    let badgeHeight: CGFloat = 44
    let badgeFont = NSFont.systemFont(ofSize: 24, weight: .bold)

    func drawPill(text: String, centerX: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: badgeFont,
            .foregroundColor: NSColor(calibratedRed: 0.92, green: 1.0, blue: 0.98, alpha: 1.0)
        ]
        let astr = NSAttributedString(string: text, attributes: attrs)
        let textSize = astr.size()
        let pillWidth = textSize.width + 42
        let pillRect = CGRect(x: centerX - pillWidth / 2, y: badgeY, width: pillWidth, height: badgeHeight)
        let pillPath = CGPath(roundedRect: pillRect, cornerWidth: badgeHeight / 2, cornerHeight: badgeHeight / 2, transform: nil)

        ctx.saveGState()
        // Pill-Schatten
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: CGColor(red: 0.0, green: 0.02, blue: 0.08, alpha: 0.60))
        ctx.addPath(pillPath)
        ctx.setFillColor(CGColor(red: 0.02, green: 0.16, blue: 0.30, alpha: 0.88))
        ctx.fillPath()

        // Pill-Umrandung (Glänzendes Cyan)
        ctx.setLineWidth(2.0)
        ctx.setStrokeColor(CGColor(red: 0.0, green: 0.88, blue: 0.98, alpha: 0.80))
        ctx.addPath(pillPath)
        ctx.strokePath()

        // Text zentrieren
        let textRect = CGRect(
            x: pillRect.midX - textSize.width / 2,
            y: pillRect.midY - textSize.height / 2 + 1,
            width: textSize.width,
            height: textSize.height
        )
        astr.draw(in: textRect)
        ctx.restoreGState()
    }

    drawPill(text: "20%", centerX: x20)
    drawPill(text: "80%", centerX: x80)

    // Ein verbindender subtiler Guard-Statusindikator zwischen den Badges
    let rangeAstr = NSAttributedString(
        string: "GUARD RANGE",
        attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .heavy),
            .foregroundColor: NSColor(calibratedRed: 0.0, green: 0.92, blue: 0.98, alpha: 0.95)
        ]
    )
    let rangeSize = rangeAstr.size()
    let rangeX = (x20 + x80) / 2 - rangeSize.width / 2
    let rangeRect = CGRect(x: rangeX, y: badgeY + 13, width: rangeSize.width, height: rangeSize.height)
    rangeAstr.draw(in: rangeRect)

    // ==========================================
    // 6. Äußerer Bevel & Glanzrand um das Squircle
    // ==========================================
    ctx.saveGState()
    // Oben glänzender Catchlight-Rand
    ctx.setLineWidth(3.0)
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.45))
    ctx.addPath(squirclePath)
    ctx.strokePath()

    // Äußere innere Vignette am Rand
    let rimColors: [CGColor] = [
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.15),
        CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0),
        CGColor(red: 0.0, green: 0.02, blue: 0.08, alpha: 0.35)
    ]
    if let rimGrad = CGGradient(colorsSpace: colorSpace, colors: rimColors as CFArray, locations: [0.0, 0.85, 1.0]) {
        ctx.drawRadialGradient(
            rimGrad,
            startCenter: CGPoint(x: 512, y: 512),
            startRadius: 360,
            endCenter: CGPoint(x: 512, y: 512),
            endRadius: 420,
            options: []
        )
    }
    ctx.restoreGState()

    ctx.restoreGState() // Ende squircle clip

    image.unlockFocus()
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
