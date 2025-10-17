//
//  TeamStatExpandedView.swift
//  DynastyStatDrop
//
//  Created by Dynasty Stat Drop on 8/25/25.
//


//
//  DSDDashboard_Subviews.swift
//  DynastyStatDrop
//
//  Subordinate subviews used by DSDDashboard (previously inlined).
//  Extracted for clarity. Logic unchanged except for removal of stray tokens.
//

import SwiftUI

// MARK: - TeamStatExpandedView

struct TeamStatExpandedView: View {
    let team: TeamStanding
    // Closure returns (optional) aggregated all time stats wrapper for this team
    let aggregatedAllTime: (TeamStanding) -> DSDDashboard.AggregatedTeamStats?
    
    @State private var showConsistencyInfo = false
    @State private var showEfficiencyInfo = false
    
    // Derived weekly totals (actual roster total per week)
    private var weeklyPoints: [Double] {
        let grouped = Dictionary(grouping: team.roster.flatMap { $0.weeklyScores }, by: { $0.week })
        return grouped.keys.sorted().map { wk in
            grouped[wk]?.reduce(0) { $0 + ($1.points_half_ppr ?? $1.points) } ?? 0
        }
    }
    
    private var weeksPlayed: Int { weeklyPoints.count }
    private var last3Avg: Double {
        guard weeksPlayed > 0 else { return 0 }
        return weeklyPoints.suffix(3).reduce(0,+) / Double(min(3, weeksPlayed))
    }
    private var seasonAvg: Double {
        guard weeksPlayed > 0 else { return team.teamPointsPerWeek }
        return weeklyPoints.reduce(0,+) / Double(weeksPlayed)
    }
    private var formDelta: Double { last3Avg - seasonAvg }
    private var managementPercent: Double {
        guard team.maxPointsFor > 0 else { return 0 }
        return (team.pointsFor / team.maxPointsFor) * 100
    }
    private var stdDev: Double {
        guard weeksPlayed > 1 else { return 0 }
        let mean = seasonAvg
        let variance = weeklyPoints.reduce(0) { $0 + pow($1 - mean, 2) } / Double(weeksPlayed)
        return sqrt(variance)
    }
    private var consistencyDescriptor: String {
        switch stdDev {
        case 0..<15: return "Steady"
        case 15..<35: return "Average"
        case 35..<55: return "Swingy"
        default: return "Boom-Bust"
        }
    }
    
    private var strengthsPills: [String] {
        var pills: [String] = []
        if managementPercent >= 80 { pills.append("Efficient Mgmt") }
        if let off = team.offensivePointsFor, let def = team.defensivePointsFor {
            if off > def + 75 { pills.append("High-Power Offense") }
            if def > off + 75 { pills.append("Stout Defense") }
        }
        if stdDev < 20 && weeksPlayed >= 4 { pills.append("Reliable Output") }
        if pills.isEmpty { pills.append("Developing Roster") }
        return pills
    }
    private var weaknessPills: [String] {
        var pills: [String] = []
        if managementPercent < 55 { pills.append("Mgmt Inefficiency") }
        if stdDev > 55 { pills.append("Volatile") }
        if pills.isEmpty { pills.append("No Major Weakness") }
        return pills
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            sectionHeader("Weekly Points Trend")
            WeeklyPointsTrend(points: weeklyPoints, accent: .yellow)
            sectionHeader("Lineup Efficiency")
            lineupEfficiency
            sectionHeader("Off vs Def Contribution")
            offDefContribution
            sectionHeader("Recent Form (Performance Momentum)")
            recentForm
            sectionHeader("Strengths")
            FlowLayoutCompat(items: strengthsPills) { Pill(text: $0, bg: Color.green.opacity(0.22), stroke: .green) }
            sectionHeader("Weaknesses")
            FlowLayoutCompat(items: weaknessPills) { Pill(text: $0, bg: Color.red.opacity(0.22), stroke: .red) }
            sectionHeader("Consistency Score")
            consistencyRow
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .sheet(isPresented: $showConsistencyInfo) {
            ConsistencyInfoSheet(stdDev: stdDev, descriptor: consistencyDescriptor)
                .presentationDetents([.fraction(0.40)])
        }
        .sheet(isPresented: $showEfficiencyInfo) {
            EfficiencyInfoSheet(managementPercent: managementPercent,
                                pointsFor: team.pointsFor,
                                maxPointsFor: team.maxPointsFor)
            .presentationDetents([.fraction(0.35)])
        }
    }
    
