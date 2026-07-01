import CoreGraphics
import Foundation

public struct HiddenWindowSnapshot: Codable, Equatable {
    public let windowID: WindowID
    public let pid: pid_t
    public let bundleID: String?
    public let appName: String
    public let title: String
    public let workspace: String
    public let originalFrame: WindowFrame
    public let hiddenPosition: CGPoint
    public let updatedAt: Date

    public init(
        windowID: WindowID,
        pid: pid_t,
        bundleID: String?,
        appName: String,
        title: String,
        workspace: String,
        originalFrame: WindowFrame,
        hiddenPosition: CGPoint,
        updatedAt: Date = Date()
    ) {
        self.windowID = windowID
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.workspace = workspace
        self.originalFrame = originalFrame
        self.hiddenPosition = hiddenPosition
        self.updatedAt = updatedAt
    }
}

public protocol HiddenWindowSnapshotStoring: AnyObject {
    func loadSnapshots() throws -> [HiddenWindowSnapshot]
    func upsertSnapshot(_ snapshot: HiddenWindowSnapshot)
    func removeSnapshot(windowID: WindowID, pid: pid_t?)
}

public final class FileHiddenWindowSnapshotStore: HiddenWindowSnapshotStoring {
    public static let `default` = FileHiddenWindowSnapshotStore(
        url: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("kkaci", isDirectory: true)
            .appendingPathComponent("snapshot.json")
    )

    public let url: URL
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "kkaci.hidden-window-snapshot-store")
    private var snapshotsByKey: [SnapshotKey: HiddenWindowSnapshot]?

    public init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    public func loadSnapshots() throws -> [HiddenWindowSnapshot] {
        try queue.sync {
            try loadSnapshotsIfNeeded()
            return sortedSnapshots()
        }
    }

    public func upsertSnapshot(_ snapshot: HiddenWindowSnapshot) {
        queue.async { [self] in
            loadSnapshotsForAsyncMutation()
            snapshotsByKey?[SnapshotKey(snapshot)] = snapshot
            writeSnapshotsIgnoringErrors()
        }
    }

    public func removeSnapshot(windowID: WindowID, pid: pid_t?) {
        queue.async { [self] in
            loadSnapshotsForAsyncMutation()
            guard snapshotsByKey != nil else {
                return
            }

            if let pid {
                snapshotsByKey?[SnapshotKey(windowID: windowID, pid: pid)] = nil
            } else {
                for key in snapshotsByKey?.keys.filter({ $0.windowID == windowID }) ?? [] {
                    snapshotsByKey?[key] = nil
                }
            }
            writeSnapshotsIgnoringErrors()
        }
    }

    private func loadSnapshotsIfNeeded() throws {
        guard snapshotsByKey == nil else {
            return
        }

        guard fileManager.fileExists(atPath: url.path) else {
            snapshotsByKey = [:]
            return
        }

        let data = try Data(contentsOf: url)
        let document = try JSONDecoder().decode(SnapshotDocument.self, from: data)
        snapshotsByKey = Dictionary(uniqueKeysWithValues: document.snapshots.map {
            (SnapshotKey($0), $0)
        })
    }

    private func loadSnapshotsForAsyncMutation() {
        if snapshotsByKey == nil {
            try? loadSnapshotsIfNeeded()
        }
        if snapshotsByKey == nil {
            snapshotsByKey = [:]
        }
    }

    private func writeSnapshotsIgnoringErrors() {
        do {
            let directory = url.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            let snapshots = sortedSnapshots()
            guard !snapshots.isEmpty else {
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
                return
            }

            let data = try JSONEncoder().encode(SnapshotDocument(snapshots: snapshots))
            try data.write(to: url, options: .atomic)
        } catch {
            // Snapshot persistence must not block or fail window manipulation.
        }
    }

    private func sortedSnapshots() -> [HiddenWindowSnapshot] {
        (snapshotsByKey ?? [:])
            .values
            .sorted {
                if $0.pid == $1.pid {
                    return $0.windowID < $1.windowID
                }
                return $0.pid < $1.pid
            }
    }
}

private struct SnapshotDocument: Codable {
    let snapshots: [HiddenWindowSnapshot]
}

private struct SnapshotKey: Hashable {
    let windowID: WindowID
    let pid: pid_t

    init(windowID: WindowID, pid: pid_t) {
        self.windowID = windowID
        self.pid = pid
    }

    init(_ snapshot: HiddenWindowSnapshot) {
        self.windowID = snapshot.windowID
        self.pid = snapshot.pid
    }
}
