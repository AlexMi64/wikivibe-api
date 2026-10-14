import Foundation

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
    func columnCount(availableWidth: CGFloat) -> Int {
        guard arrangement != .vertical else { return 1 }
        let capacity = max(1, Int((availableWidth + density.spacing) / (320 + density.spacing)))
        let maximum = arrangement == .horizontal ? 3 : 2
        return min(capacity, maximum, max(1, visibleCards.count))
    }
}
