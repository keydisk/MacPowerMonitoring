import SwiftUI

enum SmoothChartPath {
    // 단조 cubic Hermite: 연속된 기울기를 이어 주되 측정 구간의 최저/최고를 넘지 않는다.
    static func make(_ points: [CGPoint]) -> Path {
        guard let first = points.first else { return Path() }
        var path = Path()
        path.move(to: first)
        guard points.count > 1 else { return path }
        let slopes = zip(points, points.dropFirst()).map { a, b in
            (b.y - a.y) / max(b.x - a.x, .leastNonzeroMagnitude)
        }
        var tangents = [slopes[0]]
        for i in 1..<points.count - 1 {
            let left = slopes[i - 1], right = slopes[i]
            tangents.append(left * right > 0 ? 2 * left * right / (left + right) : 0)
        }
        tangents.append(slopes.last!)
        for i in 0..<points.count - 1 {
            let a = points[i], b = points[i + 1]
            let third = (b.x - a.x) / 3
            let lower = min(a.y, b.y), upper = max(a.y, b.y)
            path.addCurve(to: b,
                control1: CGPoint(x: a.x + third, y: min(upper, max(lower, a.y + tangents[i] * third))),
                control2: CGPoint(x: b.x - third, y: min(upper, max(lower, b.y - tangents[i + 1] * third))))
        }
        return path
    }
}
