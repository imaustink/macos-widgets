import Foundation

// The host app writes JSON files into the shared App Group container; the widget extension reads them.

/// Set per build from the signing team (see project.yml), so forks don't collide.
let appGroupID: String? = Bundle.main.object(forInfoDictionaryKey: "KWAppGroupID") as? String

/// A Codable value stored as one JSON file in the App Group container.
struct JSONStore<Value: Codable> {
    let fileName: String

    var fileURL: URL? {
        guard let id = appGroupID, !id.isEmpty else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)?
            .appendingPathComponent(fileName)
    }

    func load() -> Value? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(Value.self, from: data)
    }

    func save(_ value: Value) {
        guard let url = fileURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try? enc.encode(value).write(to: url, options: .atomic)
    }
}

enum Stores {
    static let snapshot = JSONStore<Snapshot>(fileName: "snapshot.json")
    static let namespaces = JSONStore<NamespaceFile>(fileName: "namespaces.json")
    static let ssh = JSONStore<SSHFile>(fileName: "ssh.json")
}
