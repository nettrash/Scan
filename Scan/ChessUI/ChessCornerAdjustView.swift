//
//  ChessCornerAdjustView.swift
//  Scan
//
//  Place the board's four corners by hand.
//
//  This is the manual override for `BoardNet` — and, until the models are
//  trained, the *only* way to rectify a board. That makes it the bootstrap
//  out of the chicken-and-egg: with corners supplied by hand the app can
//  warp a real photograph today, the user names the position in the
//  editor, and the pair becomes a fine-tuning sample. Collect a few
//  hundred and the models can be trained; once they are, this view demotes
//  itself to the safety net for boards `BoardNet` misses.
//
//  ## The magnifier is not decoration
//
//  A board corner needs placing to within a few pixels — a fifth of a
//  square is enough to shift the whole grid — and a fingertip covers
//  roughly forty. Without a loupe the user is aiming at something they
//  cannot see, and the resulting corners are worse than a mediocre model's.
//  So the loupe shows the area *under* the finger, offset to the opposite
//  side of the handle.
//
//  ## Coordinates
//
//  Corners are stored in **image pixels, origin top-left** — the same
//  space `BoardNet` predicts in and `ChessBoardWarp.warp` consumes.
//  The view converts to and from its own layout on the fly, so nothing
//  downstream has to know how large the image was displayed.
//

import SwiftUI

struct ChessCornerAdjustView: View {
    let image: UIImage
    /// Corners in image pixels, board order (a8, h8, h1, a1).
    @Binding var corners: [CGPoint]
    var onCancel: () -> Void
    var onConfirm: () -> Void

    @State private var dragging: Int?
    @State private var fingerInView: CGPoint = .zero

    /// Labels drawn beside each handle. Naming the corners is what makes
    /// board-order meaningful to a person — otherwise "drag the four
    /// corners" is ambiguous about rotation, and a board placed with a8 at
    /// the wrong end reads perfectly but 180 degrees out.
    private let handleNames = ["a8", "h8", "h1", "a1"]

