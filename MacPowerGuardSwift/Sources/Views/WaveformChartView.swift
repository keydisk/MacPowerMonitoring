import SwiftUI

// ==============================================================================
// SwiftUI Canvas 기반 실시간 파형 차트
// ==============================================================================
public struct WaveformChartView: View {
    let title: LocalizedStringKey
    let points: [ChartPoint]
    let lineColor: Color
    let unit: String
    let defaultMinY: Double
    let defaultMaxY: Double
    let thresholdValue: Double?
    let timeSpanText: String?
    let suppliedPowerW: Double?

    public init(
        title: LocalizedStringKey,
        points: [ChartPoint],
        lineColor: Color,
        unit: String,
        defaultMinY: Double = 0.0,
        defaultMaxY: Double = 40.0,
        thresholdValue: Double? = nil,
        timeSpanText: String? = nil,
        suppliedPowerW: Double? = nil
    ) {
        self.title = title
        self.points = points
        self.lineColor = lineColor
        self.unit = unit
        self.defaultMinY = defaultMinY
        self.defaultMaxY = defaultMaxY
        self.thresholdValue = thresholdValue
        self.timeSpanText = timeSpanText
        self.suppliedPowerW = suppliedPowerW
    }

    // 전압은 0V(비정상 유입)를 제외, 전력은 0W 이상 모두 유효
    private var validValues: [Double] {
        points.map(\.value).filter { unit == "V" ? $0 > 0.0 : $0 >= 0.0 }
    }

    private func format(_ v: Double?) -> String {
        guard let v else { return "-- \(unit)" }
        return String(format: unit == "V" ? "%.2f %@" : "%.1f %@", v, unit)
    }

