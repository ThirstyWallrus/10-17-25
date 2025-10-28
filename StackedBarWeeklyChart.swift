//
//  StackedBarWeeklyChart.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 10/28/25.
//


//
//  StackedBarWeeklyChart.swift
//  DynastyStatDrop
//
//  Reusable stacked bar chart for weekly position breakdowns.
//  - Each bar = one week, segments colored per position
//  - Supports tooltip on tap
//  - Always fits all bars in available width
//  - Custom horizontal grid lines and chart top value
//

import SwiftUI

public struct StackedBarWeeklyChart: View {
    public struct WeekBarData: Identifiable {
        public let id: Int      // week number, 1-based
        public let segments: [Segment]
        public struct Segment: Identifiable {
            public let id: String
            public let position: String // canonical position (QB, RB, etc)
            public let value: Double
        }
        public let total: Double
        public init(id: Int, segments: [Segment]) {
            self.id = id
            self.segments = segments
            self.total = segments.reduce(0) { $0 + $1.value }
        }
    }
    
    public let weekBars: [WeekBarData]         // oldest to newest (left to right)
    public let positionColors: [String: Color] // normalized position -> Color
    public let gridLines: [Double]             // e.g. [100, 200, 300]
    public let chartTop: Double                // e.g. 400
    public let showPositions: Set<String>      // which positions to display per bar
    public let barSpacing: CGFloat             // space between bars
    public let tooltipFont: Font               // font for tooltip
    public let showWeekLabels: Bool            // show week numbers below bars

    @State private var tappedWeek: Int? = nil

    public init(
        weekBars: [WeekBarData],
        positionColors: [String: Color],
        gridLines: [Double],
        chartTop: Double,
        showPositions: Set<String>,
        barSpacing: CGFloat = 4,
        tooltipFont: Font = .caption2.bold(),
        showWeekLabels: Bool = true
    ) {
        self.weekBars = weekBars
        self.positionColors = positionColors
        self.gridLines = gridLines
        self.chartTop = chartTop
        self.showPositions = showPositions
        self.barSpacing = barSpacing
        self.tooltipFont = tooltipFont
        self.showWeekLabels = showWeekLabels
    }

    public var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let barCount = weekBars.count
                let barWidth = barCount > 0 ? (w - CGFloat(barCount - 1) * barSpacing) / CGFloat(barCount) : 0

                ZStack {
                    // Grid lines
                    ForEach(gridLines, id: \.self) { lineValue in
                        let y = h - CGFloat(lineValue / chartTop) * h
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: w, y: y))
                        }
                        .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 2]))
                        Text("\(Int(lineValue))")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.40))
                            .position(x: 28, y: y - 8)
                    }
                    
                    // Bars
                    HStack(alignment: .bottom, spacing: barSpacing) {
                        ForEach(weekBars) { weekBar in
                            VStack(spacing: 0) {
                                ZStack(alignment: .bottom) {
                                    ForEach(weekBar.segments.filter { showPositions.contains($0.position) }) { seg in
                                        let segHeight = CGFloat(seg.value / chartTop) * h
                                        Rectangle()
                                            .fill(positionColors[seg.position] ?? Color.gray)
                                            .frame(height: segHeight)
                                            .cornerRadius(segHeight > 8 ? 3 : 1)
                                    }
                                }
                                .frame(width: barWidth, height: h)
                                .contentShape(Rectangle())
                                .onTapGesture { tappedWeek = weekBar.id }
                                
                                if showWeekLabels {
                                    Text("W\(weekBar.id)")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.45))
                                        .frame(height: 16)
                                }
                            }
                            .frame(width: barWidth)
                        }
                    }
                    
                    // Tooltip
                    if let t = tappedWeek, let weekBar = weekBars.first(where: { $0.id == t }) {
                        let idx = weekBars.firstIndex(where: { $0.id == t }) ?? 0
                        let x = CGFloat(idx) * (barWidth + barSpacing) + barWidth / 2
                        let tooltipY: CGFloat = {
                            // Place above the bar's top
                            let barTotal = weekBar.total
                            return h - CGFloat(barTotal / chartTop) * h - 40
                        }()
                        TooltipView(weekBar: weekBar, positionColors: positionColors, font: tooltipFont)
                            .position(x: min(max(70, x), w - 70), y: max(30, tooltipY))
                            .transition(.opacity.combined(with: .scale))
                            .onTapGesture { tappedWeek = nil }
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: tappedWeek)
            }
            .frame(height: 140)
        }
        .padding(.vertical, 8)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct TooltipView: View {
    let weekBar: StackedBarWeeklyChart.WeekBarData
    let positionColors: [String: Color]
    let font: Font
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("W\(weekBar.id) Breakdown")
                .font(font)
                .foregroundColor(.yellow)
            ForEach(weekBar.segments) { seg in
                HStack(spacing: 6) {
                    Circle()
                        .fill(positionColors[seg.position] ?? .gray)
                        .frame(width: 10, height: 10)
                    Text("\(seg.position): \(String(format: "%.1f", seg.value))")
                        .font(.caption2)
                        .foregroundColor(.white)
                }
            }
            Text("Total: \(String(format: "%.1f", weekBar.total))")
                .font(.caption2.bold())
                .foregroundColor(.cyan)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.90)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.22), lineWidth: 1))
        .foregroundColor(.white)
    }
}