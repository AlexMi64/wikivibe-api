import Foundation

/// What the account holds, as the server reports it.
///
/// The API returns money in the server's own unit, so the unit is read from
/// `/settings/public` rather than assumed to be dollars: the panel lets the
/// operator change `balance_unit_name`/`balance_unit_symbol`, and a client that
/// hardcoded "$" would keep printing dollars after that change.
///
/// Three separate amounts, because they are three separate things and the panel
/// shows them separately:
///   - `regular` is spendable balance, the number a user means by "balance";
///   - `bonus` is promotional credit, which expires on its own terms and cannot
///     be treated as the same money;
///   - `frozen` is held against something in flight and is not spendable.
///
/// A missing field is not zero. `bonus` and `frozen` are optional because the
/// server omits them when the account has none — showing "0" there would claim
/// the account was checked, and for `bonus` the server does send an explicit
/// zero when the account really has none, so the two cases stay distinguishable.
struct WikiVibeWallet: Equatable {
    let regular: Double
    let bonus: Double?
    let frozen: Double?
    /// Server-configured unit, e.g. `USD` / `$`.
    let currencyName: String
    let currencySymbol: String

    /// `$116.11`. Falls back to the unit name when the server sends no symbol,
    /// and to a bare number when it sends neither.
    func amount(_ value: Double) -> String {
        let number = String(format: "%.2f", value)
        if !currencySymbol.isEmpty { return currencySymbol + number }
        if !currencyName.isEmpty { return number + " " + currencyName }
        return number
    }

    var regularText: String { amount(regular) }

    /// The bonus row is only shown when the server actually reported one.
    var bonusText: String? { bonus.map(amount) }
    var frozenText: String? { frozen.flatMap { $0 == 0 ? nil : amount($0) } }
}