    private var header: some View {
        HStack(spacing: 12) {
            Text(team.winLossRecord ?? "0-0-0")
            Divider().frame(height: 10).background(Color.white.opacity(0.3))
            Text("PF \(Int(team.pointsFor))")
            Divider().frame(height: 10).background(Color.white.opacity(0.3))
            Text("PPW \(String(format: "%.2f", team.teamPointsPerWeek))")
        }
        .font(.caption)
        .foregroundColor(.white.opacity(0.85))
    }
    
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.yellow)
            .padding(.top, 4)
    }
    
    private var lineupEfficiency: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                statBlock(title: "PF", value: team.pointsFor)
                statBlock(title: "Max PF", value: team.maxPointsFor)
                statBlockPercent(title: "Mgmt%", value: managementPercent)
            }
            
            EfficiencyBar(ratio: managementPercent / 100.0, height: 12)
                .frame(height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    HStack {
                        Spacer()
                        Button { showEfficiencyInfo = true } label: {
                            Image(systemName: "info.circle")
                                .foregroundColor(.white.opacity(0.75))
                                .font(.caption)
                        }
                        .padding(.trailing, 4)
                    }
                )
        }
    }
    
    private var offDefContribution: some View {
        let off = team.offensivePointsFor ?? 0
        let def = team.defensivePointsFor ?? 0
        let total = max(1, off + def)
        return HStack(spacing: 20) {
            contributionBlock(label: "OFF", points: off, pct: off / total * 100, color: .orange)
            contributionBlock(label: "DEF", points: def, pct: def / total * 100, color: .cyan)
        }
        .font(.caption)
    }
    
    private var recentForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            let arrow = formDelta > 0.5 ? "↑" : (formDelta < -0.5 ? "↓" : "→")
            HStack(spacing: 10) {
                formStatBlock(name: "Last 3 Avg", value: last3Avg)
                formStatBlock(name: "Season Avg", value: seasonAvg)
                formDeltaBlock(delta: formDelta, arrow: arrow)
            }
            Text("Shows whether your recent scoring (last 3 weeks) is above or below your overall season average.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.55))
        }
    }
    
    private var consistencyRow: some View {
        HStack {
            HStack(spacing: 8) {
                Text(consistencyDescriptor)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Button { showConsistencyInfo = true } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            Spacer()
            ConsistencyMeter(stdDev: stdDev)
                .frame(width: 110, height: 12)
        }
    }
    
    private func statBlock(title: String, value: Double) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%.2f", value))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
    
    private func statBlockPercent(title: String, value: Double) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%.1f%%", value))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private func contributionBlock(label: String, points: Double, pct: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2).bold().foregroundColor(color)
            Text(String(format: "%.2f", points)).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
            Text(String(format: "%.1f%%", pct)).font(.caption2).foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
    
    private func formStatBlock(name: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%.2f", value))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            Text(name)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
    
    private func formDeltaBlock(delta: Double, arrow: String) -> some View {
        VStack(spacing: 2) {
            Text("\(arrow) \(String(format: "%+.2f", delta))")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(delta > 3 ? .green : (delta < -3 ? .red : .yellow))
            Text("Delta")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
    
    private struct Pill: View {
        let text: String
        let bg: Color
        let stroke: Color
        var body: some View {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(bg))
                .overlay(Capsule().stroke(stroke.opacity(0.7), lineWidth: 1))
                .foregroundColor(.white)
        }
    }
    
    private struct EfficiencyBar: View {
        let ratio: Double
        let height: CGFloat
        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: height/2)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: height/2)
                        .fill(LinearGradient(colors: [.red, .orange, .yellow, .green],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, min(geo.size.width, geo.size.width * ratio)))
                        .animation(.easeInOut(duration: 0.5), value: ratio)
                }
            }
        }
    }
    
    private struct ConsistencyMeter: View {
        let stdDev: Double
        private var norm: Double { max(0, min(1, stdDev / 80.0)) }
        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [.green, .yellow, .orange, .red],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * norm)
                }
            }
            .clipShape(Capsule())
        }
    }
}

