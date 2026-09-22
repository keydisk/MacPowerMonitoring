import SwiftUI

// ==============================================================================
// 순수 SwiftUI Canvas 기반 고성능 실시간 차트 (기존 웹 CyberCanvasChart 와 100% 동일)
// ==============================================================================
public struct WaveformChartView: View {
    let title: String
    let icon: String
    let points: [ChartPoint]
    let lineColor: Color
    let fillColorStart: Color
    let fillColorEnd: Color
    let unit: String
    let defaultMinY: Double
    let defaultMaxY: Double
    let thresholdValue: Double?
    let canvasHeight: CGFloat
    let timeSpanText: String?

    public init(
        title: String,
        icon: String = "📈",
        points: [ChartPoint],
        lineColor: Color,
        fillColorStart: Color,
        fillColorEnd: Color,
        unit: String,
        defaultMinY: Double = 0.0,
        defaultMaxY: Double = 40.0,
        thresholdValue: Double? = nil,
        canvasHeight: CGFloat = 280,
        timeSpanText: String? = "최근 10분"
    ) {
        self.title = title
        self.icon = icon
        self.points = points
        self.lineColor = lineColor
        self.fillColorStart = fillColorStart
        self.fillColorEnd = fillColorEnd
        self.unit = unit
        self.defaultMinY = defaultMinY
        self.defaultMaxY = defaultMaxY
        self.thresholdValue = thresholdValue
        self.canvasHeight = canvasHeight
        self.timeSpanText = timeSpanText
    }

    private var validPoints: [ChartPoint] {
        points.filter { $0.value > 0.0 }
    }

    private var minPoint: ChartPoint? {
        validPoints.min(by: { $0.value < $1.value })
    }

    private var maxPoint: ChartPoint? {
        validPoints.max(by: { $0.value < $1.value })
    }

    private var minText: String {
        if let min = minPoint {
            return String(format: "%.1f %@", min.value, unit)
        }
        return "-- \(unit)"
    }

    private var maxText: String {
        if let max = maxPoint {
            return String(format: "%.1f %@", max.value, unit)
        }
        return "-- \(unit)"
    }

