import CoreGraphics
import Foundation
import SwiftUI

nonisolated enum TaskInteractionKind: Equatable {
    case drawing
    case hold
    case tapping
}

nonisolated enum TaskTemplateKind: Equatable {
    case none
    case spiral
    case holdTarget
    case sentence
    case wave
    case circle
    case clockReference
}

nonisolated struct ResearchTaskDefinition: Identifiable {
    let kind: ResearchTaskKind
    let title: String
    let instruction: String
    let hand: TestHand
    let interaction: TaskInteractionKind
    let template: TaskTemplateKind
    let fixedDuration: TimeInterval?

    var id: ResearchTaskKind { kind }
}

nonisolated enum TaskCatalog {
    static let all: [ResearchTaskDefinition] = [
        .init(kind: .spiralStatic, title: "静态螺旋", instruction: "请沿灰色螺旋线缓慢描摹，尽量保持连续。", hand: .none, interaction: .drawing, template: .spiral, fixedDuration: nil),
        .init(kind: .spiralDynamic, title: "动态螺旋", instruction: "请从画布中心向外连续画一个螺旋。", hand: .none, interaction: .drawing, template: .none, fixedDuration: nil),
        .init(kind: .holdRight, title: "静止保持", instruction: "请使用右手，将笔尖放在中心圆点并尽量保持不动。", hand: .right, interaction: .hold, template: .holdTarget, fixedDuration: 10),
        .init(kind: .holdLeft, title: "静止保持", instruction: "请使用左手，将笔尖放在中心圆点并尽量保持不动。", hand: .left, interaction: .hold, template: .holdTarget, fixedDuration: 10),
        .init(kind: .tappingRight, title: "触屏敲击", instruction: "请使用右手的两根手指交替点击左右圆点。", hand: .right, interaction: .tapping, template: .none, fixedDuration: 20),
        .init(kind: .tappingLeft, title: "触屏敲击", instruction: "请使用左手的两根手指交替点击左右圆点。", hand: .left, interaction: .tapping, template: .none, fixedDuration: 20),
        .init(kind: .sentenceCopying, title: "短句抄写", instruction: "请抄写：Today is a sunny day.", hand: .none, interaction: .drawing, template: .sentence, fixedDuration: nil),
        .init(kind: .waveTracing, title: "波浪线描摹", instruction: "请沿灰色波浪线从左向右描摹。", hand: .none, interaction: .drawing, template: .wave, fixedDuration: nil),
        .init(kind: .circleTracing, title: "圆形描摹", instruction: "请沿灰色圆形描摹一圈。", hand: .none, interaction: .drawing, template: .circle, fixedDuration: nil),
        .init(kind: .clockCommand, title: "数字画钟（自由绘制）", instruction: "请画一个钟表，时间显示为 11 点 10 分。", hand: .none, interaction: .drawing, template: .none, fixedDuration: nil),
        .init(kind: .clockCopy, title: "数字画钟 · 模板复制", instruction: "请在右侧复制左侧钟表，时间为 11 点 10 分。", hand: .none, interaction: .drawing, template: .clockReference, fixedDuration: nil)
    ]

    static let legacy: [ResearchTaskDefinition] = [
        .init(kind: .spiralRight, title: "螺旋描摹", instruction: "请使用右手，沿灰色螺旋线缓慢描摹。", hand: .right, interaction: .drawing, template: .spiral, fixedDuration: nil),
        .init(kind: .spiralLeft, title: "螺旋描摹", instruction: "请使用左手，沿灰色螺旋线缓慢描摹。", hand: .left, interaction: .drawing, template: .spiral, fixedDuration: nil)
    ]

    static func tasks(
        for mode: TestMode,
        dominantHand: DominantHand = .unspecified
    ) -> [ResearchTaskDefinition] {
        switch mode {
        case .quick:
            let hand = singleHand(for: dominantHand)
            let holdKind: ResearchTaskKind = hand == .left ? .holdLeft : .holdRight
            let tappingKind: ResearchTaskKind = hand == .left ? .tappingLeft : .tappingRight
            return [
                .spiralDynamic,
                holdKind,
                tappingKind,
                .waveTracing,
                .circleTracing,
                .clockCommand
            ].map(definition(for:))
        case .full:
            return all
        }
    }

    /// 快速模式只采集一只手；双手或未填写时使用右手，保证任务协议可直接执行。
    static func singleHand(for dominantHand: DominantHand) -> TestHand {
        dominantHand == .left ? .left : .right
    }

    static func definition(for kind: ResearchTaskKind) -> ResearchTaskDefinition {
        all.first { $0.kind == kind }
            ?? legacy.first { $0.kind == kind }
            ?? all[0]
    }

    static func referencePoints(for kind: ResearchTaskKind, in size: CGSize) -> [CGPoint] {
        switch kind {
        case .spiralStatic, .spiralRight, .spiralLeft:
            spiralPoints(in: size)
        case .waveTracing:
            wavePoints(in: size)
        case .circleTracing:
            circlePoints(in: size)
        case .holdRight, .holdLeft:
            [CGPoint(x: size.width / 2, y: size.height / 2)]
        case .clockCopy:
            clockReferencePoints(in: size)
        default:
            []
        }
    }

    static func spiralPoints(in size: CGSize, samples: Int = 360) -> [CGPoint] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxRadius = min(size.width, size.height) * 0.38
        return (0...samples).map { index in
            let progress = CGFloat(index) / CGFloat(samples)
            let angle = progress * 7 * .pi
            let radius = 8 + progress * maxRadius
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }

    static func wavePoints(in size: CGSize, samples: Int = 320) -> [CGPoint] {
        let horizontalInset = size.width * 0.08
        return (0...samples).map { index in
            let progress = CGFloat(index) / CGFloat(samples)
            return CGPoint(
                x: horizontalInset + progress * (size.width - horizontalInset * 2),
                y: size.height / 2 + sin(progress * 8 * .pi) * size.height * 0.22
            )
        }
    }

    static func circlePoints(in size: CGSize, samples: Int = 300) -> [CGPoint] {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.32
        return (0...samples).map { index in
            let angle = CGFloat(index) / CGFloat(samples) * 2 * .pi
            return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
    }

    static func clockReferencePoints(in size: CGSize) -> [CGPoint] {
        let referenceRect = CGRect(
            x: size.width * 0.08,
            y: size.height * 0.12,
            width: size.width * 0.34,
            height: size.height * 0.76
        )
        let center = CGPoint(x: referenceRect.midX, y: referenceRect.midY)
        let radius = min(referenceRect.width, referenceRect.height) * 0.42
        var points = (0...240).map { index in
            let angle = CGFloat(index) / 240 * 2 * .pi
            return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
        points.append(contentsOf: [
            center,
            CGPoint(x: center.x - radius * 0.28, y: center.y - radius * 0.48),
            center,
            CGPoint(x: center.x + radius * 0.63, y: center.y - radius * 0.20)
        ])
        return points
    }
}
