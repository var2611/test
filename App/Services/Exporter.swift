import Foundation
import AppKit
import UniformTypeIdentifiers
import WattsonCore

/// CSV and JSON export of power history — a Pro feature.
///
/// Uses `NSSavePanel`, which is what gives a sandboxed app permission to write to
/// the chosen location; no additional entitlement is needed or requested.
@MainActor
enum Exporter {

    enum Format: String, CaseIterable, Identifiable {
        case csv, json
        var id: String { rawValue }
        var fileExtension: String { rawValue }
        var title: String { rawValue.uppercased() }
    }

    static func export(history: PowerHistory, window: TimeInterval, format: Format) {
        let panel = NSSavePanel()
        panel.title = "Export power history"
        panel.nameFieldStringValue = defaultFilename(format: format)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = format == .csv ? [.commaSeparatedText] : [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data: Data
            switch format {
            case .csv:
                data = Data(history.csv(within: window).utf8)
            case .json:
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                data = try encoder.encode(history.samples(within: window))
            }
            try data.write(to: url, options: [.atomic])
        } catch {
            present(error: error)
        }
    }

    private static func defaultFilename(format: Format) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "wattson-history-\(formatter.string(from: Date())).\(format.fileExtension)"
    }

    private static func present(error: Error) {
        Log.history.error("Export failed: \(error.localizedDescription, privacy: .public)")
        let alert = NSAlert()
        alert.messageText = "Export failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
