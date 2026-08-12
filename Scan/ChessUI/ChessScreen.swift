//
//  ChessScreen.swift
//  Scan
//
//  The Chess tab: read a position, fix it, get a move for each side.
//
//  ## Three stages, one screen
//
//  Capture → edit → analyse. They are one scrolling screen rather than a
//  wizard because the middle stage is not optional and users skip
//  optional steps. Recognition will misread a square sometimes — that is
//  arithmetic, not pessimism: at 99.5% per square only 73% of whole
//  boards come back right — so the board is *always* presented editable,
//  with the shakiest squares ringed, before any move is suggested.
//
//  The prototype this replaces had no edit step at all, which is half of
//  why it felt broken: a single misread square produced a confident,
//  wrong answer with no way to correct it.
//
//  ## Side to move is asked, never guessed
//
//  A photograph cannot show whose turn it is, so the screen answers for
//  *both* sides. That is not a hedge — it is the honest reading of the
//  input, and for most positions only one side is even legal to move (if
//  Black stands in check it cannot be White's turn), which the analysis
//  section says plainly instead of inventing a move.
//

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ChessScreen: View {
    @StateObject private var model = ChessScreenModel()
    @AppStorage(ScanSettingsKey.chessThinkTime) private var thinkTimeRaw = ChessEngine.ThinkTime.standard.rawValue
    @AppStorage(ScanSettingsKey.chessWhiteAtBottom) private var whiteAtBottom = true

    @State private var photoPickerPresented = false
    @State private var filePickerPresented = false
    @State private var exportMessage: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var importError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                boardSection
                sourceSection
                positionSection
                analysisSection
            }
            .padding()
        }
        .navigationTitle("Chess")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        model.loadStartingPosition()
                    } label: {
                        Label("Set up starting position", systemImage: "arrow.counterclockwise")
                    }
                    Button(role: .destructive) {
                        model.clearBoard()
                    } label: {
                        Label("Clear board", systemImage: "trash")
                    }
                    Divider()
                    Toggle(isOn: $whiteAtBottom) {
                        Label("White at bottom", systemImage: "arrow.up.arrow.down")
                    }
                } label: {
                    Label("Board", systemImage: "ellipsis.circle")
                }
            }
        }
        .photosPicker(isPresented: $photoPickerPresented,
                      selection: $photoItem,
                      matching: .images)
        .onValueChange(of: photoItem) { item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .onValueChange(of: filePickerPresented) { presenting in
            guard presenting else { return }
            filePickerPresented = false
            // `.fileImporter` never fires its completion on Mac Catalyst —
            // reuse the imperative picker the scanner tab already relies on.
            DocumentPicker.pick(contentTypes: [.image]) { url in
                guard let data = try? Data(contentsOf: url),
                      let image = UIImage(data: data) else {
                    importError = "That file isn't a readable image."
                    return
                }
                model.beginCornerPlacement(with: image)
            }
        }
        .alert("Couldn't open that image",
               isPresented: Binding(get: { importError != nil },
                                    set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .fullScreenCover(item: Binding(
            get: { model.pendingImage.map(IdentifiedImage.init) },
            set: { if $0 == nil { model.cancelCornerPlacement() } }
        )) { wrapper in
            ChessCornerAdjustView(
                image: wrapper.image,
                corners: $model.pendingCorners,
                onCancel: { model.cancelCornerPlacement() },
                onConfirm: { model.confirmCornerPlacement() }
            )
        }
        .onAppear { model.thinkTime = thinkTimeRaw }
        .onValueChange(of: thinkTimeRaw) { model.thinkTime = $0 }
    }

    /// Load a picked photo and go straight to corner placement.
    ///
    /// Downscaled first: a 12-megapixel photograph is far more than the
    /// warp needs, and holding several at full size while the user drags
    /// corners is how a memory warning happens on an older device.
    private func loadPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            importError = "That photo couldn't be loaded."
            return
        }
        model.beginCornerPlacement(with: Self.downscaled(image, longestSide: 2048))
    }

    /// Proportional downscale, no-op when already small enough.
    static func downscaled(_ image: UIImage, longestSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > longestSide else { return image }
        let scale = longestSide / longest
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    // MARK: - Board

    private var boardSection: some View {
        VStack(spacing: 12) {
            ChessBoardView(
                placement: model.placement,
                whiteAtBottom: whiteAtBottom,
                arrow: model.arrow,
                decorations: model.decorations,
                onTap: model.tapped
            )

            if let palette = model.paletteSquare {
                ChessPiecePalette(
                    square: palette,
                    current: model.placement[palette.index],
                    onPick: { model.setPiece($0, at: palette) }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.snappy(duration: 0.2), value: model.paletteSquare)
    }

    // MARK: - Where the position came from

    @ViewBuilder
    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.recognizerAvailable {
                // Vision Pro has no third-party camera access at all, so
                // import is the only path there — the same rule the
                // scanner tab already follows.
                if !Platform.isVisionOS {
                    Button {
                        model.captureRequested = true
                    } label: {
                        Label("Scan a board", systemImage: "camera.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Label {
                    Text("Board recognition isn't in this build yet — set the position up by "
                         + "tapping squares, or paste a FEN below.")
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            // Import stays enabled even with no models: manual corner
            // placement rectifies the board on its own, and that is what
            // collects the data the models will be trained on.
            HStack {
                Button {
                    photoPickerPresented = true
                } label: {
                    Label("Photos", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    filePickerPresented = true
                } label: {
                    Label("Files", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)

            if let board = model.warpedBoard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Rectified board")
                        .font(.subheadline.weight(.medium))
                    Image(uiImage: board)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("Set the position above to match, then save it as a training sample.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if model.canExportTrainingSample {
                        Button {
                            exportMessage = model.exportTrainingSample()
                        } label: {
                            Label("Save training sample", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                    }
                    if let exportMessage {
                        Text(exportMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !model.repairs.isEmpty {
                DisclosureGroup("Adjusted \(model.repairs.count) thing\(model.repairs.count == 1 ? "" : "s") to make this a legal position") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.repairs, id: \.self) { repair in
                            Text("• \(repair)")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.footnote)
            }
        }
    }

    // MARK: - The things a photo can't tell us

    private var positionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Position")
                .font(.headline)

            Picker("Castling", selection: $model.castlingRightsRaw) {
                Text("No castling").tag(UInt8(0))
                Text("Both sides").tag(ChessCastlingRights.all.rawValue)
            }
            .pickerStyle(.segmented)

            HStack {
                Text("FEN")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    UIPasteboard.general.string = model.placementFEN
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
            }
            Text(model.placementFEN)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Analysis

    private var analysisSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Best move")
                    .font(.headline)
                Spacer()
                if model.isAnalysing {
                    ProgressView().controlSize(.small)
                }
            }

            ForEach([ChessColor.white, ChessColor.black], id: \.self) { side in
                ChessSideAnalysisRow(
                    side: side,
                    outcome: model.outcome(for: side),
                    isHighlighted: model.highlightedSide == side,
                    onSelect: { model.highlight(side) }
                )
            }

            Picker("Thinking time", selection: $thinkTimeRaw) {
                ForEach(ChessEngine.ThinkTime.allCases, id: \.rawValue) { option in
                    Text(option.displayName).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

// MARK: - One side's answer

private struct ChessSideAnalysisRow: View {
    let side: ChessColor
    let outcome: ChessAnalysisOutcome?
    let isHighlighted: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: side == .white ? "circle" : "circle.fill")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 4) {
                    Text(side.displayName)
                        .font(.subheadline.weight(.semibold))
                    content
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHighlighted ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isHighlighted ? Color.accentColor : Color.secondary.opacity(0.25))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch outcome {
        case .none:
            Text("—").foregroundStyle(.secondary)

        case .move(let analysis):
            HStack(spacing: 8) {
                Text(analysis.san)
                    .font(.title3.weight(.bold).monospaced())
                Text(analysis.displayScore)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if !analysis.principalVariationSAN.isEmpty {
                Text(analysis.principalVariationSAN)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text("depth \(analysis.depth) · \(analysis.nodes.formatted()) positions")
                .font(.caption2)
                .foregroundStyle(.tertiary)

        case .terminal(let state):
            Text(Self.describe(state))
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case .notLegal(let problems):
            // The common, informative case — not an error. Most boards are
            // legal for exactly one side to move.
            VStack(alignment: .leading, spacing: 2) {
                ForEach(problems.prefix(3), id: \.self) { problem in
                    Text(problem.message)
                }
            }
            .font(.caption)
            .foregroundStyle(.orange)
        }
    }

    private static func describe(_ state: ChessPosition.Outcome) -> String {
        switch state {
        case .checkmate: return "Checkmated — no move to make."
        case .stalemate: return "Stalemate — no legal move, but not in check."
        case .fiftyMoveRule: return "Drawn by the fifty-move rule."
        case .insufficientMaterial: return "Drawn — neither side can force mate."
        case .ongoing: return "—"
        }
    }
}

// MARK: - Piece palette

/// The editor's piece picker, shown under the board when a square is
/// tapped. Inline rather than a sheet: correcting three squares should be
/// three taps and a glance, not three modal presentations.
private struct ChessPiecePalette: View {
    let square: ChessSquare
    let current: ChessPiece?
    let onPick: (ChessPiece?) -> Void

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What's on \(square.algebraic)?")
                .font(.subheadline.weight(.medium))

            LazyVGrid(columns: columns, spacing: 8) {
                paletteButton(nil)
                ForEach([ChessColor.white, ChessColor.black], id: \.self) { color in
                    ForEach(ChessPieceKind.allCases, id: \.self) { kind in
                        paletteButton(ChessPiece(color, kind))
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
    }

    private func paletteButton(_ piece: ChessPiece?) -> some View {
        let isCurrent = piece == current
        return Button {
            onPick(piece)
        } label: {
            Group {
                if let piece {
                    Text(ChessBoardView.glyph(for: piece.kind))
                        .font(.system(size: 26))
                        .foregroundStyle(piece.color == .white ? Color.white : Color.black)
                        .shadow(color: piece.color == .white ? .black : .white, radius: 0.5)
                } else {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCurrent ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(piece.map { "\($0.color.displayName) \($0.kind.displayName)" } ?? "Empty")
    }
}

#Preview {
    NavigationStack { ChessScreen() }
}

/// `fullScreenCover(item:)` needs an `Identifiable`, and `UIImage` is not.
///
/// Wrapping rather than using `isPresented` keeps the image and its
/// presentation in one piece of state, so there is no window where the
/// sheet is up with nothing to show.
///
/// **The id must be derived from the image, never minted.** This wrapper is
/// built inside the presentation binding's `get`, which SwiftUI re-runs on
/// every `body` evaluation — and dragging a corner mutates
/// `model.pendingCorners`, which publishes, which re-evaluates `body`. With
/// `let id = UUID()` every one of those passes produced a *different*
/// identity, so SwiftUI concluded the presented item had changed and
/// rebuilt `ChessCornerAdjustView` from scratch: `@State` reset, in-flight
/// `DragGesture` destroyed. The corner placement screen let you nudge one
/// handle and then went dead — which, since manual corners are the only way
/// to warp a board until the models ship, made the whole training-capture
/// path unusable.
///
/// `pendingImage` is stored, so the instance is stable for as long as the
/// cover is up and `ObjectIdentifier` is the honest identity here.
struct IdentifiedImage: Identifiable {
    let image: UIImage
    var id: ObjectIdentifier { ObjectIdentifier(image) }
}
