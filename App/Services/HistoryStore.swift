import Foundation
import Combine
import WattsonCore

/// Persists power history to the app's sandbox container.
///
/// Design constraints that shaped this:
/// * a menu bar app runs for weeks, so the in-memory series is hard-capped;
/// * disk writes are debounced — history is worth keeping, not worth thrashing an SSD;
/// * a corrupt or unreadable file loses history, never launches into an error state.
@MainActor
final class HistoryStore: ObservableObject {

    /// One point every 30 s is plenty for a wattage trend and keeps a month of
    /// history at roughly 90 000 samples before retention pruning.
    private static let minimumSampleInterval: TimeInterval = 30
    private static let flushInterval: TimeInterval = 120

    @Published private(set) var history: PowerHistory

    private let fileURL: URL?
    private var lastSampleAt: Date?
    private var lastFlushAt = Date.distantPast
    private var isDirty = false

    init(fileURL: URL? = HistoryStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.history = HistoryStore.load(from: fileURL)
    }

    static func defaultFileURL() -> URL? {
        do {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("Wattson", isDirectory: true)

            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent("history.json")
        } catch {
            Log.history.error("No writable history location: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Records a snapshot if enough time has passed since the last one.
    func record(_ snapshot: PowerSnapshot, retention: TimeInterval) {
        if let lastSampleAt, snapshot.timestamp.timeIntervalSince(lastSampleAt) < HistoryStore.minimumSampleInterval {
            return
        }
        lastSampleAt = snapshot.timestamp
        history.append(snapshot: snapshot)
        history.prune(olderThan: retention, now: snapshot.timestamp)
        isDirty = true

        if Date().timeIntervalSince(lastFlushAt) >= HistoryStore.flushInterval {
            flush()
        }
    }

    func clear() {
        history = PowerHistory()
        isDirty = true
        flush()
    }

    /// Writes the series out. Called on a timer, on state changes and at termination.
    func flush() {
        guard isDirty, let fileURL else { return }
        lastFlushAt = Date()
        isDirty = false

        let snapshotOfHistory = history
        // Encoding a month of samples off the main thread keeps the menu bar smooth.
        Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(snapshotOfHistory)
                try data.write(to: fileURL, options: [.atomic])
            } catch {
                Log.history.error("History write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func load(from fileURL: URL?) -> PowerHistory {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return PowerHistory() }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(PowerHistory.self, from: data)
        } catch {
            Log.history.error("History unreadable, starting fresh: \(error.localizedDescription, privacy: .public)")
            return PowerHistory()
        }
    }
}
