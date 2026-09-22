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
        if unit == "V" {
            // 전압의 경우 0V가 아닌 유효한 실측 전압 기준
            return points.filter { $0.value > 0.0 }
        } else {
            // 전력의 경우 0.0W 이상인 모든 유효 포인트 포함
            return points.filter { $0.value >= 0.0 }
        }
    }

    private var minValue: Double? {
        validPoints.map(\.value).min()
    }

    private var maxValue: Double? {
        validPoints.map(\.value).max()
    }

    private var avgValue: Double? {
        guard !validPoints.isEmpty else { return nil }
        let sum = validPoints.reduce(0.0) { $0 + $1.value }
        return sum / Double(validPoints.count)
    }

    private var currentValue: Double? {
        points.last?.value
    }

    private var minText: String {
        if let v = minValue {
            return unit == "V" ? String(format: "%.2f %@", v, unit) : String(format: "%.1f %@", v, unit)
        }
        return "-- \(unit)"
    }

    private var maxText: String {
        if let v = maxValue {
            return unit == "V" ? String(format: "%.2f %@", v, unit) : String(format: "%.1f %@", v, unit)
        }
        return "-- \(unit)"
    }

    private var avgText: String {
        if let v = avgValue {
            return unit == "V" ? String(format: "%.2f %@", v, unit) : String(format: "%.1f %@", v, unit)
        }
        return "-- \(unit)"
    }

    private var currentText: String {
        if let v = currentValue {
            return unit == "V" ? String(format: "%.2f %@", v, unit) : String(format: "%.1f %@", v, unit)
        }
        return "-- \(unit)"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. 헤더 첫 번째 줄: 제목, 아이콘, 시간 범위 뱃지 & 현재 실시간 값
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Text(icon)
                        .font(.system(size: 15))
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)

                    if let timeSpan = timeSpanText {
                        Text(timeSpan)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(white: 0.6))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                // 현재 실시간 수치 (우측 정렬)
                HStack(spacing: 6) {
                    Circle()
                        .fill(lineColor)
                        .frame(width: 7, height: 7)
                    Text("현재")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(Color(white: 0.6))
                    Text(currentText)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(lineColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(lineColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(lineColor.opacity(0.3), lineWidth: 1)
                )
            }

            // 2. 헤더 두 번째 줄: 최저 / 평균 / 최고 요약 통계 바
            HStack(spacing: 10) {
                // 최저값
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(Color(red: 0.22, green: 0.85, blue: 0.95))
                    Text("최저")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(white: 0.5))
                    Text(minText)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(red: 0.22, green: 0.85, blue: 0.95))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(Color.white.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )

                // 평균값
                HStack(spacing: 5) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(Color(white: 0.7))
                    Text("평균")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(white: 0.5))
                    Text(avgText)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(white: 0.9))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(Color.white.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )

                // 최고값
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(Color(red: 0.96, green: 0.62, blue: 0.04))
                    Text("최고")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(white: 0.5))
                    Text(maxText)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(red: 0.96, green: 0.62, blue: 0.04))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(Color.white.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )

                Spacer()
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
