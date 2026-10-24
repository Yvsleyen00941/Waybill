import SwiftUI

/// "While you were away": what the depot did while the app was closed.
struct AwayReportCard: View {
    let report: GameModel.AwayReport
    var regionName = "Riverside"
    var unit = "pallets"
    let onCollect: () -> Void
    @State private var appeared = false
    @State private var counted = 0.0

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.18 : 0)
                .ignoresSafeArea()
                .onTapGesture { onCollect() }
            VStack(spacing: 16) {
                WaybillTile(size: 52)
                VStack(spacing: 4) {
                    Text("While you were away")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.UI.ink)
                    Text(Format.duration(report.seconds) + " at " + regionName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.UI.secondary)
                }
                if report.earned > 0 {
                    Text("+" + Format.money(counted))
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.UI.positive)
                        .contentTransition(.numericText(value: counted))
                    Text("\(Format.short(report.delivered)) \(unit) delivered" + (report.contractsDone > 0 ? " · \(report.contractsDone) contract\(report.contractsDone == 1 ? "" : "s") done" : ""))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.UI.secondary)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "truck.box.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Palette.UI.warning)
                        Text(report.hadDispatcher ? "The dock was quiet." : "Your trucks waited at the dock.")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.UI.ink)
                        if !report.hadDispatcher {
                            Text("Hire a Dispatcher to keep earning while you're away.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Palette.UI.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                Button(action: onCollect) {
                    Text(report.earned > 0 ? "Collect" : "Back to work")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0x7276F2), Color(hex: 0x4347CF)], startPoint: .top, endPoint: .bottom)))
                }
                .buttonStyle(PressableStyle(scale: 0.95))
            }
            .padding(26)
            .frame(width: 360)
            .glassEffect(.regular, in: .rect(cornerRadius: 30))
            .scaleEffect(appeared ? 1 : 0.88)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.55, bounce: 0.3)) { appeared = true }
            withAnimation(.easeOut(duration: 1.2).delay(0.3)) { counted = report.earned }
        }
    }
}
