import SwiftUI

/// Research tab: one project at a time, real time, and every project visibly changes the depot.
struct ResearchView: View {
    let game: GameModel
    let world: WorldController

    var body: some View {
        if !game.researchUnlocked {
            LockedPanel(symbol: "flask.fill", title: "Research",
                        message: "Finish a contract or earn \(Format.money(15_000)) to unlock research. Every project changes how the depot looks.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let active = game.activeResearch, let project = ResearchProject.find(active.id) {
                        RunningCard(project: project, remaining: active.remaining)
                            .padding(.bottom, 4)
                            .transition(.scale(scale: 0.95).combined(with: .opacity))
                    }
                    SectionLabel(text: game.config.name, detail: "projects")
                    ForEach(ResearchProject.projects(for: game.region)) { project in
                        ResearchRow(game: game, world: world, project: project)
                    }
                }
                .animation(.spring(duration: 0.4, bounce: 0.2), value: game.activeResearch?.id)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 430)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct RunningCard: View {
    let project: ResearchProject
    let remaining: Double

    var body: some View {
        let progress = 1 - remaining / max(project.seconds, 1)
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color.black.opacity(0.07), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Palette.UI.brand, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: progress)
                Image(systemName: project.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.UI.brand)
                    .symbolEffect(.pulse)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Researching \(project.title)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.UI.ink)
                Text(project.effectLabel)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.UI.positive)
                Text("Ready in \(Format.duration(remaining))")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.UI.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.6)))
    }
}

private struct ResearchRow: View {
    let game: GameModel
    let world: WorldController
    let project: ResearchProject

    var body: some View {
        let done = game.research.contains(project.id)
        let running = game.activeResearch?.id == project.id
        let busy = game.activeResearch != nil
        let affordable = game.money >= project.cost
        HStack(spacing: 11) {
            Image(systemName: done ? "checkmark" : project.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(done ? .white : Palette.UI.brand)
                .frame(width: 36, height: 36)
                .background(done ? AnyShapeStyle(Palette.UI.positive.gradient) : AnyShapeStyle(Palette.UI.infoBG),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(project.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Palette.UI.ink)
                Text(project.effectLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(done ? Palette.UI.secondary : Palette.UI.positive)
                Text(project.detail)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Palette.UI.secondary.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 4)
            if done {
                Button {
                    world.show(research: project.id)
                } label: {
                    Label("Show", systemImage: "scope")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Palette.UI.brand)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Capsule().strokeBorder(Palette.UI.brand.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(PressableStyle(scale: 0.92))
            } else if running {
                Text("Running")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.UI.brand)
                    .frame(width: 86)
            } else {
                Button {
                    withAnimation(.spring(duration: 0.4, bounce: 0.25)) { game.startResearch(project) }
                } label: {
                    VStack(spacing: 1) {
                        Text(Format.duration(project.seconds))
                            .font(.system(size: 10.5, weight: .semibold))
                            .opacity(0.85)
                        Text(Format.money(project.cost))
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(affordable && !busy ? .white : Palette.UI.secondary)
                    .frame(width: 86, height: 42)
                    .background {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(affordable && !busy ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x6E72F0), Color(hex: 0x4B4FD8)], startPoint: .top, endPoint: .bottom))
                                                      : AnyShapeStyle(Color.black.opacity(0.06)))
                    }
                }
                .buttonStyle(PressableStyle(scale: 0.92))
                .disabled(!affordable || busy)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(running ? Palette.UI.infoBG.opacity(0.7) : Color.white.opacity(done ? 0.2 : 0.35)))
    }
}
