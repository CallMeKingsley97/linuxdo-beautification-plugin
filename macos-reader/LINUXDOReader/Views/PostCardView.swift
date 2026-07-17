//
//  PostCardView.swift
//

import SwiftUI
import AppKit

struct PostCardView: View {
    let post: PostItem
    let onOpenTopic: ((Int) -> Void)?
    let onReply: ((PostItem) -> Void)?
    @State private var isHovering = false

    init(
        post: PostItem,
        onOpenTopic: ((Int) -> Void)? = nil,
        onReply: ((PostItem) -> Void)? = nil
    ) {
        self.post = post
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
                        .opacity(isHovering ? 1 : 0.55)
                        .help("回复 #\(post.postNumber)")
                    }
                }

                CookedHTMLView(html: post.cookedHTML, onOpenTopic: onOpenTopic)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var rowBackground: Color {
        if post.acceptedAnswer { return Color.green.opacity(0.055) }
        if isHovering { return Color.primary.opacity(0.025) }
        return .clear
    }
}
