import Foundation
import Observation

@Observable
final class CategoryPairStore: @unchecked Sendable {
    static let shared = CategoryPairStore()

    struct PairKey: Hashable, Codable {
        let first: String
        let second: String

        init(_ x: String, _ y: String) {
            if x <= y {
                self.first = x
                self.second = y
            } else {
                self.first = y
                self.second = x
            }
        }
    }

    private let storageKey = "categoryPairs.v1"
    private(set) var pairs: [PairKey] = []

    private init() {
        load()
    }

    func contains(_ x: String, _ y: String) -> Bool {
        pairs.contains(PairKey(x, y))
    }

    func add(_ x: String, _ y: String) {
        guard x != y else { return }
        let key = PairKey(x, y)
        guard !pairs.contains(key) else { return }
        pairs.append(key)
        save()
    }

    func remove(_ pair: PairKey) {
        pairs.removeAll { $0 == pair }
        save()
    }

    func renameCategory(from oldName: String, to newName: String) {
        let renamed = pairs.map { pair in
            PairKey(
                pair.first == oldName ? newName : pair.first,
                pair.second == oldName ? newName : pair.second
            )
        }
        pairs = Array(Set(renamed)).filter { $0.first != $0.second }.sorted {
            if $0.first != $1.first { return $0.first < $1.first }
            return $0.second < $1.second
        }
        save()
    }

    func removeCategory(_ category: String) {
        pairs.removeAll { $0.first == category || $0.second == category }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PairKey].self, from: data) else {
            return
        }
        pairs = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(pairs) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