    private var latestText: String {
        if let last = points.last, last.value > 0 {
            return String(format: "%.1f %@", last.value, unit)
        }
        return "-- \(unit)"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 1. Chart Header
            HStack {
                HStack(spacing: 8) {
                    Text(icon)
                        .font(.system(size: 16))
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)

                    if let timeSpan = timeSpanText {
                        Text(timeSpan)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color(white: 0.6))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                // 최저값, 최고값, 현재값 뱃지 그룹
                HStack(spacing: 8) {
                    // 최저값 (Min)
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color(red: 0.22, green: 0.85, blue: 0.95))
                        Text("최저")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(Color(white: 0.55))
                        Text(minText)
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.22, green: 0.85, blue: 0.95))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )

                    // 최고값 (Max)
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color(red: 0.96, green: 0.62, blue: 0.04))
                        Text("최고")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(Color(white: 0.55))
                        Text(maxText)
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.96, green: 0.62, blue: 0.04))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )

                    // 현재값 (Current)
                    HStack(spacing: 4) {
                        Text("현재")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(Color(white: 0.55))
                        Text(latestText)
                            .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                            .foregroundColor(lineColor)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(lineColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(lineColor.opacity(0.35), lineWidth: 1)
                    )
                }
            }

            // 2. Canvas Wrapper (HTML5 Canvas 2D 1:1 완벽 이식)
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.04), lineWidth: 1)
                    )

                Canvas { context, size in
                    drawChart(context: context, size: size)
                }
            }
            .frame(height: canvasHeight)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.85)) // #0f172a
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 4)
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
        let labelColor = Color(red: 0.39, green: 0.45, blue: 0.55) // #64748b

        for i in 0...gridSteps {
            let ratio = CGFloat(i) / CGFloat(gridSteps)
            let yVal = minV + (vRange * Double(i) / Double(gridSteps))
            let yPos = padTop + chartH - (chartH * ratio)

            // Horizontal Grid Line
            var gridLine = Path()
            gridLine.move(to: CGPoint(x: padLeft, y: yPos))
            gridLine.addLine(to: CGPoint(x: size.width - padRight, y: yPos))
            context.stroke(gridLine, with: .color(Color.white.opacity(0.06)), lineWidth: 1.0)

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
                .font(.system(size: 11, design: .monospaced))
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
                with: .color(Color(red: 0.94, green: 0.27, blue: 0.27).opacity(0.65)),
                style: StrokeStyle(lineWidth: 1.5, dash: [5, 5])
            )

            let threshLabel = Text("정격 한계 (\(Int(tv))\(unit))")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(red: 0.94, green: 0.27, blue: 0.27).opacity(0.85))
            context.draw(threshLabel, at: CGPoint(x: padLeft + 6, y: threshY - 8), anchor: .leading)
        }

        // 5. 데이터가 없는 경우 대기 텍스트
        if validPoints.isEmpty {
            let waitingText = Text("데이터 수신 대기 중...")
                .font(.system(size: 12))
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

        let gradient = Gradient(colors: [fillColorStart, fillColorEnd])
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
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        )

        // 8.5. 최고값(Max) 및 최저값(Min) 캔버스 마커 표시
        if validPoints.count >= 4,
           let maxIdx = validPoints.indices.max(by: { validPoints[$0].value < validPoints[$1].value }),
           let minIdx = validPoints.indices.min(by: { validPoints[$0].value < validPoints[$1].value }),
           maxIdx < pts.count, minIdx < pts.count {
            let maxVal = validPoints[maxIdx].value
            let minVal = validPoints[minIdx].value

            // 의미 있는 차이가 있을 때만 마커 표시
            if (maxVal - minVal) >= (unit == "V" ? 0.05 : 0.5) {
                let maxCanvasPt = pts[maxIdx]
                let minCanvasPt = pts[minIdx]

                // 최고값 (Max) 마커
                if maxIdx != pts.count - 1 {
                    context.stroke(
                        Path(ellipseIn: CGRect(x: maxCanvasPt.x - 5, y: maxCanvasPt.y - 5, width: 10, height: 10)),
                        with: .color(Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.8)),
                        lineWidth: 1.5
                    )
                    context.fill(
                        Path(ellipseIn: CGRect(x: maxCanvasPt.x - 3, y: maxCanvasPt.y - 3, width: 6, height: 6)),
                        with: .color(Color(red: 0.96, green: 0.62, blue: 0.04))
                    )
                    let maxLabel = Text(String(format: "▲ %.1f", maxVal))
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.96, green: 0.62, blue: 0.04))
                    let maxLabelY = max(padTop + 10, maxCanvasPt.y - 12)
                    context.draw(maxLabel, at: CGPoint(x: maxCanvasPt.x, y: maxLabelY), anchor: .bottom)
                }

                // 최저값 (Min) 마커
                if minIdx != pts.count - 1 {
                    context.stroke(
                        Path(ellipseIn: CGRect(x: minCanvasPt.x - 5, y: minCanvasPt.y - 5, width: 10, height: 10)),
                        with: .color(Color(red: 0.22, green: 0.85, blue: 0.95).opacity(0.8)),
                        lineWidth: 1.5
                    )
                    context.fill(
                        Path(ellipseIn: CGRect(x: minCanvasPt.x - 3, y: minCanvasPt.y - 3, width: 6, height: 6)),
                        with: .color(Color(red: 0.22, green: 0.85, blue: 0.95))
                    )
                    let minLabel = Text(String(format: "▼ %.1f", minVal))
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.22, green: 0.85, blue: 0.95))
                    let minLabelY = min(padTop + chartH - 4, minCanvasPt.y + 12)
                    context.draw(minLabel, at: CGPoint(x: minCanvasPt.x, y: minLabelY), anchor: .top)
                }
            }
        }

        // 9. Glowing Head Dot (최신 데이터 포인트)
        let lastPt = pts[pts.count - 1]
        // 외부 글로우
        context.fill(
            Path(ellipseIn: CGRect(x: lastPt.x - 10, y: lastPt.y - 10, width: 20, height: 20)),
            with: .color(lineColor.opacity(0.35))
        )
        // 내부 흰색 포인트 (원형 5.5px)
        context.fill(
            Path(ellipseIn: CGRect(x: lastPt.x - 5.5, y: lastPt.y - 5.5, width: 11, height: 11)),
            with: .color(.white)
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
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(labelColor)
            context.draw(startText, at: CGPoint(x: padLeft, y: padTop + chartH + 18), anchor: .leading)

            // 중간 기준 시간
            if pts.count >= 6 {
                let midIdx = pts.count / 2
                let midPt = pts[midIdx]
                let midStr = timeFmt.string(from: midPt.time)
                let midText = Text(midStr)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(labelColor.opacity(0.8))
                context.draw(midText, at: CGPoint(x: padLeft + chartW / 2.0, y: padTop + chartH + 18), anchor: .center)
            }

            let endStr = timeFmt.string(from: lastPt.time)
            let endText = Text(endStr)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(labelColor)
            context.draw(endText, at: CGPoint(x: size.width - padRight, y: padTop + chartH + 18), anchor: .trailing)
        }
    }
}
