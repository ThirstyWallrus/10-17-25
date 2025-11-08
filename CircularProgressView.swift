//
//  CircularProgressView.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 11/8/25.
//


//
//  SharedBalanceComponents.swift
//  DynastyStatDrop
//
//  Shared UI components used by balance/info sheets.
//  Contains: CircularProgressView, visual effects, PositionGauge, BalanceGauge.
//

import SwiftUI

// MARK: - Circular / Decorative Visuals

public struct CircularProgressView: View {
    public var progress: Double
    public var tintColor: Color
    public var lineWidth: CGFloat = 5

    private var arcColor: Color {
        Color(hue: 0.333 - 0.333 * (1 - progress), saturation: 1, brightness: 1)
    }

    private var effectOverlay: some View {
        if progress >= 0.8 {
            AnyView(FlameEffect())
        } else if progress >= 0.6 {
            AnyView(GlowEffect(color: .green))
        } else {
            AnyView(IceEffect())
        }
    }

    private var backgroundCircle: some View {
        Circle()
            .stroke(Color.white.opacity(0.2), lineWidth: lineWidth)
    }

    private var progressArc: some View {
        Circle()
            .trim(from: 0, to: max(0, min(1, progress)))
            .stroke(arcColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }

    private var progressDot: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 8, height: 8)
            .offset(y: -30)
            .rotationEffect(.degrees(360 * progress - 90))
    }

    private var progressText: some View {
        Text(String(format: "%.2f%%", progress * 100))
            .font(.caption)
            .bold()
            .foregroundColor(.white)
    }

    public init(progress: Double, tintColor: Color, lineWidth: CGFloat = 5) {
        self.progress = progress
        self.tintColor = tintColor
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            backgroundCircle
            progressArc
            progressDot
            progressText
        }
        .frame(width: 60, height: 60)
        .overlay {
            effectOverlay
        }
    }
}

// MARK: - Visual Effects

public struct FlameBurst: View {
    let rotation: Angle

    public var body: some View {
        FlameShape()
            .fill(LinearGradient(gradient: Gradient(colors: [.yellow, .orange, .red]), startPoint: .bottom, endPoint: .top))
            .frame(width: 10, height: 20)
            .offset(y: -35)
            .rotationEffect(rotation)
            .blur(radius: 1)
    }
}

public struct FlameEffect: View {
    private var outerFlameRing: some View {
        Circle()
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [.red, .orange, .yellow, .orange, .red]),
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(360)
                ),
                style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 4])
            )
            .blur(radius: 2)
            .frame(width: 70, height: 70)
    }

    private var innerFlameBursts: some View {
        ZStack {
            ForEach(0..<6) { i in
                FlameBurst(rotation: .degrees(Double(i) * 60 - 90))
            }
        }
    }

    public var body: some View {
        ZStack {
            outerFlameRing
            innerFlameBursts
        }
    }
}

public struct FlameShape: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

public struct GlowEffect: View {
    public let color: Color

    private var glowStroke: some View {
        Circle()
            .stroke(color, lineWidth: 2)
            .blur(radius: 4)
            .frame(width: 70, height: 70)
    }

    private var glowFill: some View {
        Circle()
            .fill(color.opacity(0.2))
            .blur(radius: 6)
            .frame(width: 68, height: 68)
    }

    public init(color: Color) { self.color = color }

    public var body: some View {
        glowStroke
            .overlay(glowFill)
    }
}

public struct IcicleBurst: View {
    let i: Int

    public var body: some View {
        IcicleShape()
            .fill(LinearGradient(gradient: Gradient(colors: [.white, .cyan, .blue]), startPoint: .top, endPoint: .bottom))
            .frame(width: 8, height: 15 + CGFloat(i * 2))
            .offset(x: CGFloat(Double(i * 15) - 22.5), y: 30)
            .blur(radius: 0.5)
    }
}

public struct IceEffect: View {
    private var frostyOverlay: some View {
        Circle()
            .fill(Color.blue.opacity(0.1))
            .blur(radius: 3)
            .frame(width: 60, height: 60)
    }

    private var outerIceBorder: some View {
        Circle()
            .stroke(Color.cyan.opacity(0.5), lineWidth: 3)
            .blur(radius: 2)
            .frame(width: 70, height: 70)
    }

    private var icicles: some View {
        ZStack {
            ForEach(0..<4) { i in
                IcicleBurst(i: i)
            }
        }
    }

    public var body: some View {
        ZStack {
            frostyOverlay
            outerIceBorder
            icicles
        }
    }
}

public struct IcicleShape: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.maxY + 5))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        return path
    }
}

// MARK: - Position / Balance Gauges (shared)

public struct PositionGauge: View {
    public let pos: String
    public let pct: Double
    public let color: Color

    public init(pos: String, pct: Double, color: Color) {
        self.pos = pos
        self.pct = pct
        self.color = color
    }

    public var body: some View {
        VStack(spacing: 4) {
            CircularProgressView(progress: pct / 100.0, tintColor: color)
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(pos)
                    .font(.caption2)
                    .bold()
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .frame(width: 80)
    }
}

public struct BalanceGauge: View {
    public let balance: Double

    public init(balance: Double) {
        self.balance = balance
    }

    private var color: Color {
        balance < 8 ? .green : (balance < 16 ? .yellow : .red)
    }

    public var body: some View {
        VStack(spacing: 4) {
            CircularProgressView(progress: balance / 100.0, tintColor: color)
            // Invisible placeholder to match height and alignment
            Text(" ")
                .font(.caption2)
                .bold()
                .foregroundColor(.clear)
        }
        .frame(width: 80)
    }
}