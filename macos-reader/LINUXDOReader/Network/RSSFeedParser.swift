//
//  RSSFeedParser.swift
//  解析 Discourse 官方 RSS 2.0，只读取站点公开的只读数据。
//

import Foundation

struct RSSFeed {
    let title: String
    let description: String
    let category: String?
    let items: [RSSFeedItem]
}

struct RSSFeedItem {
    let title: String
    let creator: String
    let category: String?
    let html: String
    let link: String
    let guid: String
    let publishedAt: Date?
    let pinned: Bool
    let closed: Bool
    let archived: Bool
}

enum RSSFeedParser {
    static func parse(_ data: Data) throws -> RSSFeed {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            let message = delegate.parseError?.localizedDescription
                ?? parser.parserError?.localizedDescription
                ?? "无效的 RSS 数据"
            throw LDOError.decoding(message)
        }
        return delegate.feed
    }
}

private final class ParserDelegate: NSObject, XMLParserDelegate {
    private struct ItemBuilder {
        var title = ""
        var creator = ""
        var category: String?
        var html = ""
        var link = ""
        var guid = ""
        var publishedAt: Date?
        var pinned = false
        var closed = false
        var archived = false

        var item: RSSFeedItem {
            RSSFeedItem(
                title: title,
                creator: creator,
                category: category,
                html: html,
                link: link,
                guid: guid,
                publishedAt: publishedAt,
                pinned: pinned,
                closed: closed,
                archived: archived
            )
        }
    }

    private var channelTitle = ""
    private var channelDescription = ""
    private var channelCategory: String?
    private var items: [RSSFeedItem] = []
    private var currentItem: ItemBuilder?
    private var currentElement = ""
    private var currentText = ""

    private(set) var parseError: Error?

    var feed: RSSFeed {
        RSSFeed(
            title: channelTitle,
            description: channelDescription,
            category: channelCategory,
            items: items
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "item" {
            currentItem = ItemBuilder()
        }
        currentElement = elementName
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) {
            currentText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "item" {
            if let currentItem {
                items.append(currentItem.item)
            }
            currentItem = nil
            currentElement = ""
            currentText = ""
            return
        }

        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentItem != nil {
            assignItemValue(value, element: elementName)
        } else {
            assignChannelValue(value, element: elementName)
        }
        currentElement = ""
        currentText = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }

    private func assignChannelValue(_ value: String, element: String) {
        switch element {
        case "title" where channelTitle.isEmpty:
            channelTitle = value
        case "description" where channelDescription.isEmpty:
            channelDescription = value
        case "category" where channelCategory == nil:
            channelCategory = value
        default:
            break
        }
    }

    private func assignItemValue(_ value: String, element: String) {
        switch element {
        case "title": currentItem?.title = value
        case "dc:creator": currentItem?.creator = value
        case "category": currentItem?.category = value
        case "description": currentItem?.html = value
        case "link": currentItem?.link = value
        case "guid": currentItem?.guid = value
        case "pubDate": currentItem?.publishedAt = RSSDateParser.date(from: value)
        case "discourse:topicPinned": currentItem?.pinned = Self.isYes(value)
        case "discourse:topicClosed": currentItem?.closed = Self.isYes(value)
        case "discourse:topicArchived": currentItem?.archived = Self.isYes(value)
        default:
            break
        }
    }

    private static func isYes(_ value: String) -> Bool {
        value.caseInsensitiveCompare("yes") == .orderedSame
            || value.caseInsensitiveCompare("true") == .orderedSame
    }
}

private enum RSSDateParser {
    static func date(from value: String) -> Date? {
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss Z"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }
}
