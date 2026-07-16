//
//  PostCardView.swift
//

import SwiftUI
import AppKit

struct PostCardView: View {
    let post: PostItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AvatarView(template: post.avatarTemplate, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(post.name?.isEmpty == false ? post.name! : post.username)
                            .font(.subheadline.weight(.semibold))
                        Text("@\(post.username)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if post.acceptedAnswer {
                            Text("已采纳")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }
                    HStack(spacing: 8) {
                        Text("#\(post.postNumber)")
                        if let createdAt = post.createdAt {
                            Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        if let replyTo = post.replyToPostNumber {
                            Text("回复 #\(replyTo)")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }

            CookedHTMLView(html: post.cookedHTML)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

