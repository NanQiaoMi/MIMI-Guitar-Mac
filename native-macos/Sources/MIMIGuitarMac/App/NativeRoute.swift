import Foundation

enum CatalogCategory: String, CaseIterable, Hashable, Identifiable {
    case all
    case guitar
    case ukulele
    case bass

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "全部曲谱"
        case .guitar: return "吉他谱"
        case .ukulele: return "尤克里里"
        case .bass: return "贝斯谱"
        }
    }
    var databaseValue: String? { self == .all ? nil : rawValue }
}

enum SearchDomain: String, CaseIterable, Hashable, Identifiable {
    case all
    case guitar
    case ukulele
    case article

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "全部"
        case .guitar: return "吉他谱"
        case .ukulele: return "尤克里里"
        case .article: return "文章"
        }
    }
}

enum AccountArea: String, CaseIterable, Hashable, Identifiable {
    case favorites
    case creator
    case history
    case profile

    var id: String { rawValue }
    var title: String {
        switch self {
        case .favorites: return "我的收藏"
        case .creator: return "创作中心"
        case .history: return "浏览记录"
        case .profile: return "个人资料"
        }
    }
    var routeNumber: String {
        switch self {
        case .favorites: return "0"
        case .creator: return "1"
        case .history: return "2"
        case .profile: return "3"
        }
    }
}

enum DocumentPage: String, CaseIterable, Hashable, Identifiable {
    case help
    case about
    case privacy
    case agreement
    case copyright
    case licenses
    case contact
    case uploadPolicy

    var id: String { rawValue }
    var title: String {
        switch self {
        case .help: return "帮助中心"
        case .about: return "关于 MIMI Guitar"
        case .privacy: return "隐私政策"
        case .agreement: return "用户协议"
        case .copyright: return "版权政策"
        case .licenses: return "授权说明"
        case .contact: return "联系我们"
        case .uploadPolicy: return "上传政策"
        }
    }
    var routePath: String {
        switch self {
        case .help: return "/help"
        case .about: return "/about"
        case .privacy: return "/policy"
        case .agreement: return "/agreementPolicy"
        case .copyright: return "/copyrightPolicy"
        case .licenses: return "/licenses"
        case .contact: return "/contact"
        case .uploadPolicy: return "/uploadpolicy"
        }
    }
}

struct NativeRouteQueryItem: Hashable {
    let name: String
    let value: String?
}

struct NativeCatalogRouteQuery: Hashable {
    let items: [NativeRouteQueryItem]

    init(_ items: [URLQueryItem]) {
        self.items = items.map { NativeRouteQueryItem(name: $0.name, value: $0.value) }
    }

    func value(_ names: [String]) -> String? {
        for name in names {
            if let value = items.first(where: { $0.name == name })?.value, !value.isEmpty { return value }
        }
        return nil
    }
}

enum NativeRoute: Hashable {
    case home
    case catalog(CatalogCategory)
    case catalogQuery(CatalogCategory, NativeCatalogRouteQuery)
    case search(query: String, domain: SearchDomain)
    case score(id: String)
    case studio
    case studioClone(sourceID: String)
    case studioScore(id: String)
    case studioProject(id: String)
    case articles
    case article(id: String)
    case publishArticle
    case practice(scoreID: String?)
    case library
    case dataSettings
    case motion
    case showcase
    case account(AccountArea)
    case login
    case register
    case authenticationReturn(destination: String, isRegistration: Bool)
    case resetPassword
    case upload
    case document(DocumentPage)

    var title: String {
        switch self {
        case .home: return "首页"
        case .catalog(let category): return category.title
        case .catalogQuery(let category, _): return category.title
        case .search: return "搜索结果"
        case .score: return "曲谱详情"
        case .studio: return "制谱工坊 PRO"
        case .studioClone: return "制谱工坊 PRO"
        case .studioScore: return "制谱工坊 PRO"
        case .studioProject: return "制谱工坊 PRO"
        case .articles: return "专栏文章"
        case .article: return "文章"
        case .publishArticle: return "发布文章"
        case .practice: return "我的练习"
        case .library: return "我的谱"
        case .dataSettings: return "数据与备份"
        case .motion: return "交互体验"
        case .showcase: return "界面展示"
        case .account(let area): return area.title
        case .login: return "登录"
        case .register: return "注册"
        case .authenticationReturn(_, let isRegistration): return isRegistration ? "注册" : "登录"
        case .resetPassword: return "重置密码"
        case .upload: return "上传"
        case .document(let page): return page.title
        }
    }

