import SwiftUI

struct PowerVoltageChartView: View {
    let power: [ChartPoint]
    let voltage: [ChartPoint]
    let suppliedPower: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Power & Voltage", tableName: "Metrics").font(.headline)
            HStack(spacing: 16) {
                Text("Power", tableName: "Metrics").foregroundStyle(.blue)
                Label(power.last.map { String(format: "%.1f W", $0.value) } ?? "-- W", systemImage: "waveform.path")
                    .foregroundStyle(.blue)
                Text("Voltage", tableName: "Metrics").foregroundStyle(.green)
                Label(voltage.last.map { String(format: "%.2f V", $0.value) } ?? "-- V", systemImage: "line.diagonal")
                    .foregroundStyle(.green)
                Spacer()
                Text("공급 전력").foregroundStyle(.secondary)
                Text(suppliedPower.map { String(format: "%.1f W", $0) } ?? "-- W")
            }.font(.caption).monospacedDigit()
            Canvas { context, size in draw(context, size) }.frame(height: 170)
                .accessibilityLabel(Text("Power & Voltage", tableName: "Metrics"))
                .accessibilityValue("\(power.last.map { String($0.value) } ?? "--") W, \(voltage.last.map { String($0.value) } ?? "--") V")
        }.panel()
    }

    private func draw(_ context: GraphicsContext, _ size: CGSize) {
        let p = power.filter { $0.value.isFinite && $0.value >= 0 }
        let v = voltage.filter { $0.value.isFinite && $0.value > 0 }
        let all = p + v
        let start = all.map(\.time).min() ?? Date()
        let end = all.map(\.time).max() ?? start
        let span = end.timeIntervalSince(start)
        let rect = CGRect(x: 44, y: 16, width: max(1, size.width - 92), height: size.height - 44)
        let powerMax = max(35, ceil((p.map(\.value).max() ?? 0) * 1.15))
        let voltageMin = floor((v.map(\.value).min() ?? 18) - 1)
        let voltageMax = max(voltageMin + 2, ceil((v.map(\.value).max() ?? 20) + 1))
        for i in 0...4 {
            let ratio = Double(i) / 4
            let y = rect.maxY - ratio * rect.height
            var grid = Path()
            grid.move(to: CGPoint(x: rect.minX, y: y))
            grid.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.stroke(grid, with: .color(.primary.opacity(0.08)), lineWidth: 1)
            context.draw(Text(String(format: "%.0fW", ratio * powerMax)).font(.caption2).foregroundColor(.blue), at: CGPoint(x: rect.minX - 6, y: y), anchor: .trailing)
            context.draw(Text(String(format: "%.1fV", voltageMin + ratio * (voltageMax - voltageMin))).font(.caption2).foregroundColor(.green), at: CGPoint(x: rect.maxX + 6, y: y), anchor: .leading)
        }
        for (points, minimum, maximum, color, dashed) in [(p, 0.0, powerMax, Color.blue, false), (v, voltageMin, voltageMax, Color.green, true)] {
            let positions = points.map { point in
                CGPoint(x: rect.minX + (span > 0 ? point.time.timeIntervalSince(start) / span : 0.5) * rect.width,
                        y: rect.maxY - (point.value - minimum) / (maximum - minimum) * rect.height)
            }
            context.stroke(SmoothChartPath.make(positions), with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: dashed ? [5, 3] : []))
            if let last = positions.last {
                context.fill(Path(ellipseIn: CGRect(x: last.x - 2.5, y: last.y - 2.5, width: 5, height: 5)), with: .color(color))
            }
        }
        if all.isEmpty {
            context.draw(Text("데이터 수신 대기 중...").font(.caption).foregroundColor(.secondary), at: CGPoint(x: rect.midX, y: rect.midY))
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = span >= 86400 ? "MM/dd HH:mm" : "HH:mm:ss"
            context.draw(Text(formatter.string(from: start)).font(.caption2).foregroundColor(.secondary), at: CGPoint(x: rect.minX, y: rect.maxY + 18), anchor: .leading)
            context.draw(Text(formatter.string(from: end)).font(.caption2).foregroundColor(.secondary), at: CGPoint(x: rect.maxX, y: rect.maxY + 18), anchor: .trailing)
        }
    }
}
