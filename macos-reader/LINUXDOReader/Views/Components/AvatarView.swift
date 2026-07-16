//
//  AvatarView.swift
//

import SwiftUI

struct AvatarView: View {
    let template: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let template,
               let url = Endpoints.avatarURL(template: template, size: Int(size * 2)) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.42))
                .foregroundStyle(.secondary)
        }
    }
}
