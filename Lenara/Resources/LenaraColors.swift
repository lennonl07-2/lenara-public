import SwiftUI
import UIKit

struct LenaraColors {
    static let background = Color(red: 0.075, green: 0.137, blue: 0.102) // bosque profundo
    static let surface = Color(red: 0.125, green: 0.196, blue: 0.149)
    static let userBubble = Color(red: 0.176, green: 0.267, blue: 0.196)
    static let textPrimary = Color(red: 0.949, green: 0.953, blue: 0.918)
    static let textSecondary = Color(red: 0.745, green: 0.792, blue: 0.741)
    static let textTertiary = Color(red: 0.604, green: 0.671, blue: 0.612)
    static let accent = Color(red: 0.690, green: 0.804, blue: 0.686)
    static let logoMint = Color(red: 0.42, green: 0.78, blue: 0.76)
    static let onAccent = Color(red: 0.10, green: 0.16, blue: 0.12)
    static let accentLight = accent.opacity(0.14)
    static let accentMedium = accent.opacity(0.28)
    static let divider = Color(red: 0.32, green: 0.40, blue: 0.33)
    static let success = Color(red: 0.50, green: 0.76, blue: 0.56)
    static let error = Color(red: 0.89, green: 0.47, blue: 0.43)
    static let warning = Color(red: 0.91, green: 0.70, blue: 0.39)
}

struct LenaraMark: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle()
                    .stroke(LenaraColors.textPrimary, style: StrokeStyle(lineWidth: size * 0.105, lineCap: .round))
                    .frame(width: size * 0.68, height: size * 0.68)
                    .offset(x: size * 0.07, y: size * 0.03)
                Path { path in
                    path.move(to: CGPoint(x: size * 0.29, y: size * 0.70))
                    path.addCurve(to: CGPoint(x: size * 0.23, y: size * 0.85), control1: CGPoint(x: size * 0.15, y: size * 0.85), control2: CGPoint(x: size * 0.17, y: size * 0.98))
                    path.addCurve(to: CGPoint(x: size * 0.43, y: size * 0.89), control1: CGPoint(x: size * 0.30, y: size * 0.76), control2: CGPoint(x: size * 0.37, y: size * 0.78))
                }
                .stroke(LenaraColors.textPrimary, style: StrokeStyle(lineWidth: size * 0.095, lineCap: .round, lineJoin: .round))
                Circle().fill(LenaraColors.logoMint).frame(width: size * 0.105, height: size * 0.105).offset(x: -size * 0.12, y: -size * 0.045)
                Circle().fill(LenaraColors.logoMint).frame(width: size * 0.105, height: size * 0.105).offset(x: size * 0.12, y: -size * 0.045)
                SmileShape().stroke(LenaraColors.logoMint, style: StrokeStyle(lineWidth: size * 0.085, lineCap: .round)).frame(width: size * 0.29, height: size * 0.16).offset(y: size * 0.13)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityHidden(true)
    }
}

private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

extension Font {
    static func rounded(_ style: Font.TextStyle) -> Font { .system(style, design: .rounded) }
}
