import Foundation

@MainActor
protocol VaultLocationGateway {
    func location(for kind: VaultKind) -> VaultLocation?
    func choose(for kind: VaultKind) -> VaultLocation?
}