// MARK: - OffDefStatExpandedView

struct OffDefStatExpandedView: View {
    enum Mode { case offense, defense }
    let team: TeamStanding
    let mode: Mode
    let league: LeagueData
    let personality: StatDropPersonality
    
    @State private var showConsistencyInfo = false
    @State private var showEfficiencyInfo = false
    
    private var positionSet: Set<String> {
        mode == .offense ? ["QB","RB","WR","TE","K"] : ["DL","LB","DB"]
    }
    
    private var sideWeeklyPoints: [Double] {
        let filteredScores = team.roster
            .filter { positionSet.contains($0.position) }
            .flatMap { $0.weeklyScores }
        let grouped = Dictionary(grouping: filteredScores, by: { $0.week })
        return grouped.keys.sorted().map { wk in
            grouped[wk]?.reduce(0) { $0 + ($1.points_half_ppr ?? $1.points) } ?? 0
        }
    }
    
    private var weeksPlayed: Int { sideWeeklyPoints.count }
    private var last3Avg: Double {
        guard weeksPlayed > 0 else { return 0 }
        return sideWeeklyPoints.suffix(3).reduce(0,+)/Double(min(3,weeksPlayed))
    }
    private var seasonAvg: Double {
        guard weeksPlayed > 0 else {
            return mode == .offense ? (team.averageOffensivePPW ?? 0) : (team.averageDefensivePPW ?? 0)
        }
        return sideWeeklyPoints.reduce(0,+)/Double(weeksPlayed)
    }
    private var formDelta: Double { last3Avg - seasonAvg }
    private var formDeltaColor: Color {
        if formDelta > 2 { return .green }
        if formDelta < -2 { return .red }
        return .yellow
    }
    
    private var sidePoints: Double {
        mode == .offense ? (team.offensivePointsFor ?? 0) : (team.defensivePointsFor ?? 0)
    }
    private var sideMaxPoints: Double {
        mode == .offense ? (team.maxOffensivePointsFor ?? 0) : (team.maxDefensivePointsFor ?? 0)
    }
    private var managementPercent: Double {
        guard sideMaxPoints > 0 else { return 0 }
        return (sidePoints / sideMaxPoints) * 100
    }

    private var stdDev: Double {
        guard weeksPlayed > 1 else { return 0 }
        let mean = seasonAvg
        let variance = sideWeeklyPoints.reduce(0) { $0 + pow($1 - mean, 2) } / Double(weeksPlayed)
        return sqrt(variance)
    }
    private var consistencyDescriptor: String {
        switch stdDev {
        case 0..<15: return "Steady"
        case 15..<35: return "Average"
        case 35..<55: return "Swingy"
        default: return "Boom-Bust"
        }
    }
    
    private var strengths: [String] {
        var arr: [String] = []
        if managementPercent >= 75 { arr.append("Efficient Usage") }
        if stdDev < 15 && weeksPlayed >= 4 { arr.append("Reliable Output") }
        if arr.isEmpty { arr.append("Developing Unit") }
        return arr
    }
    private var weaknesses: [String] {
        var arr: [String] = []
        if managementPercent < 55 { arr.append("Usage Inefficiency") }
        if stdDev > 40 { arr.append("Volatility") }
        if weeksPlayed >= 3 && last3Avg < seasonAvg - 5 { arr.append("Recent Dip") }
        if arr.isEmpty { arr.append("No Major Weakness") }
        return arr
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            sectionHeader("\(mode == .offense ? "Offensive" : "Defensive") Weekly Trend")
            WeeklyPointsTrend(points: sideWeeklyPoints, stroke: mode == .offense ? .red : .blue, accent: mode == .offense ? .orange : .cyan)
                .frame(height: 120)
            sectionHeader("Lineup Efficiency")
            lineupEfficiency
            sectionHeader("Recent Form")
            recentForm
            StatDropAnalysisBox(
                            team: team,
                            league: league,
                            context: mode == .offense ? .offense : .defense,
                            personality: personality
                        )
            sectionHeader("Consistency Score")
            consistencyRow
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .sheet(isPresented: $showConsistencyInfo) {
            ConsistencyInfoSheet(stdDev: stdDev, descriptor: consistencyDescriptor)
                .presentationDetents([.fraction(0.40)])
        }
        .sheet(isPresented: $showEfficiencyInfo) {
            EfficiencyInfoSheet(managementPercent: managementPercent,
                                pointsFor: sidePoints,
                                maxPointsFor: sideMaxPoints)
            .presentationDetents([.fraction(0.35)])
        }
    }
    
