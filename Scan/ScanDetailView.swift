//
//  ScanDetailView.swift
//  Scan
//
//  Detail view for a saved ScanRecord — shows the decoded value, symbology,
//  timestamp, smart actions, copy/share, and editable notes.
//

import SwiftUI
import CoreData

struct ScanDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var record: ScanRecord

    @State private var notes: String = ""
    @State private var notesLoaded = false

    private var symbology: Symbology {
        Symbology(rawValue: record.symbology ?? "") ?? .unknown
    }
    private var raw: String { record.value ?? "" }
    private var payload: ScanPayload {
        ScanPayloadParser.parse(raw, symbology: symbology)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(payload.kindLabel)
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                    Spacer()
                    Text(record.symbology ?? "Unknown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(raw)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                if let ts = record.timestamp {
                    Text(ts, format: .dateTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            PayloadActionsView(payload: payload, raw: raw)

            Section("Notes") {
                TextField("Add a note", text: $notes, axis: .vertical)
                    .lineLimit(1...6)
                    .onValueChange(of: notes) { newValue in
                        // Persist on change.
                        record.notes = newValue.isEmpty ? nil : newValue
                        try? viewContext.save()
                    }
            }

            Section {
                Button(role: .destructive) {
                    viewContext.delete(record)
                    try? viewContext.save()
                    dismiss()
                } label: {
                    Label("Delete scan", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Scan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !notesLoaded {
                notes = record.notes ?? ""
                notesLoaded = true
            }
        }
    }
}