    var body: some View {
        VStack(spacing: 0) {
            instructions
            GeometryReader { geometry in
                let layout = ImageLayout(image: image.size, container: geometry.size)
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()

                    quadOutline(layout)
                    handles(layout)

                    if let dragging {
                        Magnifier(image: image,
                                  focus: corners[dragging],
                                  layout: layout,
                                  fingerInView: fingerInView)
                    }
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(layout))
            }
            controls
        }
        .background(Color.black)
    }

    // MARK: - Pieces

    private var instructions: some View {
        Text("Drag each handle onto the matching corner of the board.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
    }

    private func quadOutline(_ layout: ImageLayout) -> some View {
        Path { path in
            let points = corners.map { layout.toView($0) }
            guard points.count == 4 else { return }
            path.move(to: points[0])
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
        .stroke(isUsable ? Color.accentColor : Color.red,
                style: StrokeStyle(lineWidth: 2, dash: isUsable ? [] : [6]))
        .allowsHitTesting(false)
    }

    private func handles(_ layout: ImageLayout) -> some View {
        ForEach(0..<4, id: \.self) { index in
            let point = layout.toView(corners[index])
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(dragging == index ? 0.9 : 0.55))
                    .frame(width: 22, height: 22)
                Circle()
                    .stroke(.white, lineWidth: 2)
                    .frame(width: 22, height: 22)
                Text(handleNames[index])
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .offset(y: -24)
                    .shadow(radius: 2)
            }
            .position(point)
            .allowsHitTesting(false)
        }
    }

    private var controls: some View {
        HStack {
            Button("Cancel", role: .cancel, action: onCancel)
            Spacer()
            if !isUsable {
                Label("Corners cross over", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Spacer()
            }
            Button("Use these corners", action: onConfirm)
                .buttonStyle(.borderedProminent)
                .disabled(!isUsable)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var isUsable: Bool {
        ChessBoardWarp.isUsableQuad(corners, minimumArea: 400)
    }

    // MARK: - Dragging

    private func dragGesture(_ layout: ImageLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                fingerInView = value.location
                if dragging == nil {
                    dragging = nearestHandle(to: value.location, layout: layout)
                }
                guard let index = dragging else { return }
                // Clamp into the image: a corner outside the picture is
                // one the warp would sample from nothing.
                corners[index] = layout.toImage(value.location, clamped: true)
            }
            .onEnded { _ in dragging = nil }
    }

    /// The handle a touch grabbed, or nil if the touch was nowhere near one.
    ///
    /// Picking the *nearest* handle unconditionally would mean a tap in
    /// the middle of the board yanks a corner across the screen, which is
    /// startling and easy to do by accident.
    private func nearestHandle(to point: CGPoint, layout: ImageLayout) -> Int? {
        var best: Int?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for index in 0..<4 {
            let handle = layout.toView(corners[index])
            let distance = hypot(handle.x - point.x, handle.y - point.y)
            if distance < bestDistance { bestDistance = distance; best = index }
        }
        return bestDistance <= 60 ? best : nil
    }
}

// MARK: - Layout

/// Maps between image pixels and the view's coordinate space.
///
/// `scaledToFit` letterboxes, so the mapping is a uniform scale plus an
/// offset — not a plain division by the view size, which is the mistake
/// that puts every corner slightly off on any image whose aspect ratio
/// differs from the frame's.
private struct ImageLayout {
    let scale: CGFloat
    let offset: CGSize
    let imageSize: CGSize

    init(image: CGSize, container: CGSize) {
        imageSize = image
        scale = min(container.width / max(image.width, 1),
                    container.height / max(image.height, 1))
        offset = CGSize(width: (container.width - image.width * scale) / 2,
                        height: (container.height - image.height * scale) / 2)
    }

    func toView(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale + offset.width,
                y: point.y * scale + offset.height)
    }

    func toImage(_ point: CGPoint, clamped: Bool = false) -> CGPoint {
        let x = (point.x - offset.width) / scale
        let y = (point.y - offset.height) / scale
        guard clamped else { return CGPoint(x: x, y: y) }
        return CGPoint(x: min(max(x, 0), imageSize.width),
                       y: min(max(y, 0), imageSize.height))
    }
}

// MARK: - Magnifier

/// A circular loupe showing the pixels under the dragged handle.
private struct Magnifier: View {
    let image: UIImage
    /// The point being placed, in image pixels.
    let focus: CGPoint
    let layout: ImageLayout
    /// Where the finger is, so the loupe can dodge it.
    let fingerInView: CGPoint

    private let diameter: CGFloat = 120
    private let zoom: CGFloat = 3.5

    var body: some View {
        let centre = layout.toView(focus)
        return ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(zoom, anchor: .topLeading)
                // Slide the zoomed image so the focus point sits in the
                // middle of the loupe.
                .offset(x: -centre.x * zoom + diameter / 2,
                        y: -centre.y * zoom + diameter / 2)
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())

            // Crosshair, so the exact target is unambiguous.
            Path { path in
                path.move(to: CGPoint(x: diameter / 2 - 10, y: diameter / 2))
                path.addLine(to: CGPoint(x: diameter / 2 + 10, y: diameter / 2))
                path.move(to: CGPoint(x: diameter / 2, y: diameter / 2 - 10))
                path.addLine(to: CGPoint(x: diameter / 2, y: diameter / 2 + 10))
            }
            .stroke(Color.accentColor, lineWidth: 1.5)
            .frame(width: diameter, height: diameter)

            Circle()
                .stroke(.white, lineWidth: 3)
                .frame(width: diameter, height: diameter)
        }
        .shadow(radius: 6)
        // Sit above the handle normally, below it when the handle is near
        // the top of the screen — otherwise the loupe is off-screen
        // exactly when the user is placing the far corners.
        .position(x: centre.x,
                  y: fingerInView.y < diameter * 1.2
                      ? centre.y + diameter * 0.9
                      : centre.y - diameter * 0.9)
        .allowsHitTesting(false)
    }
}
