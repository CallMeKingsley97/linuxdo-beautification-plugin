//
//  PostCardView.swift
//

import SwiftUI
import AppKit

struct PostCardView: View {
    let post: PostItem
    let isFollowedAuthor: Bool
    let followedColor: Color
    let onOpenTopic: ((Int) -> Void)?
    let onReply: ((PostItem) -> Void)?

    init(
        post: PostItem,
        isFollowedAuthor: Bool = false,
        followedColor: Color = .green,
        onOpenTopic: ((Int) -> Void)? = nil,
        onReply: ((PostItem) -> Void)? = nil
    ) {
        self.post = post
        self.isFollowedAuthor = isFollowedAuthor
        self.followedColor = followedColor
        self.onOpenTopic = onOpenTopic
        self.onReply = onReply
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(template: post.avatarTemplate, size: 36)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(post.name?.isEmpty == false ? post.name! : post.username)
                                .font(.subheadline.weight(.semibold))
                            if let name = post.name, !name.isEmpty, name != post.username {
                                Text("@\(post.username)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if post.acceptedAnswer {
                                LDOStatusBadge(text: "已采纳", color: .green, systemImage: "checkmark")
                            }
                            if isFollowedAuthor {
                                LDOStatusBadge(
                                    text: "已关注",
                                    color: followedColor,
                                    systemImage: "person.badge.checkmark"
                                )
                            }
                        }

                        HStack(spacing: 7) {
                            Text("#\(post.postNumber)")
                                .monospacedDigit()
                            if let createdAt = post.createdAt {
                                Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                            }
                            if let replyTo = post.replyToPostNumber {
                                Label("回复 #\(replyTo)", systemImage: "arrowshape.turn.up.left")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)
                    if let onReply {
                        Button {
                            onReply(post)
                        } label: {
                            Label("回复", systemImage: "arrowshape.turn.up.left")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .opacity(0.72)
                        .help("回复 #\(post.postNumber)")
                    }
                }

                CookedHTMLView(
                    contentID: post.id,
                    html: post.cookedHTML,
                    onOpenTopic: onOpenTopic
                )
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background {
            ZStack {
                rowBackground
                if isFollowedAuthor {
                    LDOHighlightedRowBackground(color: followedColor)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var rowBackground: Color {
        if post.acceptedAnswer { return Color.green.opacity(0.055) }
        return .clear
    }
}
