import CoreGraphics

/// Packs cards into free space, avoiding obstacles and each other.
/// Plain geometry in AppKit coordinates (origin bottom-left).
enum CardLayout {
    /// Returns one rect per card, or `nil` for a card that doesn't fit anywhere.
    static func place(sizes: [CGSize], in area: CGRect, obstacles: [CGRect],
                      gap: CGFloat, mode: ArrangeMode) -> [CGRect?] {
        let relevant = obstacles.filter { $0.intersects(area.insetBy(dx: -gap, dy: -gap)) }
        var placed: [CGRect] = []
        var result: [CGRect?] = []

        for size in sizes {
            let blockers = relevant + placed
            let best = candidates(for: size, in: area, around: blockers, gap: gap)
                .filter { rect in !blockers.contains { $0.insetBy(dx: -gap, dy: -gap).intersects(rect) } }
                .min { score($0, area, mode) < score($1, area, mode) }
            result.append(best)
            if let best { placed.append(best) }
        }
        return result
    }

    /// Candidate spots aligned to the screen edges and to the edges of every other rect.
    private static func candidates(for size: CGSize, in area: CGRect, around rects: [CGRect], gap: CGFloat) -> [CGRect] {
        var xs: Set<CGFloat> = [area.minX, area.maxX - size.width]
        var tops: Set<CGFloat> = [area.maxY]
        for rect in rects {
            xs.formUnion([rect.maxX + gap, rect.minX - gap - size.width, rect.minX, rect.maxX - size.width])
            tops.formUnion([rect.minY - gap, rect.maxY])
        }
        var rects: [CGRect] = []
        for x in xs where x >= area.minX - 0.5 && x + size.width <= area.maxX + 0.5 {
            for top in tops where top <= area.maxY + 0.5 && top - size.height >= area.minY - 0.5 {
                rects.append(CGRect(x: x, y: top - size.height, width: size.width, height: size.height))
            }
        }
        return rects
    }

    /// Lower is better. Grid grows from the top-right, column fills top-down then leftwards,
    /// row fills left-to-right then downwards.
    private static func score(_ rect: CGRect, _ area: CGRect, _ mode: ArrangeMode) -> CGFloat {
        let fromTop = area.maxY - rect.maxY
        let fromRight = area.maxX - rect.maxX
        let fromLeft = rect.minX - area.minX
        switch mode {
        case .grid: return fromTop + fromRight
        case .column: return fromRight * 1000 + fromTop
        case .row: return fromTop * 1000 + fromLeft
        }
    }
}
