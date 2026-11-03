import Foundation

public struct CatalogItem: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let artist: String?
    public let category: String
    public let difficulty: Int
    public let style: Int?
    public let key: String?
    public let tuning: String?
    public let sheetForm: Int
    public let bpm: Int?
    public let timeSignature: String?
    public let capo: Int?
    public let tuningText: String?
    public let heat: Int
    public let uploader: String?
    public let publishDate: String?
    public let format: String
    public let scoreURL: String?
    public let xheURL: String?
    public let screenshotURL: String?
    public let description: String?
    public let tags: String?
    public let createdAt: String?
    public let updatedAt: String?

    public init(
        id: String,
        title: String,
        artist: String? = nil,
        category: String = "guitar",
        difficulty: Int = 0,
        style: Int? = nil,
        key: String? = nil,
        tuning: String? = nil,
        sheetForm: Int = 0,
        bpm: Int? = nil,
        timeSignature: String? = nil,
        capo: Int? = nil,
        tuningText: String? = nil,
        heat: Int = 0,
        uploader: String? = nil,
        publishDate: String? = nil,
        format: String = "gp",
        scoreURL: String? = nil,
        xheURL: String? = nil,
        screenshotURL: String? = nil,
        description: String? = nil,
        tags: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.category = category
        self.difficulty = difficulty
        self.style = style
        self.key = key
        self.tuning = tuning
        self.sheetForm = sheetForm
        self.bpm = bpm
        self.timeSignature = timeSignature
        self.capo = capo
        self.tuningText = tuningText
        self.heat = heat
        self.uploader = uploader
        self.publishDate = publishDate
        self.format = format
        self.scoreURL = scoreURL
        self.xheURL = xheURL
        self.screenshotURL = screenshotURL
        self.description = description
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum CatalogSearchField: String, CaseIterable, Sendable {
    case title
    case artist
    case all
}

public enum CatalogSort: String, CaseIterable, Sendable {
    case newest
    case popular
    case difficulty
    case title
    case providedOrder
}

public enum CatalogRankingPeriod: String, CaseIterable, Sendable {
    case today
    case week
    case month
}

public struct CatalogQuery: Sendable {
    public let text: String
    public let searchField: CatalogSearchField
    public let category: String?
    public let difficulty: Int?
    public let style: Int?
    public let key: String?
    public let tuning: String?
    public let sheetForm: Int?
    public let ids: [String]?
    public let sort: CatalogSort
    public let limit: Int
    public let offset: Int
    /// Includes tags and key in all-field searches used by command suggestions.
    /// Regular catalog browsing keeps the website's title/artist behavior.
    public let includeMetadata: Bool

    public init(
        text: String = "",
        searchField: CatalogSearchField = .all,
        category: String? = nil,
        difficulty: Int? = nil,
        style: Int? = nil,
        key: String? = nil,
        tuning: String? = nil,
        sheetForm: Int? = nil,
        ids: [String]? = nil,
        sort: CatalogSort = .popular,
        limit: Int = 90,
        offset: Int = 0,
        includeMetadata: Bool = false
    ) {
        self.text = text
        self.searchField = searchField
        self.category = category
        self.difficulty = difficulty
        self.style = style
        self.key = key
        self.tuning = tuning
        self.sheetForm = sheetForm
        self.ids = ids
        self.sort = sort
        self.limit = limit
        self.offset = offset
        self.includeMetadata = includeMetadata
    }
}

public struct CatalogPage: Sendable {
    public let items: [CatalogItem]
    public let total: Int

    public init(items: [CatalogItem], total: Int) {
        self.items = items
        self.total = total
    }
}

public struct CatalogArticle: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let content: String
    public let category: String?
    public let views: Int
    public let createdAt: String?

    public init(id: String, title: String, content: String, category: String? = nil, views: Int = 0, createdAt: String? = nil) {
        self.id = id
        self.title = title
        self.content = content
        self.category = category
        self.views = views
        self.createdAt = createdAt
    }
}

public enum CatalogArticleSort: String, CaseIterable, Sendable {
    case newest
    case popular
}

public struct CatalogArticleQuery: Sendable {
    public let text: String
    public let sort: CatalogArticleSort
    public let limit: Int
    public let offset: Int

    public init(text: String = "", sort: CatalogArticleSort = .newest, limit: Int = 90, offset: Int = 0) {
        self.text = text
        self.sort = sort
        self.limit = limit
        self.offset = offset
    }
}

public struct CatalogArticlePage: Sendable {
    public let articles: [CatalogArticle]
    public let total: Int

    public init(articles: [CatalogArticle], total: Int) {
        self.articles = articles
        self.total = total
    }
}
