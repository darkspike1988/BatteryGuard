import SwiftUI

struct BatteryRangeSlider: View {
    @Binding var lowerLimit: Int
    @Binding var upperLimit: Int
    @Binding var isEnabled: Bool
    var currentPercent: Int? = nil
    
    private let minSpacing: Int = 5
    
    @State private var dragStartLower: Int? = nil
    @State private var dragStartUpper: Int? = nil
    @State private var isDraggingLower: Bool = false
    @State private var isDraggingUpper: Bool = false
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    init(
        lowerLimit: Binding<Int>,
        upperLimit: Binding<Int>,
        isEnabled: Binding<Bool>,
        currentPercent: Int? = nil
    ) {
        self._lowerLimit = lowerLimit
        self._upperLimit = upperLimit
        self._isEnabled = isEnabled
        self.currentPercent = currentPercent
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Live-Werteanzeige
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.blue)
                    Text("Laden ab")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(lowerLimit) %")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.to.line")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                    Text("Stoppen bei")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(upperLimit) %")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                }
            }
            .padding(.horizontal, 2)
            
            // Batterie-Balken als Glas-Kapsel mit Custom Drag Handles
            GeometryReader { geo in
                let thumbRadius: CGFloat = 12
                let trackPadding: CGFloat = thumbRadius
                let availableWidth = max(geo.size.width - (trackPadding * 2), 1)
                
                let lowerFraction = CGFloat(lowerLimit) / 100.0
                let upperFraction = CGFloat(upperLimit) / 100.0
                let lowerX = trackPadding + (lowerFraction * availableWidth)
                let upperX = trackPadding + (upperFraction * availableWidth)
                
                ZStack(alignment: .leading) {
                    // Glas-Kapsel Basis (Track)
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .frame(height: 20)
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.30),
                                            Color.white.opacity(0.08)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.5
                                )
                        )
                        .padding(.horizontal, trackPadding - 2)
                    
                    // Leuchtender aktiver Schutzbereich (zwischen Min und Max)
                    if isEnabled && upperX > lowerX {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.15, green: 0.70, blue: 0.85),
                                        Color(red: 0.20, green: 0.82, blue: 0.40)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(upperX - lowerX, 0), height: 15)
                            .shadow(color: Color.green.opacity(0.40), radius: 5, x: 0, y: 1)
                            .offset(x: lowerX)
                    }
                    
                    // Live-Akku-Markierung (wenn verfügbar)
                    if let cur = currentPercent {
                        let curFraction = CGFloat(min(max(cur, 0), 100)) / 100.0
                        let curX = trackPadding + (curFraction * availableWidth)
                        Capsule()
                            .fill(Color.white.opacity(0.90))
                            .frame(width: 2.5, height: 20)
                            .shadow(color: Color.white.opacity(0.6), radius: 2)
                            .offset(x: curX - 1.25)
                    }
                    
                    // Min-Griff (Ladebeginn)
                    GlassSliderHandle(
                        icon: "arrowtriangle.right.fill",
                        color: .blue,
                        isDragging: isDraggingLower,
                        reduceMotion: reduceMotion
                    )
                    .offset(x: lowerX - thumbRadius)
                    .help("Ladebeginn: Der Akku wird erst wieder geladen, wenn er unter diesen Wert fällt.")
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard isEnabled else { return }
                                if dragStartLower == nil {
                                    dragStartLower = lowerLimit
                                    isDraggingLower = true
                                }
                                let start = dragStartLower ?? lowerLimit
                                let delta = Int(round((value.translation.width / availableWidth) * 100.0))
                                let raw = start + delta
                                let maxAllowed = min(95, upperLimit - minSpacing)
                                lowerLimit = min(max(raw, 5), maxAllowed)
                            }
                            .onEnded { _ in
                                dragStartLower = nil
                                isDraggingLower = false
                            }
                    )
                    
                    // Max-Griff (Ladestopp)
                    GlassSliderHandle(
                        icon: "arrowtriangle.left.fill",
                        color: .green,
                        isDragging: isDraggingUpper,
                        reduceMotion: reduceMotion
                    )
                    .offset(x: upperX - thumbRadius)
                    .help("Ladestopp: Der Ladevorgang wird bei diesem Wert gestoppt.")
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard isEnabled else { return }
                                if dragStartUpper == nil {
                                    dragStartUpper = upperLimit
                                    isDraggingUpper = true
                                }
                                let start = dragStartUpper ?? upperLimit
                                let delta = Int(round((value.translation.width / availableWidth) * 100.0))
                                let raw = start + delta
                                let minAllowed = max(20, lowerLimit + minSpacing)
                                upperLimit = min(max(raw, minAllowed), 100)
                            }
                            .onEnded { _ in
                                dragStartUpper = nil
                                isDraggingUpper = false
                            }
                    )
                }
                .frame(height: 26)
            }
            .frame(height: 26)
            .opacity(isEnabled ? 1.0 : 0.45)
            
            // Preset-Chips als Glas-Kapseln
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                GlassPresetChip(
                    title: "20–80 Standard",
                    isActive: isEnabled && lowerLimit == 20 && upperLimit == 80
                ) {
                    isEnabled = true
                    lowerLimit = 20
                    upperLimit = 80
                }
                
                GlassPresetChip(
                    title: "40–80 Dauerbetrieb",
                    isActive: isEnabled && lowerLimit == 40 && upperLimit == 80
                ) {
                    isEnabled = true
                    lowerLimit = 40
                    upperLimit = 80
                }
                
                GlassPresetChip(
                    title: "50–90 Komfort",
                    isActive: isEnabled && lowerLimit == 50 && upperLimit == 90
                ) {
                    isEnabled = true
                    lowerLimit = 50
                    upperLimit = 90
                }
                
                GlassPresetChip(
                    title: "0–100 Aus",
                    isActive: !isEnabled
                ) {
                    isEnabled = false
                }
            }
        }
        .padding(12)
        .adaptiveGlassCard(cornerRadius: 14)
    }
}

// MARK: - Glas-Griff mit Lichtreflex-Gradient & 0.5pt Innen-Stroke

private struct GlassSliderHandle: View {
    let icon: String
    let color: Color
    let isDragging: Bool
    let reduceMotion: Bool
    
    var body: some View {
        ZStack {
            // Basis
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 24, height: 24)
            
            // Lichtreflex-Gradient (Highlight oben)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.85),
                            Color.white.opacity(0.35),
                            Color.white.opacity(0.12)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 24, height: 24)
            
            // Äußere Farbkante
            Circle()
                .strokeBorder(color.opacity(0.80), lineWidth: 1.5)
                .frame(width: 24, height: 24)
            
            // 0.5pt Innen-Stroke weiß 30 %
            Circle()
                .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5)
                .frame(width: 23, height: 23)
            
            // Symbol im Zentrum
            Image(systemName: icon)
                .font(.system(size: 8.5, weight: .black))
                .foregroundStyle(color)
        }
        .shadow(color: Color.black.opacity(0.24), radius: 3.5, x: 0, y: 1.5)
        .scaleEffect(isDragging ? 1.20 : 1.0)
        .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.68), value: isDragging)
    }
}

// MARK: - Preset-Chip als Glas-Kapsel

private struct GlassPresetChip: View {
    let title: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5.5)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule()
                        .fill(isActive ? Color.accentColor.opacity(0.20) : Color.primary.opacity(0.04))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    isActive ? Color.white.opacity(0.45) : Color.white.opacity(0.20),
                                    isActive ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.05)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: isActive ? Color.accentColor.opacity(0.22) : Color.clear, radius: 3)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
