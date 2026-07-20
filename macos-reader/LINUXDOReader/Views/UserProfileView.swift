//
//  UserProfileView.swift
//

import AppKit
import SwiftUI

struct UserProfileView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: UserProfileViewModel
    let route: UserProfileRoute

    @State private var contentSection: ProfileContentSection = .topics
    @State private var showsBadges = false
    @State private var showsSolved = false
    @State private var showsEndorsement = false

    var body: some View {
        Group {
            if let profile = viewModel.profile {
                profileContent(profile)
            } else if case .failed(let message) = viewModel.phase {
                failurePane(message)
            } else {
                LoadingPane(message: "正在加载用户资料…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LDOTheme.contentBackground)
        .navigationTitle(viewModel.profile?.name ?? route.displayName ?? route.username)
        .toolbar { profileToolbar }
        .task(id: route.id) {
            contentSection = .topics
            viewModel.load(username: route.username)
        }
        .sheet(isPresented: $showsBadges) {
            UserBadgesSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showsSolved) {
            UserSolvedSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showsEndorsement) {
            UserEndorsementSheet(viewModel: viewModel)
        }
        .alert(
            "操作未完成",
            isPresented: Binding(
                get: { viewModel.actionMessage != nil },
                set: { if !$0 { viewModel.clearActionMessage() } }
            )
        ) {
            Button("好") { viewModel.clearActionMessage() }
        } message: {
            Text(viewModel.actionMessage ?? "未知错误")
        }
    }

    private func failurePane(_ message: String) -> some View {
        ContentUnavailableView {
            Label("用户资料加载失败", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("重试") { viewModel.reload() }
            if !appState.siteSession.isLoggedIn {
                Button("登录与验证") { appState.openLogin() }
            }
        }
    }

    private func profileContent(_ profile: UserProfileDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                identitySection(profile)

                if let summary = viewModel.summary {
                    Divider()
                    statsSection(summary.stats)

                    if !summary.topBadges.isEmpty {
                        Divider()
                        badgesSection(summary.topBadges, totalCount: profile.badgeCount)
                    }

                    if hasInteractions(summary) {
                        Divider()
                        interactionsSection(summary)
                    }

                    Divider()
                    contentSectionView(summary)
                } else if case .loading = viewModel.phase {
                    Divider()
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在加载统计和动态…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: LDOTheme.readerMaxWidth, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
    }

    private func identitySection(_ profile: UserProfileDetail) -> some View {
        HStack(alignment: .top, spacing: 18) {
            AvatarView(
                template: profile.avatarTemplate ?? route.avatarTemplate,
                size: 82
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(profile.name)
                        .font(.title2.weight(.semibold))
                        .textSelection(.enabled)

                    if let statusEmoji = profile.statusEmoji {
                        ProfileStatusView(shortcode: statusEmoji)
                    }
                }

                Text("@\(profile.username)")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack(spacing: 6) {
                    if let title = profile.title {
                        LDOStatusBadge(text: title, color: .accentColor)
                    } else if let level = profile.trustLevelName {
                        LDOStatusBadge(text: level, color: .secondary)
                    }
                    if let trustLevel = profile.trustLevel {
                        LDOTag(text: "Lv\(trustLevel)")
                    }
                }

                if let bio = profile.bio {
                    Text(bio)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                profileMetadata(profile)
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 8) {
                if profile.canFollow {
                    if profile.isFollowed {
                        followButton(profile)
                            .buttonStyle(.bordered)
                    } else {
                        followButton(profile)
                            .buttonStyle(.borderedProminent)
                    }
                }

                if profile.endorsementAvailable {
                    Button {
                        showsEndorsement = true
                    } label: {
                        Label(
                            profile.endorsedCategoryIDs.isEmpty
                                ? "认可"
                                : "已认可 · \(profile.endorsedCategoryIDs.count)",
                            systemImage: "checkmark.seal"
                        )
                    }
                    .buttonStyle(.bordered)
                    .help("在相关类别中认可此用户")
                }
            }
            .controlSize(.regular)
        }
    }

    private func followButton(_ profile: UserProfileDetail) -> some View {
        Button {
            viewModel.toggleFollow()
        } label: {
            if viewModel.isChangingFollow {
                ProgressView().controlSize(.small)
            } else {
                Label(
                    profile.isFollowed ? "已关注" : "关注",
                    systemImage: profile.isFollowed ? "person.badge.checkmark" : "person.badge.plus"
                )
            }
        }
        .disabled(viewModel.isChangingFollow)
        .help(profile.isFollowed ? "取消关注此用户" : "关注此用户")
    }

    private func profileMetadata(_ profile: UserProfileDetail) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                profileMetadataItems(profile)
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 6) {
                profileMetadataItems(profile)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func profileMetadataItems(_ profile: UserProfileDetail) -> some View {
            if let createdAt = profile.createdAt {
                Label("加入于 \(createdAt.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar")
            }
            if let lastPostedAt = profile.lastPostedAt {
                Label("最近发帖 \(lastPostedAt.ldoRelativeDescription)", systemImage: "clock")
            }
            if profile.profileViewCount > 0 {
                Label(profile.profileViewCount.formatted(), systemImage: "eye")
                    .help("资料页浏览量")
            }
            if profile.followerCount > 0 || profile.followingCount > 0 {
                Text("\(profile.followerCount.formatted()) 位关注者 · 关注 \(profile.followingCount.formatted()) 人")
            }
    }

    private func statsSection(_ stats: UserProfileStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("社区统计")
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ProfileMetricView(title: "访问天数", value: stats.daysVisited.formatted(), systemImage: "calendar.badge.clock")
                ProfileMetricView(title: "阅读时长", value: Self.readingTime(stats.timeReadSeconds), systemImage: "book.pages")
                ProfileMetricView(title: "浏览话题", value: stats.topicsEntered.formatted(), systemImage: "rectangle.stack")
                ProfileMetricView(title: "发布话题", value: stats.topicCount.formatted(), systemImage: "text.bubble")
                ProfileMetricView(title: "回复", value: stats.postCount.formatted(), systemImage: "bubble.left.and.bubble.right")
                ProfileMetricView(title: "获赞", value: stats.likesReceived.formatted(), systemImage: "heart.fill", tint: .red)
                ProfileMetricView(title: "送出赞", value: stats.likesGiven.formatted(), systemImage: "hand.thumbsup")
                if let solvedCount = stats.solvedCount {
                    Button {
                        showsSolved = true
                    } label: {
                        ProfileMetricView(title: "解决方案", value: solvedCount.formatted(), systemImage: "checkmark.seal.fill", tint: .green)
                    }
                    .buttonStyle(.plain)
                    .disabled(solvedCount == 0)
                    .help("查看被采纳的回复")
                }
            }
        }
    }

    private func badgesSection(_ badges: [UserBadgeItem], totalCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("徽章")
                    .font(.headline)
                if totalCount > 0 {
                    Text(totalCount.formatted())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Button("查看全部") { showsBadges = true }
                    .buttonStyle(.borderless)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    ForEach(badges) { badge in
                        BadgeSummaryView(badge: badge)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func interactionsSection(_ summary: UserProfileSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("互动圈")
                .font(.headline)
            InteractionRow(
                title: "经常回复",
                interactions: summary.mostRepliedToUsers,
                onOpenUser: openInteractionUser
            )
            InteractionRow(
                title: "经常点赞",
                interactions: summary.mostLikedUsers,
                onOpenUser: openInteractionUser
            )
            InteractionRow(
                title: "常获其赞",
                interactions: summary.mostLikedByUsers,
                onOpenUser: openInteractionUser
            )
        }
    }

    private func contentSectionView(_ summary: UserProfileSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("内容", selection: $contentSection) {
                ForEach(ProfileContentSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 460)

            switch contentSection {
            case .topics:
                topicRows(summary.topTopics)
            case .replies:
                replyRows(summary.topReplies)
            case .activity:
                activityRows
            }
        }
    }

    @ViewBuilder
    private func topicRows(_ topics: [UserTopTopic]) -> some View {
        if topics.isEmpty {
            ProfileEmptyRow(text: "暂无热门话题", systemImage: "text.bubble")
        } else {
            VStack(spacing: 0) {
                ForEach(topics) { topic in
                    ProfileLinkRow(
                        title: topic.title,
                        date: topic.createdAt,
                        metric: topic.likeCount,
                        metricImage: "heart"
                    ) {
                        appState.openTopicFromProfile(id: topic.topicID)
                    }
                    if topic.id != topics.last?.id { Divider() }
                }
            }
        }
    }

    @ViewBuilder
    private func replyRows(_ replies: [UserTopReply]) -> some View {
        if replies.isEmpty {
            ProfileEmptyRow(text: "暂无热门回复", systemImage: "bubble.left")
        } else {
            VStack(spacing: 0) {
                ForEach(replies) { reply in
                    ProfileLinkRow(
                        title: reply.topicTitle,
                        subtitle: "#\(reply.postNumber)",
                        date: reply.createdAt,
                        metric: reply.likeCount,
                        metricImage: "heart"
                    ) {
                        appState.openTopicFromProfile(id: reply.topicID)
                    }
                    if reply.id != replies.last?.id { Divider() }
                }
            }
        }
    }

    private var activityRows: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("动态类型", selection: Binding(
                get: { viewModel.activityFilter },
                set: viewModel.selectActivityFilter
            )) {
                ForEach(UserActivityFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            if viewModel.activityItems.isEmpty, viewModel.isLoadingActivity {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在加载动态…").foregroundStyle(.secondary)
                }
            } else if viewModel.activityItems.isEmpty {
                ProfileEmptyRow(text: "暂无相关动态", systemImage: "clock.arrow.circlepath")
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.activityItems) { item in
                        ActivityRow(item: item) {
                            appState.openTopicFromProfile(id: item.topicID)
                        }
                        if item.id != viewModel.activityItems.last?.id { Divider() }
                    }
                }

                if viewModel.hasMoreActivity || viewModel.isLoadingActivity {
                    Button(action: viewModel.loadMoreActivity) {
                        HStack(spacing: 6) {
                            if viewModel.isLoadingActivity {
                                ProgressView().controlSize(.small)
                            }
                            Text(viewModel.isLoadingActivity ? "正在加载…" : "加载更多")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isLoadingActivity)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var profileToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: appState.closeUserProfile) {
                Label("返回", systemImage: "chevron.backward")
            }
            .help("返回上一页")

            Button(action: viewModel.reload) {
                if case .loading = viewModel.phase {
                    ProgressView().controlSize(.small)
                } else {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }

            Button {
                NSWorkspace.shared.open(Endpoints.userPage(username: route.username))
            } label: {
                Label("网页版资料", systemImage: "globe")
            }
            .help("在浏览器中打开用户资料")
        }
    }

    private func openInteractionUser(_ user: UserSummary) {
        appState.openUserProfile(
            username: user.username,
            displayName: user.name,
            avatarTemplate: user.avatarTemplate
        )
    }

    private func hasInteractions(_ summary: UserProfileSummary) -> Bool {
        !summary.mostRepliedToUsers.isEmpty
            || !summary.mostLikedUsers.isEmpty
            || !summary.mostLikedByUsers.isEmpty
    }

    private static func readingTime(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        if hours >= 24 {
            return "\(hours / 24) 天 \(hours % 24) 小时"
        }
        if hours > 0 { return "\(hours) 小时" }
        return "\(max(0, seconds / 60)) 分钟"
    }
}

private enum ProfileContentSection: String, CaseIterable, Identifiable {
    case topics
    case replies
    case activity

    var id: String { rawValue }
    var title: String {
        switch self {
        case .topics: return "热门话题"
        case .replies: return "热门回复"
        case .activity: return "最近动态"
        }
    }
}

private struct ProfileStatusView: View {
    let shortcode: String

    var body: some View {
        Group {
            if let emoji = Self.nativeEmoji[shortcode] {
                Text(emoji)
            } else {
                Image(systemName: "face.smiling")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .frame(minWidth: 22, minHeight: 22)
        .background(LDOTheme.subtleFill, in: Capsule())
        .help(":\(shortcode):")
        .accessibilityLabel("用户状态：\(shortcode)")
    }

    private static let nativeEmoji: [String: String] = [
        "speech_balloon": "💬",
        "crown": "👑",
        "nerd_face": "🤓",
        "sunglasses": "😎",
        "thinking": "🤔",
        "smiley": "😃",
        "heart": "❤️",
        "fire": "🔥",
        "star": "⭐️",
        "rocket": "🚀",
        "coffee": "☕️",
        "computer": "💻",
        "seedling": "🌱",
        "lollipop": "🍭",
    ]
}

private struct ProfileMetricView: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

private struct BadgeSummaryView: View {
    let badge: UserBadgeItem

    var body: some View {
        VStack(spacing: 6) {
            BadgeIconView(badge: badge, size: 34)
            Text(badge.name)
                .font(.caption)
                .lineLimit(1)
            if badge.grantCount > 1 {
                Text("×\(badge.grantCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 88)
        .help(badge.description ?? badge.name)
    }
}

private struct BadgeIconView: View {
    let badge: UserBadgeItem
    let size: CGFloat

    var body: some View {
        Group {
            if let imageURL = badge.imageURL,
               let url = Endpoints.avatarURL(template: imageURL, size: Int(size * 2)) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    symbol
                }
            } else {
                symbol
            }
        }
        .frame(width: size, height: size)
    }

    private var symbol: some View {
        Image(systemName: badge.badgeTypeID == 1 ? "medal.fill" : "seal.fill")
            .font(.system(size: size * 0.72))
            .foregroundStyle(badgeColor)
    }

    private var badgeColor: Color {
        switch badge.badgeTypeID {
        case 1: return .yellow
        case 2: return .secondary
        default: return .orange
        }
    }
}

private struct InteractionRow: View {
    let title: String
    let interactions: [UserInteraction]
    let onOpenUser: (UserSummary) -> Void

    var body: some View {
        if !interactions.isEmpty {
            HStack(spacing: 12) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 76, alignment: .leading)
                ForEach(interactions) { interaction in
                    Button {
                        onOpenUser(interaction.user)
                    } label: {
                        VStack(spacing: 3) {
                            AvatarView(template: interaction.user.avatarTemplate, size: 34)
                            Text(interaction.count.formatted())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .buttonStyle(.plain)
                    .help("打开 @\(interaction.user.username) 的资料")
                }
                Spacer()
            }
        }
    }
}

private struct ProfileLinkRow: View {
    let title: String
    var subtitle: String?
    var date: Date?
    var metric: Int
    var metricImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        if let subtitle {
                            Text(subtitle)
                        }
                        if let date {
                            Text(date.ldoRelativeDescription)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if metric > 0 {
                    LDOMetric(value: metric, systemImage: metricImage)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

private struct ActivityRow: View {
    let item: UserActivityItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(template: item.author?.avatarTemplate, size: 32)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Label(actionTitle, systemImage: actionImage)
                        if let createdAt = item.createdAt {
                            Text(createdAt.ldoRelativeDescription)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(item.title)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if !item.excerpt.isEmpty {
                        Text(item.excerpt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private var actionTitle: String {
        switch item.actionType {
        case 4: return "发布话题"
        case 5: return "回复"
        case 1: return "点赞"
        default: return "动态"
        }
    }

    private var actionImage: String {
        switch item.actionType {
        case 4: return "text.bubble"
        case 5: return "bubble.left"
        case 1: return "heart"
        default: return "clock"
        }
    }
}

private struct ProfileEmptyRow: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}

private struct UserBadgesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: UserProfileViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("全部徽章").font(.headline)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()

            if viewModel.isLoadingBadges, viewModel.badgeGroups.isEmpty {
                LoadingPane(message: "正在加载徽章…")
            } else if let error = viewModel.badgesError, viewModel.badgeGroups.isEmpty {
                ContentUnavailableView("徽章加载失败", systemImage: "medal", description: Text(error))
            } else {
                List {
                    ForEach(viewModel.badgeGroups) { group in
                        Section(group.name) {
                            ForEach(group.badges) { badge in
                                HStack(spacing: 12) {
                                    BadgeIconView(badge: badge, size: 30)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(badge.name)
                                        if let description = badge.description {
                                            Text(description)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                    if badge.grantCount > 1 {
                                        Text("×\(badge.grantCount)")
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 560, height: 620)
        .task { viewModel.loadBadges() }
    }
}

private struct UserSolvedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: UserProfileViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("被采纳的解决方案").font(.headline)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()

            if viewModel.isLoadingSolved, viewModel.solvedItems.isEmpty {
                LoadingPane(message: "正在加载解决方案…")
            } else if let error = viewModel.solvedError, viewModel.solvedItems.isEmpty {
                ContentUnavailableView("加载失败", systemImage: "checkmark.seal", description: Text(error))
            } else {
                List {
                    ForEach(viewModel.solvedItems) { item in
                        Button {
                            dismiss()
                            appState.openTopicFromProfile(id: item.topicID)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.topicTitle).foregroundStyle(.primary)
                                if !item.excerpt.isEmpty {
                                    Text(item.excerpt)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                                HStack {
                                    Text("#\(item.postNumber)")
                                    if let date = item.createdAt { Text(date.ldoRelativeDescription) }
                                }
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                    }

                    if viewModel.hasMoreSolved || viewModel.isLoadingSolved {
                        Button(viewModel.isLoadingSolved ? "正在加载…" : "加载更多") {
                            viewModel.loadSolved(reset: false)
                        }
                        .disabled(viewModel.isLoadingSolved)
                    }
                }
            }
        }
        .frame(width: 620, height: 620)
        .task { viewModel.loadSolved(reset: true) }
    }
}

private struct UserEndorsementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: UserProfileViewModel
    @State private var selectedCategoryIDs: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("认可用户").font(.headline)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
            }

            if viewModel.isLoadingEndorsements {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在加载可认可类别…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else if viewModel.endorsableCategories.isEmpty {
                ContentUnavailableView("暂无可认可类别", systemImage: "checkmark.seal")
                    .frame(minHeight: 160)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.endorsableCategories) { category in
                        let reachedLimit = selectedCategoryIDs.count >= viewModel.remainingEndorsements
                        Toggle(isOn: Binding(
                            get: { selectedCategoryIDs.contains(category.id) },
                            set: { selected in
                                if selected { selectedCategoryIDs.insert(category.id) }
                                else { selectedCategoryIDs.remove(category.id) }
                            }
                        )) {
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(Color(hex: category.color ?? "") ?? .secondary)
                                    .frame(width: 7, height: 7)
                                Text(category.name)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(reachedLimit && !selectedCategoryIDs.contains(category.id))
                    }
                }

                Divider()

                HStack {
                    Text("今天还可认可 \(viewModel.remainingEndorsements) 个类别 · 已选择 \(selectedCategoryIDs.count) 个")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("认可") {
                        Task {
                            if await viewModel.endorse(categoryIDs: selectedCategoryIDs) {
                                dismiss()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        selectedCategoryIDs.isEmpty
                            || selectedCategoryIDs.count > viewModel.remainingEndorsements
                            || viewModel.remainingEndorsements == 0
                            || viewModel.isSubmittingEndorsement
                    )
                }
            }
        }
        .padding(20)
        .frame(width: 440)
        .task { viewModel.loadEndorsableCategories() }
    }
}