    public var body: some View {
        let values = validValues

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                if let timeSpanText {
                    Text(timeSpanText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(format(points.last?.value))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(lineColor)
            }

            HStack(spacing: 14) {
                if unit == "W" {
                    stat("공급 전력", format(suppliedPowerW))
                }
                stat("최저", format(values.min()))
                stat("평균", format(values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)))
                stat("최고", format(values.max()))
            }
            .font(.caption)

            Canvas { context, size in
                drawChart(context: context, size: size)
            }
            .frame(height: 260)
        }
        .panel()
    }

    private func stat(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }

    private func drawChart(context: GraphicsContext, size: CGSize) {
        let padLeft: CGFloat = 48.0
        let padRight: CGFloat = 20.0
        let padTop: CGFloat = 25.0
        let padBottom: CGFloat = 32.0

        let chartW = size.width - padLeft - padRight
        let chartH = size.height - padTop - padBottom

        guard chartW > 0, chartH > 0 else { return }

        // 1. 양수 유효 데이터 포인트만 분리 (비정상 0V 유입에 의한 하단 늘어짐 방지)
        let validPoints = points.filter { $0.value > 0.0 }

        // 2. Auto Scale 계산 (전압 vs 전력 특성에 맞춘 스케일링)
        var minV = defaultMinY
        var maxV = defaultMaxY

        if !validPoints.isEmpty {
            let vals = validPoints.map(\.value)
            let dataMin = vals.min() ?? defaultMinY
            let dataMax = vals.max() ?? defaultMaxY

            if unit == "V" {
                // 전압(V): 정격 전압(20V 등) 및 실측값 기반의 밀착 범위 유지 (하단 늘어짐 원천 차단)
                let targetNominal = thresholdValue ?? (dataMax >= 16.0 ? 20.0 : (dataMax >= 11.0 ? 12.0 : 5.0))
                if targetNominal >= 18.0 {
                    // 표준 20V USB-C 어댑터: 18.0V ~ 21.0V (정격 20V가 67% 높이에 위치)
                    minV = min(18.0, floor(dataMin - 0.5))
                    maxV = max(21.0, ceil(dataMax + 0.5))
                } else if targetNominal >= 11.0 {
                    // 12V / 15V 배터리/충전기
                    minV = min(floor(targetNominal - 2.0), floor(dataMin - 0.5))
                    maxV = max(ceil(targetNominal + 2.0), ceil(dataMax + 0.5))
                } else {
                    minV = min(defaultMinY, floor(dataMin * 0.95))
                    maxV = max(defaultMaxY, ceil(dataMax * 1.1))
                }
            } else {
                // 전력 (W): 0W 기준점 자연스러운 스케일링
                minV = 0.0
                maxV = ceil(max(defaultMaxY, dataMax * 1.15))
            }
        }

        let vRange = max(maxV - minV, 0.001)

        // 3. Grid Lines & Left Y-Axis Labels (단계 계산)
        let gridSteps = (unit == "V" && vRange <= 4.0) ? Int(vRange) : 4
        let labelColor = Color.secondary

        for i in 0...gridSteps {
            let ratio = CGFloat(i) / CGFloat(gridSteps)
            let yVal = minV + (vRange * Double(i) / Double(gridSteps))
            let yPos = padTop + chartH - (chartH * ratio)

            // Horizontal Grid Line
            var gridLine = Path()
            gridLine.move(to: CGPoint(x: padLeft, y: yPos))
            gridLine.addLine(to: CGPoint(x: size.width - padRight, y: yPos))
            context.stroke(gridLine, with: .color(Color.primary.opacity(0.08)), lineWidth: 1.0)

            // Y-Axis Text Label
            let labelStr: String
            if vRange <= 4.0 && yVal.truncatingRemainder(dividingBy: 1.0) == 0.0 {
                labelStr = String(format: "%.0f%@", yVal, unit)
            } else if vRange <= 10.0 {
                labelStr = String(format: "%.1f%@", yVal, unit)
            } else {
                labelStr = String(format: "%.0f%@", yVal, unit)
            }
            let labelText = Text(labelStr)
                .font(.caption2.monospacedDigit())
                .foregroundColor(labelColor)

            context.draw(labelText, at: CGPoint(x: padLeft - 8, y: yPos), anchor: .trailing)
        }

        // 4. Threshold Line (기존 웹 버전과 동일한 정격 한계 점선)
        if let tv = thresholdValue, tv >= minV && tv <= maxV {
            let tRatio = CGFloat((tv - minV) / vRange)
            let threshY = padTop + chartH - (tRatio * chartH)

            var threshLine = Path()
            threshLine.move(to: CGPoint(x: padLeft, y: threshY))
            threshLine.addLine(to: CGPoint(x: size.width - padRight, y: threshY))
            context.stroke(
                threshLine,
                with: .color(Color.red.opacity(0.6)),
                style: StrokeStyle(lineWidth: 1.5, dash: [5, 5])
            )

            let threshLabel = Text("정격 한계 (\(Int(tv))\(unit))")
                .font(.caption2.weight(.semibold))
                .foregroundColor(Color.red)
            context.draw(threshLabel, at: CGPoint(x: padLeft + 6, y: threshY - 8), anchor: .leading)
        }

        // 5. 데이터가 없는 경우 대기 텍스트
        if validPoints.isEmpty {
            let waitingText = Text("데이터 수신 대기 중...")
                .font(.callout)
                .foregroundColor(labelColor)
            context.draw(waitingText, at: CGPoint(x: padLeft + chartW / 2.0, y: padTop + chartH / 2.0), anchor: .center)
            return
        }

        // 6. 좌표 계산 (X, Y)
        struct CanvasPoint {
            let x: CGFloat
            let y: CGFloat
            let time: Date
            let timeStr: String
        }

        let n = validPoints.count
        let xStep = n > 1 ? chartW / CGFloat(n - 1) : 0.0
        var pts: [CanvasPoint] = []

        for i in 0..<n {
            let x = padLeft + (n > 1 ? CGFloat(i) * xStep : chartW / 2.0)
            let clampedVal = max(minV, min(maxV, validPoints[i].value))
            let yRatio = CGFloat((clampedVal - minV) / vRange)
            let y = padTop + chartH - (yRatio * chartH)
            pts.append(CanvasPoint(x: x, y: y, time: validPoints[i].time, timeStr: validPoints[i].timeStr))
        }

        // 7. Fill Gradient Under Bezier Curve
        var fillPath = Path()
        fillPath.move(to: CGPoint(x: pts[0].x, y: padTop + chartH))
        fillPath.addLine(to: CGPoint(x: pts[0].x, y: pts[0].y))

        for i in 1..<pts.count {
            let prev = pts[i - 1]
            let curr = pts[i]
            let midX = (prev.x + curr.x) / 2.0
            fillPath.addCurve(
                to: CGPoint(x: curr.x, y: curr.y),
                control1: CGPoint(x: midX, y: prev.y),
                control2: CGPoint(x: midX, y: curr.y)
            )
        }

        fillPath.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: padTop + chartH))
        fillPath.closeSubpath()

        let gradient = Gradient(colors: [lineColor.opacity(0.18), lineColor.opacity(0.0)])
        context.fill(
            fillPath,
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: 0, y: padTop),
                endPoint: CGPoint(x: 0, y: padTop + chartH)
            )
        )

        // 8. Smooth Bezier Stroke Line
        var linePath = Path()
        linePath.move(to: CGPoint(x: pts[0].x, y: pts[0].y))

        for i in 1..<pts.count {
            let prev = pts[i - 1]
            let curr = pts[i]
            let midX = (prev.x + curr.x) / 2.0
            linePath.addCurve(
                to: CGPoint(x: curr.x, y: curr.y),
                control1: CGPoint(x: midX, y: prev.y),
                control2: CGPoint(x: midX, y: curr.y)
            )
        }

        context.stroke(
            linePath,
            with: .color(lineColor),
            style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round)
        )

        // 9. 최신 데이터 포인트
        let lastPt = pts[pts.count - 1]
        context.fill(
            Path(ellipseIn: CGRect(x: lastPt.x - 3.5, y: lastPt.y - 3.5, width: 7, height: 7)),
            with: .color(lineColor)
        )

        // 10. Time Ticks at Bottom (좌우 정렬로 Y축 단위 라벨과의 겹침 방지)
        if pts.count >= 2 {
            let spanSec = abs(lastPt.time.timeIntervalSince(pts[0].time))
            let timeFmt = DateFormatter()
            if spanSec >= 86400 {
                timeFmt.dateFormat = "MM/dd HH:mm"
            } else {
                timeFmt.dateFormat = "HH:mm:ss"
            }

            let startStr = timeFmt.string(from: pts[0].time)
            let startText = Text(startStr)
                .font(.caption2.monospacedDigit())
                .foregroundColor(labelColor)
            context.draw(startText, at: CGPoint(x: padLeft, y: padTop + chartH + 18), anchor: .leading)

            // 중간 기준 시간
            if pts.count >= 6 {
                let midIdx = pts.count / 2
                let midPt = pts[midIdx]
                let midStr = timeFmt.string(from: midPt.time)
                let midText = Text(midStr)
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(labelColor.opacity(0.8))
                context.draw(midText, at: CGPoint(x: padLeft + chartW / 2.0, y: padTop + chartH + 18), anchor: .center)
            }

            let endStr = timeFmt.string(from: lastPt.time)
            let endText = Text(endStr)
                .font(.caption2.monospacedDigit())
                .foregroundColor(labelColor)
            context.draw(endText, at: CGPoint(x: size.width - padRight, y: padTop + chartH + 18), anchor: .trailing)
        }
    }
}
