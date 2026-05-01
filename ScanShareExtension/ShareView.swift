//
//  ShareView.swift
//  ScanShareExtension
//
//  The SwiftUI surface inside the iOS share-sheet sheet. Three states:
//   - Loading: we're walking the providers and decoding.
//   - Ready: we have a list of recognised codes; user picks one to
//     act on.
//   - Failed: nothing decoded, show a friendly empty state.
//
//  Actions per code: copy the raw value, or "Open in Scan" which
//  hands the payload back via the host app's Universal-Link route
//  (`https://nettrash.me/scan/<base64url-payload>`). The full
//  payload-action surface (open URL / call / add contact / add
//  calendar event / open wallet) lives in PayloadActionsView in
//  the main app — extensions can't perform those host-app actions
//  themselves, so we hand off to the main app via the deep link.
//

import SwiftUI
import UniformTypeIdentifiers

struct ShareView: View {

    /// One thing the user shared. The provider is loaded lazily by
    /// the decoder — keeping it as `NSItemProvider` rather than
    /// pre-loading all the bytes into memory means a 10-image batch
    /// doesn't OOM the extension before we even start.
    struct Item: Identifiable {
        let id = UUID()
        let provider: NSItemProvider
        let kind: Kind

        enum Kind { case image, pdf }
    }

    let items: [Item]
    let onDone: () -> Void
    /// Callback fired when the user taps "Open in Scan" on a
    /// specific result. The full `ScannedCode` is passed so the
    /// host can include the symbology in its deep-link encoding —
    /// the parser needs the symbology hint to disambiguate
    /// e.g. EAN-13 product codes from raw 13-digit numeric strings.
    let onOpenInApp: (ScannedCode) -> Void

    @State private var phase: Phase = .loading

    enum Phase {
        case loading
        case ready([ScannedCode])
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Scan")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done", action: onDone)
                    }
                }
        }
        .task { await decodeAll() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Reading shared content…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No barcodes found")
                    .font(.title3.bold())
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready(let codes):
            if codes.count == 1 {
                ResultDetail(code: codes[0], onOpenInApp: onOpenInApp)
            } else {
                ResultList(codes: codes, onOpenInApp: onOpenInApp)
            }
        }
    }

    // MARK: - Decoding

    private func decodeAll() async {
        guard !items.isEmpty else {
            phase = .failed("Nothing was shared.")
            return
        }
        var tuples: [(Data, Bool)] = []
        for item in items {
            if let data = await load(item) {
                tuples.append((data, item.kind == .pdf))
            }
        }
        guard !tuples.isEmpty else {
            phase = .failed("Couldn't read any of the shared files.")
            return
        }
        do {
            let codes = try await ImageDecoder.decodeBatch(items: tuples)
            phase = .ready(codes)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Pull the bytes off an NSItemProvider. We try the
    /// `loadDataRepresentation` path first (covers most cases including
    /// HEIC, PNG, JPEG, PDF) and fall back to file-URL when the
    /// provider only exposes the latter.
    private func load(_ item: Item) async -> Data? {
        let typeIdentifier = (item.kind == .pdf
                              ? UTType.pdf.identifier
                              : UTType.image.identifier)
        return await withCheckedContinuation { cont in
            item.provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                cont.resume(returning: data)
            }
        }
    }
}

// MARK: - Result-detail (single code)

private struct ResultDetail: View {
    let code: ScannedCode
    let onOpenInApp: (ScannedCode) -> Void

    private var payload: ScanPayload {
        ScanPayloadParser.parse(code.value, symbology: code.symbology)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(payload.kindLabel)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                    Spacer()
                    Text(code.symbology.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(code.value)
                    .font(.body.monospaced())
                    .textSelection(.enabled)

                actions
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private var actions: some View {
        Button {
            UIPasteboard.general.string = code.value
        } label: {
            Label("Copy raw value", systemImage: "doc.on.doc")
        }
        .buttonStyle(.bordered)

        Button {
            onOpenInApp(code)
        } label: {
            Label("Open in Scan", systemImage: "arrow.up.right.square")
        }
        .buttonStyle(.borderedProminent)
    }
}

// MARK: - Result-list (multi-code)

private struct ResultList: View {
    let codes: [ScannedCode]
    let onOpenInApp: (ScannedCode) -> Void

    var body: some View {
        List(codes) { code in
            VStack(alignment: .leading, spacing: 6) {
                Text(code.value)
                    .font(.body.monospaced())
                    .lineLimit(2)
                Text(code.symbology.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button {
                        UIPasteboard.general.string = code.value
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc").labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onOpenInApp(code)
                    } label: {
                        Label("Open in Scan", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// `ScannedCode` already has a stable `id` field for SwiftUI lists.
