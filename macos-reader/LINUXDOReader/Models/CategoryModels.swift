//
//  CategoryModels.swift
//

import Foundation

struct CategorySummary: Identifiable, Hashable {
    let id: Int
    let name: String
    let slug: String
    let color: String?
    let textColor: String?
    let description: String?
    let topicCount: Int
    let postCount: Int
    let position: Int
    let parentCategoryID: Int?

    var isSubcategory: Bool { parentCategoryID != nil }

    static func from(_ dto: CategoryJSON) -> CategorySummary {
        CategorySummary(
            id: dto.id,
            name: dto.name ?? "分类 \(dto.id)",
            slug: dto.slug ?? String(dto.id),
            color: dto.color,
            textColor: dto.textColor,
            description: dto.descriptionText ?? dto.description,
            topicCount: dto.topicCount ?? 0,
            postCount: dto.postCount ?? 0,
            position: dto.position ?? 0,
            parentCategoryID: dto.parentCategoryID
        )
    }
}

struct CategoriesJSON: Decodable {
    let categoryList: CategoryListJSON?
}

struct CategoryListJSON: Decodable {
    let categories: [CategoryJSON]?
}

struct CategoryJSON: Decodable {
    let id: Int
    let name: String?
    let color: String?
    let textColor: String?
    let slug: String?
    let topicCount: Int?
    let postCount: Int?
    let position: Int?
    let description: String?
    let descriptionText: String?
    let parentCategoryID: Int?
    let readRestricted: Bool?
}
