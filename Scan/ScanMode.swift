//
//  ScanMode.swift
//  Scan
//
//  The three things the Scan tab can do, and the persisted choice of which
//  one to open in. Codes is the historic behaviour; Live Text hands the
//  viewfinder to VisionKit so a menu or a sign can be read; Bulk keeps every
//  distinct code a pallet throws at the camera instead of stopping at the
//  first.
//
//  The stored value is a stable key ("codes" / "text" / "bulk"), not the
//  label, so the Start Scanning App Intent, the Android port's
//  `ScanModePreference` keys and any future relabelling all agree on what
//  sits in UserDefaults. Every writer goes through `storedValue` /
//  `store(_:in:)` and the one reader through `init(storedValue:)`.
//

import Foundation
import CoreData

enum ScanMode: String, CaseIterable, Identifiable {
    case codes
    case text
    case bulk

    var id: String { rawValue }

    /// What `ScanSettingsKey.scanMode` holds for this mode — the same keys
    /// the Android port's `ScanModePreference.key` stores. Spelled out rather
    /// than borrowed from `rawValue`, so renaming a case (or another enum's
    /// case happening to share a raw value) can never change what sits in
    /// people's UserDefaults.
    var storedValue: String {
        switch self {
        case .codes: return "codes"
        case .text:  return "text"
        case .bulk:  return "bulk"
        }
    }

    /// Reads the persisted value; anything unknown opens Codes. Also takes
    /// the display labels an unreleased build stored, so that device keeps
    /// its mode.
    init(storedValue: String) {
        self = ScanMode.allCases.first { $0.storedValue == storedValue }
            ?? ScanMode.allCases.first { $0.label == storedValue }
            ?? .codes
    }

    /// Makes `mode` the one the Scan tab shows: its `@AppStorage` reads this
    /// key, so a camera already on screen switches live. The Start Scanning
    /// intent writes through here too.
    static func store(_ mode: ScanMode, in defaults: UserDefaults = .standard) {
        defaults.set(mode.storedValue, forKey: ScanSettingsKey.scanMode)
    }

    /// Shown in the mode picker. Same strings as Android.
    var label: String {
        switch self {
        case .codes: return "Codes"
        case .text:  return "Live Text"
        case .bulk:  return "Bulk"
        }
    }

    var symbol: String {
        switch self {
        case .codes: return "qrcode.viewfinder"
        case .text:  return "text.viewfinder"
        case .bulk:  return "square.stack.3d.down.right.fill"
        }
    }

    /// The hint under the mode picker, and Start Scanning's spoken reply.
    /// Codes and Bulk read the same on Android. Live Text says what this
    /// platform's viewfinder does — tap a highlighted block for the card
    /// (Copy / Share / Translate), freeze the frame to select words with the
    /// system menu — where Android's names its list of text blocks; the
    /// sentence about codes is the same on both: one in view is read by
    /// itself, several wait for a tap.
    var footnote: String {
        switch self {
        case .codes: return "Point at a barcode or QR to decode it."
        case .text:  return "Tap highlighted text to copy, share or translate it, or freeze the frame to select words. A single code is read straight away; with several, tap one."
        case .bulk:  return "Keep scanning: every distinct code is collected and counted."
        }
    }

    /// Whether this mode can run on the current device right now. Codes and
    /// Bulk always can (AVFoundation path); Live Text needs VisionKit's
    /// scanner, which Mac Catalyst, Vision Pro, the Simulator and older
    /// hardware lack, and a camera the user has not refused.
    @MainActor
    static func isAvailable(_ mode: ScanMode) -> Bool {
        switch mode {
        case .codes, .bulk:
            return true
        case .text:
            return VisionTextScanner.isAvailable
        }
    }
}

// MARK: - Bulk session

/// Accumulates codes across frames for Bulk mode.
///
/// Dedupe is by *value*, not by geometry: the same code appears in dozens of
/// consecutive frames and a pallet has hundreds of distinct ones. `sightings`
/// tracks how many frames a code was seen in, which is a decent proxy for
/// "was this really scanned, or was it a neighbour's edge" and lets the HUD
/// show progress without pretending to know quantities.
///
/// The list outlives the mode: leaving Bulk — for Codes or Live Text,
/// another tab, or the background — only pauses the capture (`stop()`), and
/// coming back resumes the same list (`start()`). `reset()`, the sheet's
/// Clear, is the one thing that empties it. Memory only, never written to
/// disk: what the user keeps goes through Save all to History or a CSV.
/// Each entry remembers whether Save all to History already wrote it, so a
/// second Save all writes only what was captured since.
@MainActor
final class BulkScanSession: ObservableObject {
    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let value: String
        let symbology: String
        var sightings: Int
        var firstSeen: Date
        var kindLabel: String
        /// Set once Save all to History has written this entry.
        var isSaved = false
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var isRunning = false
    /// Bumped whenever what `csvLines()` writes changes — a new code, another
    /// sighting, a removal, Clear — and not by saving to History, which the
    /// CSV doesn't show. The bulk sheet keys its exported file on it.
    @Published private(set) var csvRevision = 0

