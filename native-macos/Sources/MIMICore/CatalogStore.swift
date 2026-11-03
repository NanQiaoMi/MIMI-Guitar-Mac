import CSQLite
import Foundation

public enum CatalogStoreError: Error, LocalizedError {
    case open(String)
    case query(String)
    case bind(String)

    public var errorDescription: String? {
        switch self {
        case .open(let detail): return "无法打开本地曲谱目录：\(detail)"
        case .query(let detail): return "读取本地曲谱目录失败：\(detail)"
        case .bind(let detail): return "构造本地曲谱查询失败：\(detail)"
        }
    }
}

/// Read-only, actor-isolated access to the bundled SQLite catalog and articles.
public actor CatalogStore {
    private var database: OpaquePointer?
    private let catalogColumns: Set<String>
    private let articleColumns: Set<String>

    public init(databaseURL: URL) throws {
        var opened: OpaquePointer?
        let result = sqlite3_open_v2(databaseURL.path, &opened, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let opened else {
            let detail = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite returned code \(result)"
            if let opened { sqlite3_close(opened) }
            throw CatalogStoreError.open(detail)
        }
        database = opened
        sqlite3_busy_timeout(opened, 2_000)
        do {
            let catalog = try Self.tableColumns(database: opened, table: "catalog")
            let articles = try Self.tableColumns(database: opened, table: "articles")
            for required in ["id", "title", "artist", "category", "difficulty", "style", "key", "tuning", "sheet_form", "bpm", "time_sig", "capo", "tuning_text", "heat", "uploader", "publish_date", "format", "score_url", "xhe_url", "screenshot_url", "description", "tags", "created_at", "updated_at"] {
                guard catalog.contains(required) else { throw CatalogStoreError.open("catalog 缺少必需字段 \(required)") }
            }
            for required in ["id", "title", "content", "category", "views"] {
                guard articles.contains(required) else { throw CatalogStoreError.open("articles 缺少必需字段 \(required)") }
            }
            catalogColumns = catalog
            articleColumns = articles
        } catch {
            sqlite3_close(opened)
            database = nil
            throw error
        }
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    public func search(_ query: CatalogQuery) throws -> CatalogPage {
        guard let database else { throw CatalogStoreError.open("数据库连接已关闭") }
        let orderedIDs = query.sort == .providedOrder && query.ids != nil ? Self.uniqueIDs(query.ids ?? []) : nil
        if let orderedIDs, orderedIDs.isEmpty { return CatalogPage(items: [], total: 0) }

        let filter = Self.filterSQL(for: query, columns: catalogColumns, includeIDs: orderedIDs == nil)
        let idOrder = orderedIDs.map(Self.orderedIDCTE) ?? OrderedIDCTE.empty
        let fromClause = "catalog AS c" + idOrder.joinClause
        let countSQL = "\(idOrder.withClause) SELECT COUNT(*) FROM \(fromClause)\(filter.sql)"
        let total = try Self.scalarInt(database: database, sql: countSQL, values: idOrder.values + filter.values)

        let ordering: String
        switch query.sort {
        case .newest:
            let dateField = catalogColumns.contains("publish_date") ? "c.publish_date" : (catalogColumns.contains("created_at") ? "c.created_at" : "NULL")
            ordering = "\(dateField) DESC, c.title COLLATE NOCASE ASC, c.id ASC"
        case .popular:
            ordering = "c.heat DESC, c.title COLLATE NOCASE ASC, c.id ASC"
        case .difficulty:
            ordering = "c.difficulty DESC, c.heat DESC, c.title COLLATE NOCASE ASC, c.id ASC"
        case .title:
            ordering = "c.title COLLATE NOCASE ASC, c.id ASC"
        case .providedOrder:
            ordering = orderedIDs == nil ? "c.heat DESC, c.title COLLATE NOCASE ASC, c.id ASC" : "requested.position ASC"
        }

        // Native library pagination follows the website's 90-row page contract.
        let limit = min(max(query.limit, 0), 90)
        let offset = max(query.offset, 0)
        let sql = """
        \(idOrder.withClause)
        SELECT \(Self.catalogSelectList(columns: catalogColumns))
        FROM \(fromClause)\(filter.sql)
        ORDER BY \(ordering)
        LIMIT ? OFFSET ?
        """
        let items = try Self.readItems(database: database, sql: sql, values: idOrder.values + filter.values + [.integer(limit), .integer(offset)])
        return CatalogPage(items: items, total: total)
    }

    public func item(id: String) throws -> CatalogItem? {
        guard let database else { throw CatalogStoreError.open("数据库连接已关闭") }
        let sql = "SELECT \(Self.catalogSelectList(columns: catalogColumns)) FROM catalog AS c WHERE c.id = ? LIMIT 1"
        return try Self.readItems(database: database, sql: sql, values: [.text(id)]).first
    }

    public func article(id: String) throws -> CatalogArticle? {
        guard let database else { throw CatalogStoreError.open("数据库连接已关闭") }
        let sql = "SELECT \(Self.articleSelectList(columns: articleColumns)) FROM articles AS a WHERE a.id = ? LIMIT 1"
        return try Self.readArticles(database: database, sql: sql, values: [.text(id)]).first
    }

    /// Searches bundled articles together with articles published in this app session.
    /// A published article replaces the bundled row with the same ID.
    public func searchArticles(_ query: CatalogArticleQuery, including additionalArticles: [CatalogArticle] = []) throws -> CatalogArticlePage {
        guard let database else { throw CatalogStoreError.open("数据库连接已关闭") }
        let normalized = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let articlePredicate = normalized.isEmpty
            ? nil
            : "instr(lower(a.title), lower(?)) > 0 OR instr(lower(COALESCE(a.content, '')), lower(?)) > 0"
        let filterValues: [SQLValue] = normalized.isEmpty ? [] : [.text(normalized), .text(normalized)]
        let filterSQL = articlePredicate.map { " WHERE (\($0))" } ?? ""
        let total = try Self.scalarInt(database: database, sql: "SELECT COUNT(*) FROM articles AS a\(filterSQL)", values: filterValues)
        let ordering = query.sort == .popular ? "a.views DESC, a.title COLLATE NOCASE ASC, a.id ASC" : "\(articleColumns.contains("created_at") ? "a.created_at" : "NULL") DESC, a.title COLLATE NOCASE ASC, a.id ASC"
        let limit = min(max(query.limit, 0), 90)
        let offset = max(query.offset, 0)

        var cachedByID: [String: CatalogArticle] = [:]
        for article in additionalArticles { cachedByID[article.id] = article }
        guard !cachedByID.isEmpty else {
            let sql = """
            SELECT \(Self.articleSelectList(columns: articleColumns))
            FROM articles AS a\(filterSQL)
            ORDER BY \(ordering)
            LIMIT ? OFFSET ?
            """
            let articles = try Self.readArticles(database: database, sql: sql, values: filterValues + [.integer(limit), .integer(offset)])
            return CatalogArticlePage(articles: articles, total: total)
        }

        let cacheMatches = cachedByID.mapValues { Self.articleMatches($0, normalizedQuery: normalized) }
        var bundledMatchByID: [String: Bool] = [:]
        for id in cachedByID.keys {
            bundledMatchByID[id] = try article(id: id).map { Self.articleMatches($0, normalizedQuery: normalized) } ?? false
        }
        var mergedTotal = total
        for id in cachedByID.keys {
            let bundledMatches = bundledMatchByID[id] ?? false
            let publishedMatches = cacheMatches[id] ?? false
            if bundledMatches && !publishedMatches { mergedTotal -= 1 }
            else if !bundledMatches && publishedMatches { mergedTotal += 1 }
        }

        // Remove every replaced bundled ID before fetching database candidates.
        // Otherwise a cached article that no longer matches can leak its old
        // bundled row back into the result, and a cached row whose sort fields
        // changed can hide the database row needed to fill a later page.
        let replacedIDs = Array(cachedByID.keys).sorted()
        let exclusion = "a.id NOT IN (\(Array(repeating: "?", count: replacedIDs.count).joined(separator: ", ")))"
        let candidateFilterSQL = articlePredicate.map { " WHERE (\($0)) AND \(exclusion)" } ?? " WHERE \(exclusion)"
        let candidateValues = filterValues + replacedIDs.map(SQLValue.text)

        // At most one bundled candidate is removed for each replaced ID, and
        // each matching cached row can move ahead of the database candidates.
        // Overfetching both counts guarantees enough rows to sort and slice the
        // requested merged page even when cached fields change its position.
        let removedBundledMatches = cachedByID.keys.reduce(into: 0) { count, id in
            if bundledMatchByID[id] == true { count += 1 }
        }
        let matchingCachedArticles = cacheMatches.values.filter { $0 }.count
        let (pageEnd, pageOverflow) = offset.addingReportingOverflow(limit)
        let (afterRemoved, removedOverflow) = pageEnd.addingReportingOverflow(removedBundledMatches)
        let (candidateCount, cachedOverflow) = afterRemoved.addingReportingOverflow(matchingCachedArticles)
        let fetchCount = pageOverflow || removedOverflow || cachedOverflow ? Int.max : candidateCount
        let sql = """
        SELECT \(Self.articleSelectList(columns: articleColumns))
        FROM articles AS a\(candidateFilterSQL)
        ORDER BY \(ordering)
        LIMIT ? OFFSET 0
        """
        let bundled = try Self.readArticles(database: database, sql: sql, values: candidateValues + [.integer(fetchCount)])
        var mergedByID: [String: CatalogArticle] = Dictionary(uniqueKeysWithValues: bundled.map { ($0.id, $0) })
        for (id, article) in cachedByID where cacheMatches[id] == true { mergedByID[id] = article }
        let merged = mergedByID.values.sorted { Self.articlePrecedes($0, $1, sort: query.sort, hasCreatedAt: articleColumns.contains("created_at")) }
        guard limit > 0, offset < merged.count else { return CatalogArticlePage(articles: [], total: mergedTotal) }
        let end = min(merged.count, offset > Int.max - limit ? Int.max : offset + limit)
        return CatalogArticlePage(articles: Array(merged[offset..<end]), total: mergedTotal)
    }

    public func count() throws -> Int {
        guard let database else { throw CatalogStoreError.open("数据库连接已关闭") }
        return try Self.scalarInt(database: database, sql: "SELECT COUNT(*) FROM catalog", values: [])
    }

    public func articleCount() throws -> Int {
        guard let database else { throw CatalogStoreError.open("数据库连接已关闭") }
        return try Self.scalarInt(database: database, sql: "SELECT COUNT(*) FROM articles", values: [])
    }

    /// Mirrors the home page's today/week/month playable rankings. Each period
    /// uses a rolling 24-hour/7-day/30-day publishDate window and falls back to
    /// the all-time playable heat list when fewer than six rows qualify.
    public func rankings(period: CatalogRankingPeriod, now: Date = Date()) throws -> [CatalogItem] {
        guard let database else { throw CatalogStoreError.open("数据库连接已关闭") }
        let days: TimeInterval
        switch period {
        case .today: days = 1
        case .week: days = 7
        case .month: days = 30
        }
        let cutoff = ISO8601DateFormatter().string(from: now.addingTimeInterval(-days * 24 * 60 * 60))
        if catalogColumns.contains("publish_date") {
            let filtered = try Self.readItems(
                database: database,
                sql: "SELECT \(Self.catalogSelectList(columns: catalogColumns)) FROM catalog AS c WHERE c.score_url IS NOT NULL AND trim(c.score_url) <> '' AND julianday(c.publish_date) >= julianday(?) ORDER BY c.heat DESC, c.title COLLATE NOCASE ASC, c.id ASC LIMIT 10",
                values: [.text(cutoff)]
            )
            if filtered.count >= 6 { return filtered }
        }
        return try Self.readItems(
            database: database,
            sql: "SELECT \(Self.catalogSelectList(columns: catalogColumns)) FROM catalog AS c WHERE c.score_url IS NOT NULL AND trim(c.score_url) <> '' ORDER BY c.heat DESC, c.title COLLATE NOCASE ASC, c.id ASC LIMIT 10",
            values: []
        )
    }

    private static func tableColumns(database: OpaquePointer, table: String) throws -> Set<String> {
        let statement = try prepare(database: database, sql: "PRAGMA table_info(\(table))")
        defer { sqlite3_finalize(statement) }
        var result = Set<String>()
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW, let name = sqlite3_column_text(statement, 1) else { throw makeError(.query, database: database) }
            result.insert(String(cString: UnsafeRawPointer(name).assumingMemoryBound(to: CChar.self)))
        }
    }

    private static func catalogSelectList(columns: Set<String>) -> String {
        let fields: [(String, String)] = [
            ("id", "id"), ("title", "title"), ("artist", "artist"), ("category", "category"),
            ("difficulty", "difficulty"), ("style", "style"), ("key", "key"), ("tuning", "tuning"),
            ("sheet_form", "sheet_form"), ("bpm", "bpm"), ("time_sig", "time_signature"), ("capo", "capo"),
            ("tuning_text", "tuning_text"), ("heat", "heat"), ("uploader", "uploader"), ("publish_date", "publish_date"),
            ("format", "format"), ("score_url", "score_url"), ("xhe_url", "xhe_url"),
            ("screenshot_url", "screenshot_url"), ("description", "description"), ("tags", "tags"),
            ("created_at", "created_at"), ("updated_at", "updated_at"),
        ]
        return fields.map { field, alias in columns.contains(field) ? "c.\(field) AS \(alias)" : "NULL AS \(alias)" }.joined(separator: ", ")
    }

    private static func articleSelectList(columns: Set<String>) -> String {
        let fields: [(String, String)] = [("id", "id"), ("title", "title"), ("content", "content"), ("category", "category"), ("views", "views"), ("created_at", "created_at")]
        return fields.map { field, alias in columns.contains(field) ? "a.\(field) AS \(alias)" : "NULL AS \(alias)" }.joined(separator: ", ")
    }

    private static func articleMatches(_ article: CatalogArticle, normalizedQuery: String) -> Bool {
        guard !normalizedQuery.isEmpty else { return true }
        let needle = sqliteLower(normalizedQuery)
        return sqliteLower(article.title).contains(needle) || sqliteLower(article.content).contains(needle)
    }

    private static func articlePrecedes(_ lhs: CatalogArticle, _ rhs: CatalogArticle, sort: CatalogArticleSort, hasCreatedAt: Bool) -> Bool {
        if sort == .popular, lhs.views != rhs.views { return lhs.views > rhs.views }
        if sort == .newest, hasCreatedAt, lhs.createdAt != rhs.createdAt {
            switch (lhs.createdAt, rhs.createdAt) {
            case let (left?, right?): return left > right
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): break
            }
        }
        let titleOrder = sqliteNoCaseCompare(lhs.title, rhs.title)
        if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
        return lhs.id.utf8.lexicographicallyPrecedes(rhs.id.utf8)
    }

    /// SQLite's built-in lower() folds ASCII only, matching its article query.
    private static func sqliteLower(_ value: String) -> String {
        String(decoding: value.utf8.map { byte in (65...90).contains(byte) ? byte + 32 : byte }, as: UTF8.self)
    }

    /// SQLite NOCASE folds ASCII letters and compares the resulting UTF-8 bytes.
    private static func sqliteNoCaseCompare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.utf8.map { byte in (65...90).contains(byte) ? byte + 32 : byte }
        let right = rhs.utf8.map { byte in (65...90).contains(byte) ? byte + 32 : byte }
        if left == right { return .orderedSame }
        return left.lexicographicallyPrecedes(right) ? .orderedAscending : .orderedDescending
    }

    private static func filterSQL(for query: CatalogQuery, columns: Set<String>, includeIDs: Bool) -> (sql: String, values: [SQLValue]) {
        var clauses: [String] = []
        var values: [SQLValue] = []
        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let escapedText = text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            let term = "%\(escapedText)%"
            switch query.searchField {
            case .title:
                clauses.append("c.title LIKE ? ESCAPE '\\'")
                values.append(.text(term))
            case .artist:
                clauses.append("COALESCE(c.artist, '') LIKE ? ESCAPE '\\'")
                values.append(.text(term))
            case .all:
                if query.includeMetadata {
                    clauses.append("(c.title LIKE ? ESCAPE '\\' OR COALESCE(c.artist, '') LIKE ? ESCAPE '\\' OR instr(lower(COALESCE(c.tags, '')), lower(?)) > 0 OR instr(lower(COALESCE(c.key, '')), lower(?)) > 0)")
                    values.append(contentsOf: [.text(term), .text(term), .text(text), .text(text)])
                } else {
                    clauses.append("(c.title LIKE ? ESCAPE '\\' OR COALESCE(c.artist, '') LIKE ? ESCAPE '\\')")
                    values.append(contentsOf: [.text(term), .text(term)])
                }
            }
        }
        if let category = query.category?.trimmingCharacters(in: .whitespacesAndNewlines), !category.isEmpty, category.lowercased() != "all" {
            clauses.append("c.category = ?")
            values.append(.text(category))
        }
        if let difficulty = query.difficulty { clauses.append("c.difficulty = ?"); values.append(.integer(difficulty)) }
        if let style = query.style {
            if columns.contains("style") { clauses.append("c.style = ?"); values.append(.integer(style)) }
            else { clauses.append("0") }
        }
        if let key = query.key, !key.isEmpty {
            if columns.contains("key") { clauses.append("c.key = ?"); values.append(.text(key)) }
            else { clauses.append("0") }
        }
        if let tuning = query.tuning, !tuning.isEmpty {
            if columns.contains("tuning") { clauses.append("c.tuning = ?"); values.append(.text(tuning)) }
            else { clauses.append("0") }
        }
        if let sheetForm = query.sheetForm {
            if sheetForm == 4 { clauses.append("c.sheet_form IN (4, 7)") }
            else { clauses.append("c.sheet_form = ?"); values.append(.integer(sheetForm)) }
        }
        if includeIDs, let ids = query.ids {
            let unique = uniqueIDs(ids)
            guard !unique.isEmpty else { return (" WHERE 0", []) }
            clauses.append("c.id IN (\(Array(repeating: "?", count: unique.count).joined(separator: ", "))) ")
            values.append(contentsOf: unique.map(SQLValue.text))
        }
        return clauses.isEmpty ? ("", values) : (" WHERE " + clauses.joined(separator: " AND "), values)
    }

    private static func uniqueIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    private static func orderedIDCTE(_ ids: [String]) -> OrderedIDCTE {
        guard !ids.isEmpty else { return .empty }
        let rows = ids.indices.map { "(?, \($0))" }
        return OrderedIDCTE(
            withClause: "WITH requested_ids(id, position) AS (VALUES \(rows.joined(separator: ", "))) ",
            joinClause: " JOIN requested_ids AS requested ON requested.id = c.id",
            values: ids.map(SQLValue.text)
        )
    }

    private static func scalarInt(database: OpaquePointer, sql: String, values: [SQLValue]) throws -> Int {
        let statement = try prepare(database: database, sql: sql)
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement, database: database)
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else { throw makeError(.query, database: database) }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private static func readItems(database: OpaquePointer, sql: String, values: [SQLValue]) throws -> [CatalogItem] {
        let statement = try prepare(database: database, sql: sql)
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement, database: database)
        var items: [CatalogItem] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw makeError(.query, database: database) }
            items.append(CatalogItem(
                id: text(statement, 0) ?? "", title: text(statement, 1) ?? "", artist: text(statement, 2),
                category: text(statement, 3) ?? "guitar", difficulty: integer(statement, 4), style: optionalInt(statement, 5),
                key: text(statement, 6), tuning: text(statement, 7), sheetForm: integer(statement, 8), bpm: optionalInt(statement, 9),
                timeSignature: text(statement, 10), capo: optionalInt(statement, 11), tuningText: text(statement, 12),
                heat: integer(statement, 13), uploader: text(statement, 14), publishDate: text(statement, 15), format: text(statement, 16) ?? "gp",
                scoreURL: text(statement, 17), xheURL: text(statement, 18), screenshotURL: text(statement, 19), description: text(statement, 20),
                tags: text(statement, 21), createdAt: text(statement, 22), updatedAt: text(statement, 23)
            ))
        }
        return items
    }

    private static func readArticles(database: OpaquePointer, sql: String, values: [SQLValue]) throws -> [CatalogArticle] {
        let statement = try prepare(database: database, sql: sql)
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement, database: database)
        var articles: [CatalogArticle] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw makeError(.query, database: database) }
            articles.append(CatalogArticle(id: text(statement, 0) ?? "", title: text(statement, 1) ?? "", content: text(statement, 2) ?? "", category: text(statement, 3), views: integer(statement, 4), createdAt: text(statement, 5)))
        }
        return articles
    }

    private static func prepare(database: OpaquePointer, sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else { throw makeError(.query, database: database) }
        return statement
    }

    private static func bind(_ values: [SQLValue], to statement: OpaquePointer, database: OpaquePointer) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .integer(let number): result = sqlite3_bind_int64(statement, index, sqlite3_int64(number))
            case .text(let string): result = string.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) }
            }
            guard result == SQLITE_OK else { throw makeError(.bind, database: database) }
        }
    }

    private static func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL, let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: UnsafeRawPointer(value).assumingMemoryBound(to: CChar.self))
    }

    private static func integer(_ statement: OpaquePointer, _ index: Int32) -> Int { Int(sqlite3_column_int64(statement, index)) }
    private static func optionalInt(_ statement: OpaquePointer, _ index: Int32) -> Int? { sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : integer(statement, index) }

    private static func makeError(_ kind: ErrorKind, database: OpaquePointer) -> CatalogStoreError {
        let detail = String(cString: sqlite3_errmsg(database))
        return kind == .bind ? .bind(detail) : .query(detail)
    }
}

private enum SQLValue { case text(String); case integer(Int) }
private struct OrderedIDCTE {
    let withClause: String
    let joinClause: String
    let values: [SQLValue]
    static let empty = OrderedIDCTE(withClause: "", joinClause: "", values: [])
}
private enum ErrorKind: Equatable { case query; case bind }
