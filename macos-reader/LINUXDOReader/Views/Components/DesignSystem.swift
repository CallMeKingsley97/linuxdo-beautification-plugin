//
//  DesignSystem.swift
//  LINUX DO 阅读器的 macOS 原生视觉基线。
//

import AppKit
import Foundation
import SwiftUI

enum LDOIcon {
    static let latest = "sparkles"
    static let popular = "flame.fill"
    static let account = "person.crop.circle.badge.checkmark"
    static let login = "person.crop.circle.badge.plus"
    static let personFill = "person.fill"
    static let settings = "gearshape.fill"
    static let notifications = "bell.fill"
    static let refresh = "arrow.triangle.2.circlepath"
    static let refreshCategories = "arrow.triangle.2.circlepath"
    static let connected = "checkmark.circle.fill"
    static let checkmark = "checkmark"
    static let checkmarkSeal = "checkmark.seal"
    static let solved = "checkmark.seal.fill"
    static let error = "wifi.exclamationmark"
    static let warning = "exclamationmark.triangle"
    static let info = "info.circle"
    static let close = "xmark"
    static let pinned = "pin.fill"
    static let closed = "lock.fill"
    static let replies = "bubble.left"
    static let views = "eye"
    static let person = "person"
    static let search = "text.magnifyingglass"
    static let followed = "person.badge.checkmark"
    static let needsRefresh = "arrow.down.circle"
    static let updated = "clock"
    static let markRead = "checkmark.circle"
    static let sidebar = "sidebar.right"
    static let chevronBackward = "chevron.backward"
    static let chevronForward = "chevron.forward"
    static let home = "house"
    static let secure = "lock.fill"
    static let web = "safari"
    static let compose = "square.and.pencil"
    static let reply = "arrowshape.turn.up.left"
    static let heart = "heart"
    static let heartFill = "heart.fill"
    static let copyLink = "link"
    static let more = "ellipsis.circle"
    static let ellipsis = "ellipsis"
    static let boost = "paperplane"
    static let agree = "hand.thumbsup"
    static let bookmark = "bookmark"
    static let plus = "plus"
    static let pencil = "pencil"
    static let flag = "flag"
    static let flagDisabled = "flag.slash"
    static let rocket = "rocket"
    static let ellipsisCircle = "ellipsis.circle"
    static let bellBadge = "bell.badge"
    static let calendar = "calendar"
    static let readingTime = "book.pages"
    static let topics = "rectangle.stack"
    static let textBubble = "text.bubble"
    static let conversation = "bubble.left.and.bubble.right"
    static let chevronRight = "chevron.right"
    static let questionmark = "questionmark"
    static let medal = "medal"
    static let faceSmiling = "face.smiling"

    /// 侧边栏分类图标。优先按站点 slug 识别，未收录的分类退回通用符号。
    static func category(_ slug: String) -> String {
        switch slug {
        case "develop": return "hammer.fill"
        case "resource": return "square.stack.3d.up.fill"
        case "wiki": return "text.book.closed.fill"
        case "job": return "briefcase.fill"
        case "reading": return "book.fill"
        case "news": return "newspaper.fill"
        case "welfare": return "gift.fill"
        case "gossip": return "bubble.left.and.bubble.right.fill"
        case "feedback": return "megaphone.fill"
        default: return "square.grid.2x2.fill"
        }
    }
}

enum LDOTheme {
    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing24: CGFloat = 24

    static let sidebarMinWidth: CGFloat = 200
    static let sidebarIdealWidth: CGFloat = 228
    static let sidebarMaxWidth: CGFloat = 280

    static let listMinWidth: CGFloat = 300
    static let listIdealWidth: CGFloat = 360
    static let listMaxWidth: CGFloat = 440

    static let readerMaxWidth: CGFloat = 860
    static let settingsMaxWidth: CGFloat = 700
    static let compactCornerRadius: CGFloat = 8
    static let regularCornerRadius: CGFloat = 12
    static let highlightStripeWidth: CGFloat = 2
    static let highlightFillOpacity = 0.065
    static let listRowVerticalInset: CGFloat = 10
    static let listStatusBarHeight: CGFloat = 28
    static let detailPagingBarHeight: CGFloat = 42
    static let bannerMinHeight: CGFloat = 34

    static var acceptedAnswerFill: Color {
        Color.green.opacity(highlightFillOpacity)
    }

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
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.36, blue: 0.71),
                            Color(red: 0.07, green: 0.16, blue: 0.40)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            LDOPenguinMark()
                .fill(.white)
                .frame(width: size * 0.62, height: size * 0.62)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.1), radius: 1, y: 1)
        .accessibilityHidden(true)
    }
}

