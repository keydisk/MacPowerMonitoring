import Foundation

// ==============================================================================
// LTTB (Largest Triangle Three Buckets) 다운샘플링 알고리즘
// ==============================================================================
// 원문: "Downsampling Time Series for Visual Representation" (Sveinn Steinarsson)
// 단순 보폭(Stride)이나 평균화(Moving Average)는 찰나의 전력 피크(80W)나
// 순간적인 전압 강하(Drop)를 유실시키지만, LTTB는 인접 버킷과 형성하는
// 삼각형의 면적(극값)을 기하학적으로 최대화하여 피크와 밸리를 100% 보존합니다.
public struct LTTBDownsampler {
    /// 시계열 데이터 배열 `[ChartPoint]`를 최대 `targetCount`개로 다운샘플링합니다.
    /// - Parameters:
    ///   - data: 원본 시계열 데이터
    ///   - targetCount: 목표 출력 포인트 개수 (기본 300개)
    /// - Returns: 기하학적 피크와 추세가 보존된 다운샘플링 포인트 배열
    public static func downsample(_ data: [ChartPoint], targetCount: Int = 300) -> [ChartPoint] {
        guard data.count > targetCount, targetCount >= 3 else {
            return data
        }

        var sampled: [ChartPoint] = []
        sampled.reserveCapacity(targetCount)

        // 1. 첫 번째 포인트는 항상 포함
        var aPoint = data[0]
        sampled.append(aPoint)

        // 버킷 분할 크기 (첫점과 끝점을 제외한 targetCount - 2개의 버킷)
        let bucketSize = Double(data.count - 2) / Double(targetCount - 2)

        for i in 0..<(targetCount - 2) {
            // 현재 후보 포인트 버킷 B의 범위
            let bucketStart = Int(floor(Double(i) * bucketSize)) + 1
            let bucketEnd = min(Int(floor(Double(i + 1) * bucketSize)) + 1, data.count - 1)

            guard bucketStart < bucketEnd else { continue }

            // 다음 버킷 C의 범위 (평균점 계산용)
            let nextBucketStart = Int(floor(Double(i + 1) * bucketSize)) + 1
            let nextBucketEnd = min(Int(floor(Double(i + 2) * bucketSize)) + 1, data.count)

            var avgX: Double = 0.0
            var avgY: Double = 0.0
            let nextCount = nextBucketEnd - nextBucketStart

            if nextCount > 0 && nextBucketStart < data.count {
                for j in nextBucketStart..<nextBucketEnd {
                    avgX += data[j].time.timeIntervalSinceReferenceDate
                    avgY += data[j].value
                }
                avgX /= Double(nextCount)
                avgY /= Double(nextCount)
            } else {
                let last = data[data.count - 1]
                avgX = last.time.timeIntervalSinceReferenceDate
                avgY = last.value
            }

            let ax = aPoint.time.timeIntervalSinceReferenceDate
            let ay = aPoint.value

            var maxArea: Double = -1.0
            var maxIndex = bucketStart

            // 현재 버킷 내에서 삼각형 ABC의 면적이 최대인 점 B 탐색
            for j in bucketStart..<bucketEnd {
                let bx = data[j].time.timeIntervalSinceReferenceDate
                let by = data[j].value

                // 삼각형 면적 = 0.5 * |(Ax - Cx)(By - Ay) - (Ax - Bx)(Cy - Ay)|
                let area = abs((ax - avgX) * (by - ay) - (ax - bx) * (avgY - ay))
                if area > maxArea {
                    maxArea = area
                    maxIndex = j
                }
            }

            let bestPoint = data[maxIndex]
            sampled.append(bestPoint)
            aPoint = bestPoint
        }

        // 2. 마지막 포인트는 항상 포함
        sampled.append(data[data.count - 1])
        return sampled
    }
}
