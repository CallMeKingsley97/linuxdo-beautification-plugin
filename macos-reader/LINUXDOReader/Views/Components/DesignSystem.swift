//
//  DesignSystem.swift
//  LINUX DO 阅读器的 macOS 原生视觉基线。
//

import AppKit
import Foundation
import SwiftUI

enum LDOTheme {
    static let sidebarMinWidth: CGFloat = 200
    static let sidebarIdealWidth: CGFloat = 228
    static let sidebarMaxWidth: CGFloat = 280

    static let listMinWidth: CGFloat = 300
    static let listIdealWidth: CGFloat = 360
    static let listMaxWidth: CGFloat = 440

    static let readerMaxWidth: CGFloat = 860
    static let settingsMaxWidth: CGFloat = 760
    static let compactCornerRadius: CGFloat = 8
    static let regularCornerRadius: CGFloat = 12
    static let highlightStripeWidth: CGFloat = 3
    static let highlightFillOpacity = 0.07

    static var windowBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static var contentBackground: Color {
        Color(nsColor: .textBackgroundColor)
    }

    static var subtleFill: Color {
        Color.primary.opacity(0.055)
    }

    static var separator: Color {
        Color(nsColor: .separatorColor)
    }
}

struct LDOAppMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(Color.accentColor.gradient)
            Image(systemName: "text.book.closed.fill")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.08), radius: 1, y: 1)
        .accessibilityHidden(true)
    }
}

struct LDOTag: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.11), in: Capsule())
    }
}

struct LDOStatusBadge: View {
    let text: String
    let color: Color
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.12), in: Capsule())
    }
}

struct LDOMetric: View {
    let value: Int
    let systemImage: String
    var help: String?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .imageScale(.small)
            Text(value.formatted())
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .help(help ?? "")
    }
}

struct LDOHighlightedRowBackground: View {
    let color: Color

    var body: some View {
        color.opacity(LDOTheme.highlightFillOpacity)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(color)
                    .frame(width: LDOTheme.highlightStripeWidth)
            }
            .accessibilityHidden(true)
    }
}

extension Date {
    var ldoRelativeDescription: String {
        let interval = abs(timeIntervalSinceNow)
        if interval < 45 { return "刚刚" }
        if interval < 7 * 24 * 60 * 60 {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return formatter.localizedString(for: self, relativeTo: Date())
        }
        return formatted(date: .abbreviated, time: .omitted)
    }
}

extension Color {
    /// 解析 Discourse 分类色（如 "0088CC" / "#0088CC"）。
    init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard raw.count == 6, let value = UInt64(raw, radix: 16) else { return nil }
        let red = Double((value & 0xFF0000) >> 16) / 255
        let green = Double((value & 0x00FF00) >> 8) / 255
        let blue = Double(value & 0x0000FF) / 255
        self.init(red: red, green: green, blue: blue)
    }

    var ldoHexRGB: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let red = Int((max(0, min(1, color.redComponent)) * 255).rounded())
        let green = Int((max(0, min(1, color.greenComponent)) * 255).rounded())
        let blue = Int((max(0, min(1, color.blueComponent)) * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
