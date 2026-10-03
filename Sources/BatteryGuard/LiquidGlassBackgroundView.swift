import SwiftUI
import AppKit

struct LiquidGlassBackgroundView: View {
    let accentColor: Color
    let secondaryColor: Color
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    @State private var animateBlobs: Bool = false
    
    init(accentColor: Color, secondaryColor: Color) {
        self.accentColor = accentColor
        self.secondaryColor = secondaryColor
    }
    
    public var body: some View {
        ZStack {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                // Transluzente Grundebene
                Rectangle()
                    .fill(.ultraThinMaterial)
                
                Color(nsColor: .windowBackgroundColor).opacity(0.55)
                
                // Diffuse Farbkugeln / Blobs hinter dem Glas
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    
                    // Blob 1: Hauptakzent oben rechts / Mitte
                    Circle()
                        .fill(accentColor.opacity(0.30))
                        .frame(width: max(w * 0.75, 180), height: max(w * 0.75, 180))
                        .blur(radius: 50)
                        .offset(
                            x: (animateBlobs && !reduceMotion) ? w * 0.35 : w * 0.20,
                            y: (animateBlobs && !reduceMotion) ? -h * 0.12 : -h * 0.02
                        )
                    
                    // Blob 2: Sekundärakzent unten links
                    Circle()
                        .fill(secondaryColor.opacity(0.24))
                        .frame(width: max(w * 0.70, 160), height: max(w * 0.70, 160))
                        .blur(radius: 46)
                        .offset(
                            x: (animateBlobs && !reduceMotion) ? -w * 0.15 : -w * 0.25,
                            y: (animateBlobs && !reduceMotion) ? h * 0.40 : h * 0.30
                        )
                    
                    // Blob 3: Weicher Ausgleich zentriert
                    Circle()
                        .fill(accentColor.opacity(0.14))
                        .frame(width: max(w * 0.50, 120), height: max(w * 0.50, 120))
                        .blur(radius: 38)
                        .offset(
                            x: (animateBlobs && !reduceMotion) ? w * 0.08 : -w * 0.05,
                            y: (animateBlobs && !reduceMotion) ? h * 0.15 : h * 0.22
                        )
                }
                
                // Dünner Lichtreflex-Verlauf für zusätzliche optische Tiefe
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.clear,
                        Color.black.opacity(0.05)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 8.5).repeatForever(autoreverses: true)) {
                animateBlobs = true
            }
        }
    }
}
