//
//  TopicRowView.swift
//

import SwiftUI

struct TopicRowView: View {
    let topic: TopicSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
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
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 6)
                if let activityDate {
                    Text(activityDate.ldoRelativeDescription)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            HStack(spacing: 12) {
                LDOMetric(value: topic.replyCount, systemImage: "bubble.right", help: "回复")
                if topic.views > 0 {
                    LDOMetric(value: topic.views, systemImage: "eye", help: "浏览")
                }
                if topic.likeCount > 0 {
                    LDOMetric(value: topic.likeCount, systemImage: "heart", help: "赞")
                }
                Spacer(minLength: 4)
                if let user = topic.lastPosterUsername {
                    Label(user, systemImage: "person.crop.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                }
            }

            if !topic.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(topic.tags.prefix(3), id: \.self) { tag in
                        LDOTag(text: tag)
                    }
                    if topic.tags.count > 3 {
                        Text("+\(topic.tags.count - 3)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var activityDate: Date? {
        topic.bumpedAt ?? topic.lastPostedAt ?? topic.createdAt
    }
}
