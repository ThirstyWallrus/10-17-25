// OffPositionBalanceDetailSheet.swift
// DynastyStatDrop
//
// Created by Dynasty Stat Drop on 11/6/25.

import SwiftUI

struct OffPositionBalanceDetailSheet: View {
    let positionPercents: [String: Double]
    let balancePercent: Double
    let tagline: String

    // Sort positions so we always show QB, RB, WR, TE, K in that order
    private var orderedPositions: [String] { ["QB","RB","WR","TE","K"] }

    // For consistent color mapping use same token as OffStatExpandedView
    private var positionColors: [String: Color] {
        [
            "QB": .red,
            "RB": .green,
            "WR": .blue,
            "TE": .yellow,
            "K": Color.purple
        ]
    }

    var body: some View {
        VStack(spacing: 12) {
            Capsule().fill(Color.white.opacity(0.15)).frame(width: 40, height: 6).padding(.top, 8)
            Text("Offensive Efficiency Spotlight")
                .font(.headline)
                .foregroundColor(.yellow)

            HStack(spacing: 10) {
                PositionGauge(pos: "QB", pct: positionPercents["QB"] ?? 0, color: positionColors["QB"]!)
                PositionGauge(pos: "RB", pct: positionPercents["RB"] ?? 0, color: positionColors["RB"]!)
                PositionGauge(pos: "WR", pct: positionPercents["WR"] ?? 0, color: positionColors["WR"]!)
            }

            HStack(spacing: 10) {
                PositionGauge(pos: "TE", pct: positionPercents["TE"] ?? 0, color: positionColors["TE"]!)
                BalanceGauge(balance: balancePercent)
                PositionGauge(pos: "K", pct: positionPercents["K"] ?? 0, color: positionColors["K"]!)
            }

            Text(tagline)
                .font(.caption2)
                .foregroundColor(.yellow)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer(minLength: 8)
        }
        .padding(.bottom, 12)
        .background(Color.black)
    }
}

struct CircularProgressView: View {
    var progress: Double
    var tintColor: Color
    var lineWidth: CGFloat = 5

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
            .trim(from: 0, to: progress)
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

    var body: some View {
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

struct FlameBurst: View {
    let rotation: Angle
    
    var body: some View {
        FlameShape()
            .fill(LinearGradient(gradient: Gradient(colors: [.yellow, .orange, .red]), startPoint: .bottom, endPoint: .top))
            .frame(width: 10, height: 20)
            .offset(y: -35)
            .rotationEffect(rotation)
            .blur(radius: 1)
    }
}

struct FlameEffect: View {
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

    var body: some View {
        ZStack {
            outerFlameRing
            innerFlameBursts
        }
    }
}

struct FlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

struct GlowEffect: View {
    let color: Color

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

    var body: some View {
        glowStroke
            .overlay(glowFill)
    }
}

struct IcicleBurst: View {
    let i: Int
    
    var body: some View {
        IcicleShape()
            .fill(LinearGradient(gradient: Gradient(colors: [.white, .cyan, .blue]), startPoint: .top, endPoint: .bottom))
            .frame(width: 8, height: 15 + CGFloat(i * 2))
            .offset(x: CGFloat(Double(i * 15) - 22.5), y: 30)
            .blur(radius: 0.5)
    }
}

struct IceEffect: View {
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

    var body: some View {
        ZStack {
            frostyOverlay
            outerIceBorder
            icicles
        }
    }
}

struct IcicleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.maxY + 5))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        return path
    }
}

struct PositionGauge: View {
    let pos: String
    let pct: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            CircularProgressView(progress: pct / 100, tintColor: color)
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

struct BalanceGauge: View {
    let balance: Double

    private var color: Color {
        balance < 8 ? .green : (balance < 16 ? .yellow : .red)
    }

    var body: some View {
        VStack(spacing: 4) {
            CircularProgressView(progress: balance / 100, tintColor: color)
            // Invisible placeholder to match height and alignment
            Text(" ")
                .font(.caption2)
                .bold()
                .foregroundColor(.clear)
        }
        .frame(width: 80)
    }
}
