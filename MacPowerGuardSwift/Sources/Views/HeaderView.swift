import SwiftUI

public struct HeaderView: View {
    @ObservedObject var service: TelemetryService

    public init(service: TelemetryService) {
        self.service = service
    }

    public var body: some View {
        HStack(spacing: 16) {
            // Brand Icon & Titles
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.02, green: 0.71, blue: 0.83).opacity(0.3),
                                    Color(red: 0.06, green: 0.73, blue: 0.51).opacity(0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(red: 0.02, green: 0.71, blue: 0.83).opacity(0.4), lineWidth: 1)
                        )
                        .shadow(color: Color(red: 0.02, green: 0.71, blue: 0.83).opacity(0.3), radius: 8)

                    Image(systemName: "bolt.fill")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, Color(red: 0.02, green: 0.71, blue: 0.83)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Mac Power Guard")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundColor(.white)
                    Text("실시간 전력 공급량 & 하드웨어 전원선 안전 진단 시스템 (Native SwiftUI)")
                        .font(.system(size: 11.5))
                        .foregroundColor(Color(white: 0.55))
                }
            }

            Spacer()

            // Header Actions
            HStack(spacing: 10) {
                // Live Pulse Badge
                HStack(spacing: 8) {
                    Circle()
                        .fill(service.isPaused ? Color.orange : Color(red: 0.06, green: 0.73, blue: 0.51))
                        .frame(width: 8, height: 8)
                        .shadow(color: service.isPaused ? Color.orange : Color(red: 0.06, green: 0.73, blue: 0.51), radius: 4)

                    Text(service.isPaused ? "일시정지됨" : "실시간 수신 (\(service.packetCount)회)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(service.isPaused ? Color.orange : Color(red: 0.06, green: 0.73, blue: 0.51))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    (service.isPaused ? Color.orange : Color(red: 0.06, green: 0.73, blue: 0.51)).opacity(0.12)
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke((service.isPaused ? Color.orange : Color(red: 0.06, green: 0.73, blue: 0.51)).opacity(0.3), lineWidth: 1)
                )

                // Sound Toggle Button
                Button(action: { service.toggleSound() }) {
                    HStack(spacing: 6) {
                        Image(systemName: service.soundEnabled ? "speaker.wave.2.fill" : "bell.fill")
                            .font(.system(size: 12))
                        Text(service.soundEnabled ? "경고음 켜짐" : "경고음 켜기")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(service.soundEnabled ? Color(red: 0.06, green: 0.73, blue: 0.51).opacity(0.18) : Color.white.opacity(0.06))
                    .foregroundColor(service.soundEnabled ? Color(red: 0.06, green: 0.73, blue: 0.51) : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(service.soundEnabled ? Color(red: 0.06, green: 0.73, blue: 0.51).opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // Pause Toggle Button
                Button(action: { service.togglePause() }) {
                    HStack(spacing: 6) {
                        Image(systemName: service.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 12))
                        Text(service.isPaused ? "모니터링 재개" : "일시정지")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.06))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
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
}