    private var header: some View {
        HStack(spacing: 12) {
            Text(mode == .offense
                 ? "OFF PF \(String(format: "%.2f", sidePoints))"
                 : "DEF PF \(String(format: "%.2f", sidePoints))")
            Divider().frame(height: 10).background(Color.white.opacity(0.3))
            Text("Avg \(String(format: "%.2f", seasonAvg))")
        }
        .font(.caption)
        .foregroundColor(.white.opacity(0.85))
    }
    
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.yellow)
            .padding(.top, 4)
    }
    
    private var lineupEfficiency: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                statBlock(title: "PF", value: sidePoints)
                statBlock(title: "Max", value: sideMaxPoints)
                statBlockPercent(title: "Mgmt%", value: managementPercent)
            }
            EfficiencyBar(ratio: managementPercent / 100.0, height: 12)
                .frame(height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    HStack {
                        Spacer()
                        Button { showEfficiencyInfo = true } label: {
                            Image(systemName: "info.circle")
                                .foregroundColor(.white.opacity(0.75))
                                .font(.caption)
                        }
                        .padding(.trailing, 4)
                    }
                )
        }
    }
    
    private var recentForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            let arrow = formDelta > 0.5 ? "↑" : (formDelta < -0.5 ? "↓" : "→")
            HStack(alignment: .top, spacing: 12) {
                formStatBlock("Last 3", last3Avg)
                formStatBlock("Season", seasonAvg)
                formDeltaBlock(arrow: arrow, delta: formDelta)
            }
            Text("Compares recent 3 weeks to season average for this unit.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.55))
        }
    }
    
    private var consistencyRow: some View {
        HStack {
            HStack(spacing: 8) {
                Text(consistencyDescriptor)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Button { showConsistencyInfo = true } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            Spacer()
            ConsistencyMeter(stdDev: stdDev)
                .frame(width: 110, height: 12)
        }
    }
    
    private func statBlock(title: String, value: Double) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%.2f", value))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private func statBlockPercent(title: String, value: Double) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%.1f%%", value))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
            Text(title)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
    
    private func formStatBlock(_ name: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%.2f", value))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            Text(name)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
    
    private func formDeltaBlock(arrow: String, delta: Double) -> some View {
        VStack(spacing: 2) {
            Text("\(arrow) \(String(format: "%+.2f", delta))")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(formDeltaColor)
            Text("Delta")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
    
    private struct Pill: View {
        let text: String
        let bg: Color
        let stroke: Color
        var body: some View {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(bg))
                .overlay(Capsule().stroke(stroke.opacity(0.7), lineWidth: 1))
                .foregroundColor(.white)
        }
    }
    
    private struct EfficiencyBar: View {
        let ratio: Double
        let height: CGFloat
        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: height/2)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: height/2)
                        .fill(LinearGradient(colors: [.red, .orange, .yellow, .green],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, min(geo.size.width, geo.size.width * ratio)))
                        .animation(.easeInOut(duration: 0.5), value: ratio)
                }
            }
        }
    }
    
    private struct ConsistencyMeter: View {
        let stdDev: Double
        private var norm: Double { max(0, min(1, stdDev / 60.0)) }
        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [.green, .yellow, .orange, .red],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * norm)
                }
            }
            .clipShape(Capsule())
        }
    }
}

struct ConsistencyInfoSheet: View {
    let stdDev: Double
    let descriptor: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Consistency Score")
                .font(.title3.bold())
            Text("Your team's consistency is described as \(descriptor) with a standard deviation of \(String(format: "%.2f", stdDev)).")
                .font(.callout)
            Spacer()
        }
        .padding()
        .presentationBackground(.regularMaterial)
    }
}