    /// Value → row in `entries`. Rebuilt after every removal: rows shift when
    /// an earlier one goes, and a stale row would credit the next sighting to
    /// the wrong code (or run off the end of the list).
    private var index: [String: Int] = [:]

    /// Cap so a runaway camera cannot grow the list without bound. The
    /// limit is generous for a pallet and low enough that the sheet stays
    /// usable; hitting it is reported rather than silently truncating.
    static let capacity = 500

    var count: Int { entries.count }
    var isEmpty: Bool { entries.isEmpty }
    var isFull: Bool { entries.count >= Self.capacity }

    /// What Save all to History still has to write, in list order.
    var unsavedEntries: [Entry] { entries.filter { !$0.isSaved } }
    /// False for an empty list and once every entry is saved — Save all to
    /// History is disabled then.
    var hasUnsavedEntries: Bool { entries.contains { !$0.isSaved } }

    /// Save all to History: one record per entry no earlier call wrote —
    /// value, symbology, first sighting, a "Bulk capture" note — and those
    /// entries marked saved. Returns how many it wrote, the sheet's "N saved
    /// to History". A failed save takes its inserts back out of `context`,
    /// so a later save of anything else can't write them behind the user's
    /// back, and a retry writes them once.
    @discardableResult
    func saveUnsaved(into context: NSManagedObjectContext) throws -> Int {
        let pending = unsavedEntries
        guard !pending.isEmpty else { return 0 }
        var records: [ScanRecord] = []
        for entry in pending {
            let record = ScanRecord(context: context)
            record.id = UUID()
            record.value = entry.value
            record.symbology = entry.symbology
            record.timestamp = entry.firstSeen
            record.notes = "Bulk capture"
            records.append(record)
        }
        do {
            try context.save()
        } catch {
            records.forEach(context.delete)
            // Settles the deletes now, not at the end of the run-loop turn.
            context.processPendingChanges()
            throw error
        }
        let saved = Set(pending.map(\.id))
        for row in entries.indices where saved.contains(entries[row].id) {
            entries[row].isSaved = true
        }
        return records.count
    }

    /// Collects again, carrying on with whatever is already in the list.
    func start() {
        guard !isRunning else { return }
        isRunning = true
    }

    /// Stops collecting; the list stays for the next `start()`.
    func stop() {
        guard isRunning else { return }
        isRunning = false
    }

    /// Empties the list — Clear in the bulk sheet. A running capture keeps
    /// running.
    func reset() {
        entries = []
        index = [:]
        csvRevision += 1
    }

    /// Adds a code. Returns true when it was new, so the caller can fire a
    /// haptic only on genuine progress rather than on every frame.
    @discardableResult
    func ingest(_ code: ScannedCode) -> Bool {
        guard isRunning, !code.value.isEmpty else { return false }
        if let row = index[code.value], entries.indices.contains(row) {
            entries[row].sightings += 1
            csvRevision += 1
            return false
        }
        guard !isFull else { return false }
        index[code.value] = entries.count
        entries.append(Entry(value: code.value,
                             symbology: code.symbology.displayName,
                             sightings: 1,
                             firstSeen: code.timestamp,
                             kindLabel: ScanPayloadParser.parse(code.value,
                                                                symbology: code.symbology).kindLabel))
        csvRevision += 1
        return true
    }

    /// Delete by row index, as `List.onDelete` hands them over. Written out
    /// rather than using `remove(atOffsets:)` so the session stays free of a
    /// SwiftUI dependency and stays testable on its own.
    func remove(at offsets: IndexSet) {
        entries = entries.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)
        reindex()
        csvRevision += 1
    }

    func remove(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        reindex()
        csvRevision += 1
    }

    /// The CSV rows — header first — in the same shape as the History
    /// export, so a spreadsheet that already reads one reads both. Kept as
    /// rows so a value with an embedded line break stays one quoted field.
    func csvLines() -> [String] {
        var lines = ["value,symbology,kind,sightings,first_seen"]
        for entry in entries {
            lines.append([
                HistoryCSV.csvField(entry.value),
                HistoryCSV.csvField(entry.symbology),
                HistoryCSV.csvField(entry.kindLabel),
                String(entry.sightings),
                HistoryCSV.csvField(HistoryCSV.timestampString(entry.firstSeen)),
            ].joined(separator: ","))
        }
        return lines
    }

    func csvText() -> String {
        csvLines().joined(separator: "\n")
    }

    private func reindex() {
        index = Dictionary(entries.enumerated().map { ($0.element.value, $0.offset) },
                           uniquingKeysWith: { first, _ in first })
    }
}
