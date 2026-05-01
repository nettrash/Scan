//
//  HistoryScreen.swift
//  Scan
//
//  Lists previously saved ScanRecord rows with swipe-to-delete and a
//  navigation link to ScanDetailView. As of 1.2 also supports
//  favourite-pinning and CSV export of the visible rows.
//

import SwiftUI
import CoreData

struct HistoryScreen: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        // Sort favourites first (descending on the boolean), then by
        // timestamp newest-first within each bucket. Core Data emits
        // a single SQL `ORDER BY` so this is cheap.
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ScanRecord.isFavorite, ascending: false),
            NSSortDescriptor(keyPath: \ScanRecord.timestamp,  ascending: false),
        ],
        animation: .default
    )
    private var records: FetchedResults<ScanRecord>

    @State private var search = ""
    @State private var favouritesOnly = false
    @State private var exportError: String?
    @State private var showExportError = false

    var body: some View {
        Group {
            if records.isEmpty {
                ContentUnavailableViewCompat(
                    title: "No scans yet",
                    systemImage: "qrcode.viewfinder",
                    description: "Saved scans will appear here."
                )
            } else {
                List {
                    ForEach(filtered) { record in
                        NavigationLink {
                            ScanDetailView(record: record)
                        } label: {
                            HistoryRow(record: record)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                toggleFavourite(record)
                            } label: {
                                Label(record.isFavorite ? "Unstar" : "Star",
                                      systemImage: record.isFavorite ? "star.slash" : "star.fill")
                            }
                            .tint(.yellow)
                        }
                    }
                    .onDelete(perform: deleteRecords)
                }
                .searchable(text: $search, prompt: "Search history")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Toggle(isOn: $favouritesOnly) {
                            Label("Favourites only", systemImage: favouritesOnly ? "star.fill" : "star")
                        }
                        .toggleStyle(.button)
                        .tint(.yellow)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        EditButton()
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button {
                                exportFiltered()
                            } label: {
                                Label("Export visible as CSV (\(filtered.count))", systemImage: "tablecells")
                            }
                            Button {
                                exportAll()
                            } label: {
                                Label("Export all as CSV (\(records.count))", systemImage: "square.and.arrow.up")
                            }
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
        // ShareLink presented via a transient `.sheet(item:)` driven
        // by the `exportShareURLBox` state — avoids pre-computing the
        // CSV until the user asks for it (history can be large enough
        // that doing it on every render would be wasteful) and
        // bypasses SwiftUI's "ShareLink only takes literal Transferables"
        // limitation. Reuses the `ShareSheet` UIKit bridge already
        // declared in `PayloadActionsView.swift`.
        .sheet(item: $exportShareURLBox) { box in
            ShareSheet(items: [box.url])
        }
        .alert("Export failed", isPresented: $showExportError, presenting: exportError) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
    }

    // MARK: - Filtering

    private var filtered: [ScanRecord] {
        let term = search.trimmingCharacters(in: .whitespaces).lowercased()
        var result: [ScanRecord] = Array(records)
        if favouritesOnly {
            result = result.filter { $0.isFavorite }
        }
        if !term.isEmpty {
            result = result.filter { r in
                (r.value ?? "").lowercased().contains(term) ||
                (r.symbology ?? "").lowercased().contains(term) ||
                (r.notes ?? "").lowercased().contains(term)
            }
        }
        return result
    }

    private func deleteRecords(offsets: IndexSet) {
        withAnimation {
            let target = filtered
            offsets.map { target[$0] }.forEach(viewContext.delete)
            try? viewContext.save()
        }
    }

    private func toggleFavourite(_ record: ScanRecord) {
        withAnimation {
            record.isFavorite.toggle()
            try? viewContext.save()
        }
    }

    // MARK: - CSV export

    /// Wrap the URL so we can use `.sheet(item:)` (needs Identifiable).
    private struct ShareURL: Identifiable {
        let id = UUID()
        let url: URL
    }

    @State private var exportShareURLBox: ShareURL?

    private func exportFiltered() { export(filtered) }
    private func exportAll()      { export(Array(records)) }

    private func export(_ rows: [ScanRecord]) {
        do {
            let url = try HistoryCSV.write(rows)
            exportShareURLBox = ShareURL(url: url)
        } catch {
            exportError = error.localizedDescription
            showExportError = true
        }
    }
}

private struct HistoryRow: View {
    @ObservedObject var record: ScanRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 32, height: 32)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.value ?? "")
                        .lineLimit(1)
                        .font(.body)
                    if record.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption2)
                    }
                }
                HStack(spacing: 6) {
                    if let s = record.symbology, !s.isEmpty {
                        Text(s)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.secondary.opacity(0.15), in: Capsule())
                    }
                    if let ts = record.timestamp {
                        Text(ts, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        let payload = ScanPayloadParser.parse(
            record.value ?? "",
            symbology: Symbology(rawValue: record.symbology ?? "") ?? .unknown
        )
        switch payload {
        case .url:          return "safari"
        case .email:        return "envelope"
        case .phone:        return "phone"
        case .sms:          return "message"
        case .wifi:         return "wifi"
        case .geo:          return "map"
        case .contact:      return "person.crop.circle"
        case .calendar:     return "calendar"
        case .otp:          return "key"
        case .productCode:  return "barcode"
        case .crypto:       return "bitcoinsign.circle"
        case .epcPayment:   return "eurosign.circle"
        case .swissQRBill:  return "francsign.circle"
        case .ruPayment:    return "rublesign.circle"
        case .fnsReceipt:   return "doc.text"
        case .emvPayment:   return "creditcard"
        case .sufReceipt:   return "doc.text.magnifyingglass"
        case .ipsPayment:   return "creditcard.viewfinder"
        case .upiPayment:   return "indianrupeesign.circle"
        case .czechSPD:     return "doc.plaintext"
        case .paBySquare:   return "square.grid.2x2"
        case .regionalPayment: return "arrow.up.forward.app"
        case .magnet:       return "link.badge.plus"
        case .gs1:          return "barcode.viewfinder"
        case .boardingPass: return "airplane.departure"
        case .drivingLicense: return "person.text.rectangle"
        case .richURL(let r):
            switch r.kind {
            case .whatsApp, .telegram:    return "message"
            case .appleWallet:            return "wallet.pass"
            case .appStore, .playStore:   return "arrow.down.app"
            case .youtube:                return "play.rectangle"
            case .spotify, .appleMusic:   return "music.note"
            case .googleMaps, .appleMaps: return "map"
            case .digitalIdentity:        return "person.text.rectangle"
            }
        case .text:         return "qrcode"
        }
    }
}

// MARK: - SwiftUI helpers

extension View {
    /// Wrapper that calls SwiftUI's iOS 17+ two-arg `onChange` and forwards
    /// just the new value, the way the rest of this app cares about it.
    /// Kept as a small affordance so call sites stay readable.
    func onValueChange<V: Equatable>(
        of value: V,
        perform action: @escaping (V) -> Void
    ) -> some View {
        onChange(of: value) { _, newValue in
            action(newValue)
        }
    }
}

/// Thin wrapper around SwiftUI's `ContentUnavailableView` so callers in
/// older code paths don't need to construct `Text(description)` themselves.
struct ContentUnavailableViewCompat: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
    }
}

// `ShareSheet` (UIKit-bridged `UIActivityViewController`) is already
// declared in `PayloadActionsView.swift` with property `items: [Any]`.
// We reuse that one — duplicating it here would cause an "Invalid
// redeclaration" error.