// Helper struct as previously described:
struct StatGradeBreakdown {
    let grade: String
    let composite: Double
    let percentiles: [String: Double]
    let summary: String
}

// MARK: - EfficiencyInfoSheet

struct EfficiencyInfoSheet: View {
    let managementPercent: Double
    let pointsFor: Double
    let maxPointsFor: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Lineup Efficiency").font(.title3.bold())
            Text("Management % = Points For ÷ Max Possible Points. Shows how close you were to an ideal lineup. Higher is better.")
                .font(.callout)
            HStack {
                Text("PF: \(Int(pointsFor))")
                Text("Max: \(Int(maxPointsFor))")
                Text(String(format: "Mgmt: %.1f%%", managementPercent))
            }
            .font(.caption)
            Spacer()
        }
        .padding()
        .presentationBackground(.ultraThinMaterial)
    }
}

// MARK: - WeeklyPointsTrend

struct WeeklyPointsTrend: View {
    let points: [Double]
    var stroke: Color = .orange
    var accent: Color = .yellow
    @State private var tappedWeek: Int?
    
    var body: some View {
        if points.isEmpty {
            Text("No weekly data yet")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
                .frame(height: 60)
        } else {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let maxVal = max(points.max() ?? 1, 1)
                let minVal = min(points.min() ?? 0, 0)
                let span = max(maxVal - minVal, 1)
                let stepX = points.count > 1 ? w / CGFloat(points.count - 1) : 0
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: h - 1))
                        p.addLine(to: CGPoint(x: w, y: h - 1))
                    }.stroke(Color.white.opacity(0.15), lineWidth: 1)
                    
                    if points.count > 1 {
                        Path { path in
                            for (i, val) in points.enumerated() {
                                let x = CGFloat(i) * stepX
                                let y = h - (((val - minVal) / span) * h)
                                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                else { path.addLine(to: CGPoint(x: x, y: y)) }
                            }
                            path.addLine(to: CGPoint(x: w, y: h))
                            path.addLine(to: CGPoint(x: 0, y: h))
                            path.closeSubpath()
                        }
                        .fill(LinearGradient(colors: [accent.opacity(0.28), .clear],
                                             startPoint: .top, endPoint: .bottom))
                    }
                    
                    Path { path in
                        for (i, val) in points.enumerated() {
                            let x = CGFloat(i) * stepX
                            let y = h - (((val - minVal) / span) * h)
                            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(stroke, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    
                    ForEach(points.indices, id: \.self) { idx in
                        let val = points[idx]
                        let x = CGFloat(idx) * stepX
                        let y = h - (((val - minVal) / span) * h)
                        Circle()
                            .fill(stroke)
                            .frame(width: 6, height: 6)
                            .overlay(Circle().stroke(Color.black, lineWidth: 1))
                            .position(x: x, y: y)
                            .contentShape(Rectangle().inset(by: -10))
                            .onTapGesture { tappedWeek = idx }
                    }
                    
                    if let t = tappedWeek, t < points.count {
                        let val = points[t]
                        let x = CGFloat(t) * stepX
                        let y = h - (((val - minVal) / span) * h)
                        Tooltip(text: "W\(t+1): \(String(format: "%.1f", val))")
                            .position(x: min(max(60, x), w - 60),
                                      y: max(24, y - 30))
                            .transition(.opacity.combined(with: .scale))
                    }
                    
                    ForEach(points.indices, id: \.self) { idx in
                        let x = CGFloat(idx) * stepX
                        Path { p in
                            p.move(to: CGPoint(x: x, y: h))
                            p.addLine(to: CGPoint(x: x, y: h - 4))
                        }
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: tappedWeek)
            }
            .frame(height: 120)
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(accent.opacity(0.4), lineWidth: 1)
            )
        }
    }
    
    private struct Tooltip: View {
        let text: String
        var body: some View {
            Text(text)
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.8)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.25), lineWidth: 1))
                .foregroundColor(.white)
        }
    }
}
