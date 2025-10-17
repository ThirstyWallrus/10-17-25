//
//  SparklineChart.swift
//  DynastyStatDrop
//
//  Lightweight pure SwiftUI micro visualizations (no external deps)
//  Sparkline, stacked bar, donut ring, heat grid.
//
//  NOTE: This version fixes the 'buildExpression is unavailable' compiler errors
//  caused by declaring a mutable local variable (`var start`) inside a result
//  builder (the ZStack of DonutChartMini). We now pre-compute angle segments
//  in a separate computed property so the body builder only emits Views.
//

import SwiftUI

// MARK: - SparklineChart

struct SparklineChart: View {
    let points: [Double]
    let stroke: Color
    let gradient: LinearGradient?
    let lineWidth: CGFloat
    let smooth: Bool   // (Reserved for future smoothing implementation)

    init(points: [Double],
         stroke: Color = .orange,
         gradient: LinearGradient? = nil,
         lineWidth: CGFloat = 2,
         smooth: Bool = false) {
        self.points = points
        self.stroke = stroke
        self.gradient = gradient
        self.lineWidth = lineWidth
        self.smooth = smooth
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let values = normalized(points: points)
            ZStack {
                if let gradient {
                    Path { path in
                        guard values.count > 1 else { return }
                        path.move(to: CGPoint(x: 0, y: y(values[0], h)))
                        for i in 1..<values.count {
                            path.addLine(to: CGPoint(
                                x: x(i, count: values.count, width: w),
                                y: y(values[i], h)
                            ))
                        }
                        path.addLine(to: CGPoint(x: w, y: h))
                        path.addLine(to: CGPoint(x: 0, y: h))
                        path.closeSubpath()
                    }
                    .fill(gradient.opacity(0.25))
                }

                Path { path in
                    guard values.count > 1 else { return }
                    path.move(to: CGPoint(x: 0, y: y(values[0], h)))
                    for i in 1..<values.count {
                        path.addLine(to: CGPoint(
                            x: x(i, count: values.count, width: w),
                            y: y(values[i], h)
                        ))
                    }
                }
                .stroke(
                    stroke,
                    style: StrokeStyle(lineWidth: lineWidth,
                                       lineCap: .round,
                                       lineJoin: .round)
                )
            }
        }
    }

    private func normalized(points: [Double]) -> [Double] {
        guard let minVal = points.min(),
              let maxVal = points.max(),
              maxVal - minVal > 0 else {
            return points.map { _ in 0.5 }
        }
        return points.map { ($0 - minVal) / (maxVal - minVal) }
    }

    private func x(_ index: Int, count: Int, width: CGFloat) -> CGFloat {
        guard count > 1 else { return 0 }
        return CGFloat(index) / CGFloat(count - 1) * width
    }

    private func y(_ value: Double, _ height: CGFloat) -> CGFloat {
        (1 - CGFloat(value)) * height
    }
}

// MARK: - StackedBarPercent

struct StackedBarPercent: View {
    let segments: [(color: Color, value: Double)]
    var body: some View {
        GeometryReader { geo in
            let total = segments.map { $0.value }.reduce(0,+)
            HStack(spacing: 0) {
                ForEach(0..<segments.count, id: \.self) { i in
                    let pct = total > 0 ? segments[i].value / total : 0
                    Rectangle()
                        .fill(segments[i].color)
                        .frame(width: geo.size.width * pct)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(height: 12)
    }
}

// MARK: - DonutChartMini (FIXED: no mutable var inside builder)

struct DonutChartMini: View {
    let segments: [(color: Color, value: Double)]
    let lineWidth: CGFloat

    init(segments: [(color: Color, value: Double)], lineWidth: CGFloat = 10) {
        self.segments = segments
        self.lineWidth = lineWidth
    }

    // Pre-compute the angle segments so the body only emits Views
    private var angleSegments: [(start: Angle, end: Angle, color: Color)] {
        let total = segments.map { $0.value }.reduce(0,+)
        guard total > 0 else { return [] }
        var cursor: Double = -90  // start at top
        return segments.map { seg in
            let fraction = seg.value / total
            let start = Angle(degrees: cursor)
            let end = Angle(degrees: cursor + fraction * 360)
            cursor += fraction * 360
            return (start, end, seg.color)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let radius = min(geo.size.width, geo.size.height) / 2
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
                ForEach(0..<angleSegments.count, id: \.self) { i in
                    CircleSegment(start: angleSegments[i].start, end: angleSegments[i].end)
                        .stroke(angleSegments[i].color,
                                style: StrokeStyle(lineWidth: lineWidth,
                                                   lineCap: .round))
                }
            }
            .frame(width: radius * 2, height: radius * 2)
        }
    }

    struct CircleSegment: Shape {
        let start: Angle
        let end: Angle
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                     radius: rect.width / 2,
                     startAngle: start,
                     endAngle: end,
                     clockwise: false)
            return p
        }
    }
}

// MARK: - HeatGrid

struct HeatGrid: View {
    let matrix: [[Double]]          // row-major
    let rowLabels: [String]
    let colLabels: [String]
    var color: Color = .orange

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("").frame(width: 30)
                ForEach(colLabels, id: \.self) { col in
                    Text(col)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                }
            }
            ForEach(matrix.indices, id: \.self) { r in
                HStack(spacing: 2) {
                    Text(rowLabels[r])
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .frame(width: 30, alignment: .leading)
                    ForEach(matrix[r].indices, id: \.self) { c in
                        Rectangle()
                            .fill(colorFor(value: matrix[r][c]))
                            .overlay(
                                Text(String(format: "%.1f", matrix[r][c]))
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundColor(.black.opacity(0.8))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .frame(height: 32)
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.4).blur(radius: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func colorFor(value: Double) -> Color {
        let maxVal = matrix.flatMap { $0 }.max() ?? 1
        let clamped = max(0, min(1, value / maxVal))
        return Color(
            red: 1.0,
            green: Double(0.3 + 0.5 * (1 - clamped)),
            blue: Double(0.1 + 0.5 * (1 - clamped))
        ).opacity(0.85)
    }
}