/// Dock 图标里那只企鹅的矢量版，侧边栏底部标记与之一致。
struct LDOPenguinMark: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.maxY - y * h)
        }

        var path = Path()
        path.move(to: p(0.50, 0.98))
        path.addCurve(to: p(0.16, 0.72), control1: p(0.30, 0.98), control2: p(0.16, 0.88))
        path.addCurve(to: p(0.08, 0.42), control1: p(0.08, 0.62), control2: p(0.05, 0.52))
        path.addCurve(to: p(0.26, 0.10), control1: p(0.11, 0.26), control2: p(0.17, 0.14))
        path.addQuadCurve(to: p(0.50, 0.04), control: p(0.36, 0.02))
        path.addQuadCurve(to: p(0.74, 0.10), control: p(0.64, 0.02))
        path.addCurve(to: p(0.92, 0.42), control1: p(0.83, 0.14), control2: p(0.95, 0.26))
        path.addCurve(to: p(0.84, 0.72), control1: p(0.95, 0.52), control2: p(0.92, 0.62))
        path.addCurve(to: p(0.50, 0.98), control1: p(0.84, 0.88), control2: p(0.70, 0.98))
        path.closeSubpath()

        path.addEllipse(in: CGRect(x: rect.minX + 0.30 * w, y: rect.maxY - 0.50 * h, width: 0.40 * w, height: 0.34 * h))
        path.addEllipse(in: CGRect(x: rect.minX + 0.30 * w, y: rect.maxY - 0.90 * h, width: 0.40 * w, height: 0.30 * h))
        return path
    }
}

/// 表单与正文中的说明文字：统一字号、次级色、左对齐与自动换行。
struct LDOFooterText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 轻量内联提示条：左侧状态说明，右侧单一操作；不打断正文，也不使用投影。
struct LDOInlineBanner<Action: View>: View {
    let message: String
    let systemImage: String
    var isWarning = false
    var horizontalPadding: CGFloat = LDOTheme.spacing16
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack(spacing: LDOTheme.spacing8) {
            Label(message, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(
                    isWarning ? AnyShapeStyle(Color.orange) : AnyShapeStyle(Color.secondary)
                )
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: LDOTheme.spacing12)

            action()
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 6)
        .frame(minHeight: LDOTheme.bannerMinHeight)
        .background(
            isWarning ? AnyShapeStyle(Color.orange.opacity(0.08)) : AnyShapeStyle(.bar)
        )
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// 提示条右侧的关闭按钮：图标 + 帮助文本 + 无障碍标签保持一致。
struct LDOBannerDismissButton: View {
    var help = "关闭提示"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: LDOIcon.close)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// 分类、标签与规则的颜色指示点：统一尺寸、描边与无障碍处理。
/// 分类在侧边栏里的固定色。站点没下发颜色时也要能一眼区分，所以按 slug 兜底。
enum LDOCategoryPalette {
    static func color(slug: String, fallbackHex: String?) -> Color {
        if let tint = tint(for: slug) {
            return tint
        }
        if let fallbackHex, let parsed = Color(hex: fallbackHex) {
            return parsed
        }
        return .secondary
    }

    private static func tint(for slug: String) -> Color? {
        switch slug {
        case "develop": return Color(red: 0.20, green: 0.46, blue: 0.90)
        case "resource": return Color(red: 0.13, green: 0.62, blue: 0.55)
        case "wiki": return Color(red: 0.36, green: 0.42, blue: 0.78)
        case "job": return Color(red: 0.86, green: 0.48, blue: 0.16)
        case "reading": return Color(red: 0.55, green: 0.36, blue: 0.78)
        case "news": return Color(red: 0.86, green: 0.27, blue: 0.30)
        case "welfare": return Color(red: 0.86, green: 0.32, blue: 0.52)
        case "gossip": return Color(red: 0.18, green: 0.62, blue: 0.42)
        case "feedback": return Color(red: 0.30, green: 0.55, blue: 0.82)
        default: return nil
        }
    }
}

struct LDOCategoryDot: View {
    let color: Color
    var size: CGFloat = 7
    var isOutlined = false
    var accessibilityText: String?

    var body: some View {
        let dot = Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                if isOutlined {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
                }
            }

        if let accessibilityText {
            dot
                .accessibilityElement()
                .accessibilityLabel(accessibilityText)
        } else {
            dot.accessibilityHidden(true)
        }
    }
}

/// 列表底部的分页加载按钮：统一文案、尺寸与加载态，避免各处自造实现。
struct LDOLoadMoreButton: View {
    var title = "加载更多"
    var loadingTitle = "正在加载…"
    let isLoading: Bool
    var controlSize: ControlSize = .regular
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(isLoading ? loadingTitle : title)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(controlSize)
        .disabled(isLoading)
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
                    .font(.caption2.weight(.medium))
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
                .font(.caption.weight(.medium))
            Text(value.formatted())
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .help(help ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(help ?? "指标")：\(value.formatted())")
    }
}

struct LDOHighlightedRowBackground: View {
    let color: Color

    var body: some View {
        LinearGradient(
            colors: [
                color.opacity(LDOTheme.highlightFillOpacity),
                color.opacity(LDOTheme.highlightFillOpacity * 0.28),
                .clear,
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(color)
                    .frame(width: LDOTheme.highlightStripeWidth, height: 28)
                    .padding(.leading, 1)
            }
            .accessibilityHidden(true)
    }
}

struct LDOHighlightIndicator: View {
    let text: String
    let color: Color
    let systemImage: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .font(.caption2.weight(.medium))
        .lineLimit(1)
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
