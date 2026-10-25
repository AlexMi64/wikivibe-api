import Foundation
import SwiftUI

/// Presentation only: hiding a card does not change the account or stop polling.
struct AccountWindowLayout: Codable, Equatable {
    enum Arrangement: String, Codable, CaseIterable, Identifiable {
        case automatic, vertical, horizontal
        var id: String { rawValue }
        var title: String {
            switch self {
            case .automatic: return L10n.t("Adaptive grid")
            case .vertical: return L10n.t("Vertical cards")
            case .horizontal: return L10n.t("Horizontal cards")
            }
        }
    }

    enum Density: String, Codable, CaseIterable, Identifiable {
        case comfortable, compact
        var id: String { rawValue }
        var title: String {
            switch self {
            case .comfortable: return L10n.t("Comfortable spacing")
            case .compact: return L10n.t("Compact spacing")
            }
        }
        var spacing: CGFloat { self == .compact ? 12 : 18 }
        var padding: CGFloat { self == .compact ? 14 : 20 }
    }

    enum Card: String, Codable, CaseIterable, Identifiable {
        case account, balance, appearance, apiKeys
        var id: String { rawValue }
        var title: String {
            switch self {
            case .account: return L10n.t("Account")
            case .balance: return L10n.t("Balance")
            case .appearance: return L10n.t("Widget and language")
            case .apiKeys: return L10n.t("API keys")
            }
        }
        var symbol: String {
            switch self {
            case .account: return "person.crop.circle"
            case .balance: return "creditcard"
            case .appearance: return "slider.horizontal.3"
            case .apiKeys: return "key.horizontal"
            }
        }
    }

    var arrangement: Arrangement = .automatic
    var density: Density = .comfortable
    private var order: [Card] = Card.allCases
    private var hidden: Set<Card> = []

    /// A saved order must never create duplicate SwiftUI identities or lose a
    /// newly introduced card. Hidden cards keep their place when shown again.
    var orderedCards: [Card] {
        var seen = Set<Card>()
        return (order + Card.allCases).filter { seen.insert($0).inserted }
    }
    var visibleCards: [Card] { orderedCards.filter(isVisible) }
    func isVisible(_ card: Card) -> Bool { !hidden.contains(card) }

    mutating func setVisible(_ visible: Bool, for card: Card) {
        if visible { hidden.remove(card) } else { hidden.insert(card) }
    }

    mutating func move(_ card: Card, by offset: Int) {
        var cards = orderedCards
        guard let index = cards.firstIndex(of: card),
              cards.indices.contains(index + offset) else { return }
        cards.swapAt(index, index + offset)
        order = cards
    }

    /// Narrow windows always remain usable. Horizontal mode admits a third
    /// column; adaptive mode keeps the dashboard to at most two reading columns.
    func columnCount(availableWidth: CGFloat, sectionCount: Int? = nil) -> Int {
        guard arrangement != .vertical else { return 1 }
        let capacity = max(1, Int((availableWidth + density.spacing) / (320 + density.spacing)))
        let maximum = arrangement == .horizontal ? 3 : 2
        return min(capacity, maximum, max(1, sectionCount ?? visibleCards.count))
    }
}

/// Cards keep stable SwiftUI identities while moving into the shortest column.
/// Measuring their actual height avoids blank grid rows when a model list grows.
struct AccountCardLayout: Layout {
    let columns: Int
    let spacing: CGFloat

    struct Cache {
        var width: CGFloat = .nan
        var frames: [CGRect] = []
        var columnHeights: [CGFloat] = []
        var height: CGFloat = 0
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.width = .nan
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = max(0, proposal.width ?? 320)
        measure(width: width, subviews: subviews, cache: &cache)
        return CGSize(width: width, height: cache.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        if cache.width != bounds.width {
            measure(width: bounds.width, subviews: subviews, cache: &cache)
        }
        for (index, view) in subviews.enumerated() {
            let frame = cache.frames[index]
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       anchor: .topLeading, proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func measure(width: CGFloat, subviews: Subviews, cache: inout Cache) {
        let count = max(1, columns)
        let columnWidth = max(0, (width - CGFloat(count - 1) * spacing) / CGFloat(count))
        if cache.frames.count != subviews.count {
            cache.frames = Array(repeating: .zero, count: subviews.count)
        }
        if cache.columnHeights.count != count {
            cache.columnHeights = Array(repeating: 0, count: count)
        } else {
            for column in cache.columnHeights.indices { cache.columnHeights[column] = 0 }
        }
        cache.width = width
        cache.height = 0
        for (index, view) in subviews.enumerated() {
            var column = 0
            for candidate in 1..<count where cache.columnHeights[candidate] < cache.columnHeights[column] {
                column = candidate
            }
            let size = view.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            let frame = CGRect(x: CGFloat(column) * (columnWidth + spacing),
                               y: cache.columnHeights[column], width: columnWidth, height: size.height)
            cache.frames[index] = frame
            cache.columnHeights[column] = frame.maxY + spacing
            cache.height = max(cache.height, frame.maxY)
        }
    }
}
