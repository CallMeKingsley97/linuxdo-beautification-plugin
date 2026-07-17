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

    /// 站点公开分类 URL。RSS 没有分类元数据接口，因此只保留已核验的顶层目录。
    static let rssCatalog: [CategorySummary] = [
        rss(id: 4, name: "开发调优", slug: "develop", position: 0),
        rss(id: 14, name: "资源荟萃", slug: "resource", position: 1),
        rss(id: 42, name: "文档共建", slug: "wiki", position: 2),
        rss(id: 27, name: "非我莫属", slug: "job", position: 3),
        rss(id: 32, name: "读书成诗", slug: "reading", position: 4),
        rss(id: 34, name: "前沿快讯", slug: "news", position: 5),
        rss(id: 36, name: "福利羊毛", slug: "welfare", position: 6),
        rss(id: 11, name: "搞七捻三", slug: "gossip", position: 7),
        rss(id: 2, name: "运营反馈", slug: "feedback", position: 8),
    ]

    private static func rss(id: Int, name: String, slug: String, position: Int) -> CategorySummary {
        CategorySummary(
            id: id,
            name: name,
            slug: slug,
            color: nil,
            textColor: nil,
            description: nil,
            topicCount: 0,
            postCount: 0,
            position: position,
            parentCategoryID: nil
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
