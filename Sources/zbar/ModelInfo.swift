import Foundation

/// A model as reported by `zdx models list --json`.
struct ModelInfo {
    let id: String
    let displayName: String
    let provider: String

    var row: PickerRow {
        PickerRow(title: displayName, subtitle: id)
    }

    /// Case-insensitive match across the fields a user would type.
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let haystack = "\(id) \(displayName) \(provider)".lowercased()
        // Every whitespace-separated term must appear, so "claude opus" narrows.
        return query.lowercased().split(separator: " ").allSatisfy { haystack.contains($0) }
    }
}

extension ZdxClient {
    /// Lists models from enabled providers. Returns an empty list rather than
    /// throwing: an unavailable list should disable the picker, not break asking.
    func models(timeout: TimeInterval = 20) async -> [ModelInfo] {
        guard let binary else { return [] }

        guard
            let result = try? await Shell.run(
                executable: binary,
                arguments: ["models", "list", "--json"],
                timeout: timeout
            ),
            result.status == 0,
            let data = result.stdout.data(using: .utf8),
            let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            Log.error("could not list models")
            return []
        }

        // `@fast` variants are not separate entries: a model that supports one
        // carries it in `fast_id`. Emit both, adjacent, so the picker offers it.
        return raw.flatMap { entry -> [ModelInfo] in
            guard let id = entry["id"] as? String else { return [] }
            let name = entry["display_name"] as? String ?? id
            let provider = entry["provider"] as? String ?? ""

            var variants = [ModelInfo(id: id, displayName: name, provider: provider)]
            if let fastID = entry["fast_id"] as? String {
                variants.append(
                    ModelInfo(id: fastID, displayName: "\(name) (fast)", provider: provider)
                )
            }
            return variants
        }
    }
}
