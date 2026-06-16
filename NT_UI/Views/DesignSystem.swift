import SwiftUI

enum ParchmentPalette {
    static let ink = Color(red: 0.18, green: 0.12, blue: 0.08)
    static let paper = Color(red: 0.97, green: 0.94, blue: 0.84)
    static let paperDeep = Color(red: 0.91, green: 0.85, blue: 0.72)
}

struct AppleGlassBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.015, green: 0.027, blue: 0.060),
                    Color(red: 0.010, green: 0.020, blue: 0.038),
                    Color(red: 0.016, green: 0.012, blue: 0.050)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    .cyan.opacity(0.38),
                    .blue.opacity(0.12),
                    .clear,
                    .purple.opacity(0.35)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blur(radius: 56)

            AngularGradient(
                colors: [
                    .teal.opacity(0.28),
                    .clear,
                    .indigo.opacity(0.28),
                    .purple.opacity(0.26),
                    .teal.opacity(0.18)
                ],
                center: .center
            )
            .opacity(0.55)
            .blur(radius: 82)
        }
    }
}

struct GlassIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 27, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: 62, height: 62)
            .parchmentGlass(cornerRadius: 18, tint: tint.opacity(0.16), interactive: false)
    }
}

struct GlassCard<Content: View>: View {
    let tint: Color
    let content: Content

    init(tint: Color = .white.opacity(0.05), @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .parchmentGlass(cornerRadius: 26, tint: tint, interactive: false)
    }
}

struct ScreenTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .accessibilityIdentifier("screen.\(title)")
            Text(subtitle)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
        }
    }
}

struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 21, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.cyan)
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text(message)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding()
        .parchmentGlass(cornerRadius: 26, tint: .white.opacity(0.04), interactive: false)
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .parchmentGlass(cornerRadius: 15, tint: color.opacity(0.12), interactive: false)
    }
}

struct ParchmentCanvasSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                LinearGradient(
                    colors: [ParchmentPalette.paper, ParchmentPalette.paperDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.25), radius: 20, y: 12)
    }
}

struct TaskTemplateOverlay: View {
    let task: ResearchTaskDefinition

    var body: some View {
        Canvas { context, size in
            switch task.template {
            case .spiral, .wave, .circle:
                let points = TaskCatalog.referencePoints(for: task.kind, in: size)
                stroke(points: points, context: &context)

            case .holdTarget:
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                context.stroke(
                    Path(ellipseIn: CGRect(x: center.x - 22, y: center.y - 22, width: 44, height: 44)),
                    with: .color(.gray.opacity(0.75)),
                    lineWidth: 4
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)),
                    with: .color(ParchmentPalette.ink)
                )

            case .sentence:
                let text = Text("Today is a sunny day.")
                    .font(.system(size: 30, weight: .semibold, design: .serif))
                    .foregroundStyle(ParchmentPalette.ink)
                context.draw(text, at: CGPoint(x: size.width / 2, y: 42))
                for index in 0..<3 {
                    let y = 120 + CGFloat(index) * 84
                    var path = Path()
                    path.move(to: CGPoint(x: size.width * 0.08, y: y))
                    path.addLine(to: CGPoint(x: size.width * 0.92, y: y))
                    context.stroke(path, with: .color(.brown.opacity(0.24)), lineWidth: 1)
                }

            case .clockReference:
                let dividerX = size.width / 2
                var divider = Path()
                divider.move(to: CGPoint(x: dividerX, y: size.height * 0.08))
                divider.addLine(to: CGPoint(x: dividerX, y: size.height * 0.92))
                context.stroke(divider, with: .color(.brown.opacity(0.20)), lineWidth: 2)
                stroke(
                    points: TaskCatalog.referencePoints(for: .clockCopy, in: size),
                    context: &context
                )
                context.draw(
                    Text("参考").font(.headline).foregroundStyle(ParchmentPalette.ink.opacity(0.72)),
                    at: CGPoint(x: size.width * 0.25, y: 28)
                )
                context.draw(
                    Text("请在此复制").font(.headline).foregroundStyle(ParchmentPalette.ink.opacity(0.72)),
                    at: CGPoint(x: size.width * 0.75, y: 28)
                )

            case .none:
                break
            }
        }
        .allowsHitTesting(false)
    }

    private func stroke(points: [CGPoint], context: inout GraphicsContext) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        context.stroke(
            path,
            with: .color(.gray.opacity(0.42)),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        )
    }
}

extension View {
    @ViewBuilder
    func parchmentGlass(cornerRadius: CGFloat, tint: Color?, interactive: Bool) -> some View {
        if let tint {
            glassEffect(.regular.tint(tint).interactive(interactive), in: .rect(cornerRadius: cornerRadius))
        } else {
            glassEffect(.regular.interactive(interactive), in: .rect(cornerRadius: cornerRadius))
        }
    }

    func appScreenPadding() -> some View {
        padding(.horizontal, 38).padding(.vertical, 24)
    }
}
