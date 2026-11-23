//
//  QrRiskView.swift
//  Scan
//
//  The safety banner shown above the smart actions, and its expandable
//  findings. Deliberately quiet on the 99% of codes that are ordinary: a
//  shield row only appears when something actually fired, so the badge keeps
//  its meaning instead of becoming wallpaper.
//
//  The banner is one `Form` row holding two buttons (the header and "open
//  anyway"), so both carry an explicit borderless/plain style: with the
//  default style a tap anywhere in the row would fire them all.
//

import SwiftUI
import UIKit

struct QrRiskView: View {
    let report: QrRiskReport
    /// A dangerous code's primary action is gated behind an explicit tap;
    /// the parent tells us whether the user has already confirmed.
    var confirmedOpen: Bool = false
    var onConfirmOpen: (() -> Void)?

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if expanded {
                ForEach(report.findings) { finding in
                    FindingRow(finding: finding)
                }
                if report.isBlocking, let onConfirmOpen, !confirmedOpen {
                    Button(role: .destructive) {
                        onConfirmOpen()
                    } label: {
                        Label("I understand — open anyway", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(10)
        .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(border, lineWidth: 1)
        )
    }

    private var header: some View {
        Button {
            withAnimation(.snappy) { expanded.toggle() }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: report.level.symbol)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.level.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(expanded
                         ? "Hide details"
                         : "\(report.headline) · \(report.findings.count == 1 ? "1 detail" : "\(report.findings.count) details")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(expanded ? "Hides the details" : "Shows what the safety check found")
    }

    private var tint: Color {
        switch report.level {
        case .safe:    return .green
        case .caution: return .orange
        case .danger:  return .red
        }
    }

    private var background: Color {
        switch report.level {
        case .safe:    return .green.opacity(0.08)
        case .caution: return .orange.opacity(0.10)
        case .danger:  return .red.opacity(0.12)
        }
    }

    private var border: Color {
        switch report.level {
        case .safe:    return .green.opacity(0.25)
        case .caution: return .orange.opacity(0.35)
        case .danger:  return .red.opacity(0.45)
        }
    }
}

private struct FindingRow: View {
    let finding: QrRiskFinding

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(colour)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.title)
                    .font(.footnote.weight(.semibold))
                Text(finding.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 2)
    }

    private var symbol: String {
        switch finding.severity {
        case .note:   return "info.circle"
        case .caution: return "exclamationmark.triangle.fill"
        case .danger: return "xmark.octagon.fill"
        }
    }

    private var colour: Color {
        switch finding.severity {
        case .note:   return .secondary
        case .caution: return .orange
        case .danger: return .red
        }
    }
}
