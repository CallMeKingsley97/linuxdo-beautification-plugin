//
//  TopicRowView.swift
//

import SwiftUI

struct TopicRowView: View {
    let topic: TopicSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if topic.pinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if topic.closed {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(topic.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            HStack(spacing: 10) {
                Label("\(topic.replyCount)", systemImage: "bubble.right")
                Label("\(topic.views)", systemImage: "eye")
                if topic.likeCount > 0 {
                    Label("\(topic.likeCount)", systemImage: "heart")
                }
                Spacer(minLength: 4)
                if let user = topic.lastPosterUsername {
                    Text(user)
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)

            if !topic.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(topic.tags.prefix(4), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    if topic.tags.count > 4 {
                        Text("+\(topic.tags.count - 4)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
