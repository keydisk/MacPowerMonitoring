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

    public init(
        title: String,
        icon: String = "📈",
        points: [ChartPoint],
        lineColor: Color,
        fillColorStart: Color,
        fillColorEnd: Color,
        unit: String,
        defaultMinY: Double = 0.0,
        defaultMaxY: Double = 40.0
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
    }

    private var latestText: String {
        if let last = points.last {
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
                }

                Spacer()

                Text(latestText)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(lineColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
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
            .frame(height: 280)
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
        let padLeft: CGFloat = 45.0
        let padRight: CGFloat = 20.0
        let padTop: CGFloat = 25.0
        let padBottom: CGFloat = 30.0

        let chartW = size.width - padLeft - padRight
        let chartH = size.height - padTop - padBottom

        guard chartW > 0, chartH > 0 else { return }

        // 1. Auto Scale 계산
        var minV = defaultMinY
        var maxV = defaultMaxY

        if !points.isEmpty {
            let vals = points.map(\.value)
            let dataMin = vals.min() ?? defaultMinY
            let dataMax = vals.max() ?? defaultMaxY
            minV = floor(min(minV, dataMin * 0.95))
            maxV = ceil(max(maxV, dataMax * 1.15))
        }

        let vRange = max(maxV - minV, 0.001)

        // 2. Grid Lines & Left Y-Axis Labels (4 Steps)
        let gridSteps = 4
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
            if yVal < 10.0 {
                labelStr = String(format: "%.1f%@", yVal, unit)
            } else {
                labelStr = String(format: "%.0f%@", yVal, unit)
            }
            let labelText = Text(labelStr)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(labelColor)

            context.draw(labelText, at: CGPoint(x: padLeft - 8, y: yPos), anchor: .trailing)
        }

        // 3. 데이터가 없는 경우 대기 텍스트
        if points.isEmpty {
            let waitingText = Text("데이터 수신 대기 중...")
                .font(.system(size: 12))
                .foregroundColor(labelColor)
            context.draw(waitingText, at: CGPoint(x: padLeft + chartW / 2.0, y: padTop + chartH / 2.0), anchor: .center)
            return
        }

        // 4. 좌표 계산 (X, Y)
        struct CanvasPoint {
            let x: CGFloat
            let y: CGFloat
            let timeStr: String
        }

        let n = points.count
        let xStep = n > 1 ? chartW / CGFloat(n - 1) : 0.0
        var pts: [CanvasPoint] = []

        for i in 0..<n {
            let x = padLeft + (n > 1 ? CGFloat(i) * xStep : chartW / 2.0)
            let yRatio = CGFloat((points[i].value - minV) / vRange)
            let y = padTop + chartH - (yRatio * chartH)
            pts.append(CanvasPoint(x: x, y: y, timeStr: points[i].timeStr))
        }

        // 5. Fill Gradient Under Bezier Curve
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

        // 6. Smooth Bezier Stroke Line
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

        // 7. Glowing Head Dot (최신 데이터 포인트)
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

        // 8. Time Ticks at Bottom (시작 시간 & 종료 시간)
        if pts.count >= 2 {
            if !pts[0].timeStr.isEmpty {
                let startText = Text(pts[0].timeStr)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(labelColor)
                context.draw(startText, at: CGPoint(x: pts[0].x, y: padTop + chartH + 16), anchor: .center)
            }

            if !lastPt.timeStr.isEmpty {
                let endText = Text(lastPt.timeStr)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(labelColor)
                context.draw(endText, at: CGPoint(x: lastPt.x, y: padTop + chartH + 16), anchor: .center)
            }
        }
    }
}
