import SwiftUI

/// Rush: everything runs twice as fast for 20 seconds, then a cooldown.
struct RushButton: View {
    let game: GameModel

    var body: some View {
        let active = game.rushActive
        let cooling = !active && game.rushCooldown > 0
        let progress: Double = active ? game.rushRemaining / Economy.rushDuration
            : cooling ? 1 - game.rushCooldown / Economy.rushCooldown : 1
        Button {
            withAnimation(.spring(duration: 0.4, bounce: 0.4)) { game.rush() }
        } label: {
            ZStack {
                Circle().fill(active ? AnyShapeStyle(Color(hex: 0xF2B33D).gradient) : AnyShapeStyle(Color.white.opacity(0.001)))
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(active ? Color.white : (cooling ? Palette.UI.secondary.opacity(0.5) : Color(hex: 0xF2B33D)),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(3)
                VStack(spacing: 0) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 17, weight: .bold))
                        .symbolEffect(.pulse, isActive: active)
                    Text(active ? "×2" : cooling ? Format.duration(game.rushCooldown) : "Rush")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(active ? .white : (cooling ? Palette.UI.secondary : Color(hex: 0xD9952B)))
            }
            .frame(width: 58, height: 58)
            .hudGlass(in: .circle)
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .disabled(active || cooling)
    }
}