    static func resolve(_ url: URL) -> NativeRoute? {
        let path = url.path
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { query.first(where: { $0.name == name })?.value }
        func catalog(_ category: CatalogCategory) -> NativeRoute {
            let relevant = Set(["difficulty", "style", "key", "tuning", "sheetForm", "field", "sort", "no", "page", "searchValue", "keyword"])
            guard query.contains(where: { relevant.contains($0.name) }) else { return .catalog(category) }
            return .catalogQuery(category, NativeCatalogRouteQuery(query))
        }

        switch path {
        case "/", "": return .home
        case "/tabs": return catalog(.guitar)
        case "/ukulele": return catalog(.ukulele)
        case "/studio":
            if let sourceID = value("cloneFrom"), !sourceID.isEmpty { return .studioClone(sourceID: sourceID) }
            if let scoreID = value("cloneFromPersonal"), !scoreID.isEmpty { return .studioScore(id: scoreID) }
            if let projectID = value("project"), !projectID.isEmpty { return .studioProject(id: projectID) }
            return .studio
        case "/article": return .articles
        case "/community": return .articles
        case "/publishArticle": return .publishArticle
        case "/practice": return .practice(scoreID: value("score"))
        case "/library": return .library
        case "/settings/data": return .dataSettings
        case "/motion": return .motion
        case "/showcase": return .showcase
        case "/login":
            if let destination = localReturnDestination(value("returnUrl")) { return .authenticationReturn(destination: destination, isRegistration: false) }
            return .login
        case "/register":
            if let destination = localReturnDestination(value("returnUrl")) { return .authenticationReturn(destination: destination, isRegistration: true) }
            return .register
        case "/account/reset": return .resetPassword
        case "/upload": return .upload
        case "/search", "/searchResults":
            let rawType = value("type") ?? "guitar"
            let domain = SearchDomain(rawValue: rawType) ?? .guitar
            return .search(query: value("searchValue") ?? value("q") ?? "", domain: domain)
        case "/help": return .document(.help)
        case "/about": return .document(.about)
        case "/policy": return .document(.privacy)
        case "/agreementPolicy": return .document(.agreement)
        case "/copyrightPolicy": return .document(.copyright)
        case "/licenses": return .document(.licenses)
        case "/contact", "/countact-us": return .document(.contact)
        case "/uploadpolicy": return .document(.uploadPolicy)
        default: break
        }

        let components = path.split(separator: "/").map(String.init)
        if components.count == 2, components[0] == "account" {
            if components[1] == "0" { return .account(.favorites) }
            if components[1] == "1" { return .account(.creator) }
            if components[1] == "2" { return .account(.history) }
            if components[1] == "3" { return .account(.profile) }
        }
        if components.count == 2, components[0] == "article" {
            return .article(id: components[1].removingPercentEncoding ?? components[1])
        }
        if components.count == 2, components[0] == "tabs" || components[0] == "ukulele" || components[0] == "guitar" {
            return .score(id: components[1].removingPercentEncoding ?? components[1])
        }
        return nil
    }

    private static func localReturnDestination(_ raw: String?) -> String? {
        guard let raw, raw.hasPrefix("/"), !raw.hasPrefix("//"),
              let parsed = URL(string: "mimi-local://route\(raw)"),
              resolveWithoutReturnLoop(parsed) != nil else { return nil }
        return raw
    }

    private static func resolveWithoutReturnLoop(_ url: URL) -> NativeRoute? {
        // Resolve only a path on the app's synthetic origin; authentication return URLs cannot redirect externally.
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard components?.scheme == "mimi-local", components?.host == "route" else { return nil }
        let path = components?.path ?? "/"
        if path == "/login" || path == "/register" { return nil }
        var local = URLComponents()
        local.scheme = "mimi-local"; local.host = "route"; local.path = path; local.queryItems = components?.queryItems
        guard let safeURL = local.url else { return nil }
        return resolve(safeURL)
    }
}
