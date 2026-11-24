import AppKit
import MIMICore
import SwiftUI
import UniformTypeIdentifiers

struct AccountAuthView: View {
    @EnvironmentObject private var model: AppModel
    private var isRegister: Bool {
        switch model.route {
        case .register: return true
        case .authenticationReturn(_, let isRegistration): return isRegistration
        default: return false
        }
    }
    private var isReset: Bool { if case .resetPassword = model.route { return true }; return false }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(isReset ? "Reset" : isRegister ? "Sign up" : "Sign in").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(MIMITheme.mutedInk)
            Text(isReset ? "重置密码" : isRegister ? "注册 MIMI Guitar" : "登录 MIMI Guitar").font(MIMITheme.displayFont(size: 28, weight: .bold)).foregroundStyle(MIMITheme.ink)
            Text(isReset ? "密码重置需要短信验证码服务。当前环境尚未配置真实短信服务，因此此功能暂不可用。" : isRegister ? "使用手机号或邮箱注册，登录后可使用收藏与文章发布。公开曲谱投稿当前暂停。" : "登录后可收藏曲谱、同步浏览记录与上传作品。公开曲谱投稿当前暂停；本机个人资料仍独立保存在本地。")
                .font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.mutedInk).fixedSize(horizontal: false, vertical: true)

            if isReset {
                VStack(alignment: .leading, spacing: 13) {
                    VStack(alignment: .leading, spacing: 5) { Text("手机号").font(MIMITheme.bodyFont(size: 12, weight: .semibold)); TextField("输入手机号", text: $model.resetPhone).textFieldStyle(.roundedBorder) }
                    HStack(spacing: 9) { TextField("短信验证码", text: $model.resetCode).textFieldStyle(.roundedBorder); Button("发送验证码") { model.sendResetCode() }.buttonStyle(PaperSecondaryButtonStyle()).disabled(model.accountBusy) }
                    VStack(alignment: .leading, spacing: 5) { Text("新密码").font(MIMITheme.bodyFont(size: 12, weight: .semibold)); SecureField("设置新密码", text: $model.resetPasswordValue).textFieldStyle(.roundedBorder) }
                    Text("当前服务返回 503 时会如实显示短信服务未配置，不会填入或伪造验证码。")
                        .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                    HStack { Button("重置密码") { model.resetPassword() }.buttonStyle(PaperProminentButtonStyle()).disabled(model.accountBusy || model.resetPhone.isEmpty || model.resetCode.isEmpty || model.resetPasswordValue.isEmpty); if model.accountBusy { ProgressView().controlSize(.small) } }
                }
            } else {
                VStack(alignment: .leading, spacing: 13) {
                    VStack(alignment: .leading, spacing: 5) { Text("手机号或邮箱").font(MIMITheme.bodyFont(size: 12, weight: .semibold)); TextField("手机号或邮箱", text: $model.authAccount).textContentType(.username).textFieldStyle(.roundedBorder) }
                    if isRegister { VStack(alignment: .leading, spacing: 5) { Text("昵称").font(MIMITheme.bodyFont(size: 12, weight: .semibold)); TextField("设置昵称", text: $model.authNickname).textFieldStyle(.roundedBorder) } }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("密码").font(MIMITheme.bodyFont(size: 12, weight: .semibold))
                        if isRegister {
                            SecureField("密码", text: $model.authPassword).textFieldStyle(.roundedBorder).onSubmit { submit() }
                        } else {
                            SecureField("密码", text: $model.authPassword).textContentType(.password).textFieldStyle(.roundedBorder).onSubmit { submit() }
                        }
                    }
                    if let message = model.accountMessage { PaperNotice(text: message, error: model.accountMessageIsError) }
                    HStack(spacing: 11) {
                        Button(isRegister ? "注册" : "登录", action: submit).buttonStyle(PaperProminentButtonStyle()).disabled(model.accountBusy || model.authAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.authPassword.isEmpty || (isRegister && model.authNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                        if model.accountBusy { ProgressView().controlSize(.small) }
                        Spacer()
                        if !isRegister { Button("忘记密码？") { model.navigate(.resetPassword) }.buttonStyle(.plain).foregroundStyle(MIMITheme.darkGold) }
                    }
                    HStack(spacing: 5) { Text(isRegister ? "已有账号？" : "还没有账号？").foregroundStyle(MIMITheme.mutedInk); Button(isRegister ? "去登录" : "立即注册") { model.navigate(isRegister ? .login : .register) }.buttonStyle(.plain).foregroundStyle(MIMITheme.darkGold) }.font(MIMITheme.bodyFont(size: 12))
                }
            }
            Divider().overlay(MIMITheme.softBorder)
            HStack(alignment: .top, spacing: 8) { Image(systemName: "lock.shield").foregroundStyle(MIMITheme.darkGold); Text("账号会话令牌保存在 macOS 钥匙串。HTTP 仅允许 localhost / IPv4 loopback / ::1，其他账号服务必须使用 HTTPS。退出账号不会删除本机收藏、练习或导入曲谱。") }
                .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
        }
        .padding(32).frame(maxWidth: 448, alignment: .leading).mimiCard(radius: 22, fill: MIMITheme.paperWhite)
        .frame(maxWidth: .infinity, alignment: .top)
    }
    private func submit() { if isRegister { model.register() } else { model.login() } }
}

struct AccountView: View {
    @EnvironmentObject private var model: AppModel
    let area: AccountArea
    @State private var clearedHistory: [PersonalHistoryEntry]?
    @State private var historyMessage: String?
    @State private var isClearingHistory = false
    @State private var favoritesMessage: String?
    @State private var favoritesMessageIsError = false
    @State private var isRemovingLocalFavorite = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline) {
                Text(area.title).font(MIMITheme.displayFont(size: 44, weight: .medium)).tracking(-0.88).foregroundStyle(MIMITheme.ink)
                Spacer()
                if area == .favorites {
                    Button("继续找谱") { model.navigate(.catalog(.all)) }
                        .font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.signalBlue).buttonStyle(.plain)
                }
            }
            accountNavigation
            if let message = model.accountMessage { PaperNotice(text: message, error: model.accountMessageIsError) }
            switch area {
            case .favorites: favoritesPanel
            case .creator: creatorPanel
            case .history: historyPanel
            case .profile: profilePanel
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear { model.loadAccount(area: area) }
    }

    private var accountNavigation: some View {
        HStack(spacing: 4) {
            ForEach(AccountArea.allCases) { candidate in
                Button(candidate.title) { model.navigate(.account(candidate)) }
                    .font(MIMITheme.bodyFont(size: 14, weight: candidate == area ? .medium : .regular))
                    .foregroundStyle(MIMITheme.bodyInk)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(candidate == area ? MIMITheme.navigationSegment : .clear, in: RoundedRectangle(cornerRadius: 18))
                    .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            Button("上传") { model.navigate(.upload) }.buttonStyle(PaperSecondaryButtonStyle())
            if model.remoteUser != nil {
                Button(model.accountBusy ? "退出中…" : "退出登录") { model.logout() }
                    .buttonStyle(PaperSecondaryButtonStyle()).disabled(model.accountBusy)
            }
        }
        .padding(8)
        .mimiCard(radius: 24, fill: MIMITheme.paperWhite, border: MIMITheme.softBorder, shadowOpacity: 0.025)
    }
    private var favoritesPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { PaperSectionTitle(title: "本设备收藏", detail: "与“我的谱”使用同一份本地个人资料，并包含在个人备份中。") ; Spacer(); Button("打开我的谱") { model.selectSection(.favorites) }.buttonStyle(PaperSecondaryButtonStyle()) }
            if let favoritesMessage { PaperNotice(text: favoritesMessage, error: favoritesMessageIsError) }
            let localFavorites = model.personalScores.filter { model.personalSnapshot.favorites.contains($0.id) }
            if localFavorites.isEmpty {
                Text("还没有本设备收藏的曲谱。")
                    .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk)
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
            }
            ForEach(localFavorites) { score in
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill").foregroundStyle(MIMITheme.terracotta)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(score.title).font(MIMITheme.bodyFont(size: 14, weight: .semibold))
                        Text(score.source == "catalog" ? "\(score.artist) · \(score.category == "ukulele" ? "尤克里里" : "曲库") · 本设备引用" : "\(score.artist) · 个人谱 · 本设备")
                            .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                    }
                    Spacer()
                    Button("打开") { model.openPersonalScore(score) }.buttonStyle(PaperSecondaryButtonStyle())
                    Button("取消收藏", role: .destructive) { removeLocalFavorite(score) }
                        .buttonStyle(PaperSecondaryButtonStyle()).disabled(isRemovingLocalFavorite)
                }
                .padding(12).mimiCard(radius: 12, fill: MIMITheme.paperWhite, shadowOpacity: 0.02)
            }

            HStack { PaperSectionTitle(title: "旧版云端收藏", detail: model.remoteUser == nil ? "登录后读取账号数据库中的旧收藏。" : "这些条目不会自动迁入本机收藏，两类收藏分别管理。") ; Spacer(); if model.accountBusy { ProgressView().controlSize(.small) } }
            if model.remoteUser == nil {
                accountRequired("登录后查看服务器中的旧收藏。", returnArea: .favorites)
            } else if model.remoteFavorites.isEmpty && !model.accountBusy {
                Text("服务器没有可读取的旧收藏。若服务不可用，错误会显示在页面上；空列表不代表本机收藏已删除。")
                    .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk).padding(20).frame(maxWidth: .infinity, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
            }
            ForEach(model.remoteFavorites) { favorite in
                let local = model.personalSnapshot.favorites.contains("catalog:\(favorite.id)") || model.personalSnapshot.favorites.contains(favorite.id)
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill").foregroundStyle(MIMITheme.terracotta)
                    VStack(alignment: .leading, spacing: 3) { Text(favorite.title).font(MIMITheme.displayFont(size: 17, weight: .semibold)); Text("\(favorite.artist ?? "未知演奏者") · \(favorite.category) · \(favorite.key ?? "调性未标注") · 热度 \(favorite.heat.formatted())").font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk) }
                    Spacer()
                    Button(local ? "已在本机收藏" : "迁入本机") { model.migrateRemoteFavorite(favorite) }.buttonStyle(PaperSecondaryButtonStyle()).disabled(local || model.accountBusy)
                    Button("从服务器取消") { model.removeRemoteFavorite(favorite) }.buttonStyle(.bordered).disabled(model.accountBusy)
                }.padding(15).mimiCard(radius: 15, fill: MIMITheme.paperWhite, shadowOpacity: 0.02)
            }
        }.padding(18).mimiCard(radius: 20, fill: MIMITheme.paperWhite, shadowOpacity: 0.025)
    }
    private var creatorPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.remoteUser == nil { accountRequired("登录后查看创作中心。", returnArea: .creator) }
            VStack(alignment: .leading, spacing: 10) {
                PaperSectionTitle(title: "公开投稿已暂停")
                Text("首期提供个人练习和本地曲谱导入。上传与审核 API 会返回“暂未开放”，不会把模拟审核标记为公开成功。之前的投稿记录会保留；此页面不再提供修改或审核入口。")
                    .font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(4)
                HStack(spacing: 9) { Button("前往“我的谱”本地导入") { model.navigate(.library) }.buttonStyle(PaperProminentButtonStyle()); Button("查看数据与备份") { model.navigate(.dataSettings) }.buttonStyle(PaperSecondaryButtonStyle()) }
                Text("历史投稿计数由旧服务页面提供；当前原生快照不伪造服务器计数。若账号服务不可用，请检查错误提示。")
                    .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
            }.padding(32).frame(maxWidth: 576, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
        }
    }
    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { PaperSectionTitle(title: "最近打开", detail: "浏览记录保存在本机个人资料中；这里只显示当前设备的记录。") ; Spacer()
                if let clearedHistory { Button("撤销清空（\(clearedHistory.count) 条）") { restoreHistory(clearedHistory) }.buttonStyle(PaperSecondaryButtonStyle()) }
                else { Button(isClearingHistory ? "正在清空…" : "清空浏览记录", role: .destructive) { clearHistory() }.buttonStyle(.bordered).disabled(isClearingHistory || model.recentEntries.isEmpty) }
            }
            if let historyMessage { PaperNotice(text: historyMessage, error: historyMessage.contains("失败")) }
            if model.recentEntries.isEmpty { Text("本机还没有浏览记录。清空历史后，可在这里撤销恢复刚才清除的记录。")
                .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk).padding(20).frame(maxWidth: .infinity, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
            } else { ForEach(model.recentEntries) { entry in
                HStack(spacing: 12) { Image(systemName: "clock.arrow.circlepath").foregroundStyle(MIMITheme.darkGold); VStack(alignment: .leading, spacing: 3) { Text(entry.title).font(MIMITheme.bodyFont(size: 14, weight: .semibold)); Text("\(entry.artist ?? "") · \(Date(timeIntervalSince1970: entry.time / 1000).formatted(date: .abbreviated, time: .shortened))").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk) }; Spacer(); Button("打开") { if let score = model.personalScores.first(where: { $0.id == entry.id || $0.sourceId == entry.id || $0.id == "catalog:\(entry.id)" }) { model.openPersonalScore(score) } else { model.navigate(.score(id: entry.id.hasPrefix("catalog:") ? String(entry.id.dropFirst("catalog:".count)) : entry.id)) } }.buttonStyle(PaperSecondaryButtonStyle()) }
                    .padding(12).mimiCard(radius: 12, fill: MIMITheme.paperWhite, shadowOpacity: 0.02)
            } }
        }.padding(18).mimiCard(radius: 20, fill: MIMITheme.paperWhite, shadowOpacity: 0.025)
    }
    private var profilePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let user = model.remoteUser {
                HStack(spacing: 15) { Text((user.nickname ?? user.email ?? user.phone ?? "U").prefix(1).uppercased()).font(MIMITheme.displayFont(size: 26, weight: .semibold)).foregroundStyle(MIMITheme.darkGold).frame(width: 64, height: 64).background(Color(hex: 0xF5F0E6), in: Circle()); VStack(alignment: .leading, spacing: 3) { Text(user.nickname ?? "未设置昵称").font(MIMITheme.displayFont(size: 21, weight: .semibold)); Text(user.email ?? user.phone ?? "未绑定手机/邮箱").font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk) }; Spacer(); if model.accountBusy { ProgressView().controlSize(.small) } }
                HStack(spacing: 30) { labeledValue("账号类型", user.email == nil ? "手机账号" : "邮箱账号"); labeledValue("注册时间", user.createdAt ?? "-"); labeledValue("本机资料", "独立保存") }
                Text("退出只清除此服务的会话令牌，不会删除本机个人资料、收藏、练习记录、工程或备份。")
                    .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
            } else { accountRequired("登录后查看个人资料。", returnArea: .profile) }
        }.padding(32).frame(maxWidth: 576, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
    }
    private func accountRequired(_ text: String, returnArea: AccountArea) -> some View {
        VStack(spacing: 11) { Text(text).font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.mutedInk); HStack { Button("去登录") { model.navigate(.login) }.buttonStyle(PaperProminentButtonStyle()); Button("注册") { model.navigate(.register) }.buttonStyle(PaperSecondaryButtonStyle()) } }.frame(maxWidth: .infinity, minHeight: 110)
    }
    private func removeLocalFavorite(_ score: PersonalScore) {
        guard !isRemovingLocalFavorite, let store = model.personalStore else { return }
        isRemovingLocalFavorite = true
        favoritesMessage = nil
        Task { @MainActor in
            defer { isRemovingLocalFavorite = false }
            do {
                try await store.toggleFavorite(score.id)
                favoritesMessageIsError = false
                favoritesMessage = "已从本设备收藏移除。"
                model.personalDataDidChange()
            } catch {
                favoritesMessageIsError = true
                favoritesMessage = "取消收藏失败：\(error.localizedDescription)"
            }
        }
    }
    private func labeledValue(_ label: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 3) { Text(label).font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk); Text(value).font(MIMITheme.bodyFont(size: 12, weight: .medium)) } }
    private func clearHistory() {
        guard let store = model.personalStore else { return }; let old = model.personalSnapshot.history; isClearingHistory = true; historyMessage = nil
        Task { @MainActor in defer { isClearingHistory = false }; do { var data = try await store.snapshot(); data.history = []; _ = try await store.commit(data, expectedRevision: data.revision); clearedHistory = old; historyMessage = "已清空 \(old.count) 条浏览记录；曲谱和练习内容保留。"; model.personalDataDidChange() } catch { historyMessage = "清空失败：\(error.localizedDescription)" } }
    }
    private func restoreHistory(_ old: [PersonalHistoryEntry]) {
        guard let store = model.personalStore else { return }
        Task { @MainActor in do { var data = try await store.snapshot(); data.history = old; _ = try await store.commit(data, expectedRevision: data.revision); clearedHistory = nil; historyMessage = "已恢复清空前的浏览记录。"; model.personalDataDidChange() } catch { historyMessage = "恢复失败：\(error.localizedDescription)" } }
    }
}

private struct DocumentSection: Identifiable {
    let heading: String
    let body: String
    var id: String { heading }
}

struct DocumentPageView: View {
    @EnvironmentObject private var model: AppModel
    let page: DocumentPage

    private var sections: [DocumentSection] {
        switch page {
        case .privacy: return [
            .init(heading: "引言", body: "我们非常重视你的隐私与个人信息保护。本政策说明 MIMI Guitar（下称\"本站\"）在提供服务过程中可能收集的信息、使用方式以及你的相关权利。"),
            .init(heading: "一、我们可能收集的信息", body: "在未登录状态下，本站可以正常浏览与播放全部曲谱，不要求提供任何个人信息。仅当你使用收藏、浏览记录同步、上传等功能时，可能涉及账号信息（邮箱或手机号、昵称、头像）与操作记录（收藏列表、上传记录）。"),
            .init(heading: "二、信息收集的用途及使用规则", body: "我们收集的信息仅用于：提供并优化曲谱浏览与播放服务、保存你的收藏与上传记录、在你请求时与你联系。浏览记录默认保存在你的本地设备（浏览器 localStorage）中，不会上传服务器。原生 Mac 版本的个人资料保存在本机应用支持目录，不会读取浏览器资料。"),
            .init(heading: "三、信息的共享、转让及披露", body: "我们不会出售你的个人信息。除法律法规要求、或为保障本站运行所必需的服务提供商外，我们不会向第三方共享你的个人信息。"),
            .init(heading: "四、我们的信息安全保护", body: "我们采用合理的技术与管理措施保护信息存储安全，包括密码哈希存储、传输加密等。但请注意，任何网络传输与存储方式都无法保证绝对安全。"),
            .init(heading: "五、未成年人信息保护", body: "若你为未成年人，请在监护人指导下使用本站。我们不会主动收集未成年人的个人信息。"),
            .init(heading: "六、免责条款", body: "本站为学习与演示用途的复刻项目，所展示曲谱内容来自公开渠道迁移的演示数据。因使用本站内容产生的任何直接或间接损失，本站不承担相应责任。"),
            .init(heading: "七、本政策的适用范围", body: "本政策适用于本站提供的全部页面与服务。若本站接入第三方服务，其隐私规则以第三方公示为准。"),
            .init(heading: "八、如何联系我们", body: "如对本政策有任何疑问，或希望查询、更正、删除你的个人信息，请通过「联系我们」页面与我们取得联系。"),
        ]
        case .agreement: return [
            .init(heading: "一、服务说明", body: "本站（MIMI Guitar）为「谱全了」guistudy.com 的全站功能复刻学习项目，提供吉他谱与尤克里里谱的浏览、显示、在线播放与上传等服务。注册并使用本站服务，即表示你已阅读、理解并同意本协议的全部条款。"),
            .init(heading: "二、账号与安全", body: "你应妥善保管账号密码，并对其名下账号产生的全部行为负责。若发现账号被他人盗用或存在安全漏洞，请及时通过「联系我们」告知我们。"),
            .init(heading: "三、内容与版权", body: "站内曲谱内容来自公开渠道迁移的演示数据，著作权归原作者与上传者所有。上传者应保证其上传内容不侵犯第三方合法权益；如涉及侵权，我们将在核实后依法处理。"),
            .init(heading: "四、用户行为规范", body: "不得利用本站从事任何违反法律法规或损害他人权益的行为，包括但不限于：上传违法内容、批量抓取数据、攻击服务器、滥用下载或播放接口等。"),
            .init(heading: "五、服务的变更与中断", body: "我们可能根据需要对服务内容、功能进行调整，或对服务进行维护。因维护、升级、不可抗力等原因导致服务中断的，本站不承担由此产生的责任。"),
            .init(heading: "六、免责声明", body: "本站为学习与演示用途的项目，不对内容的准确性、完整性与可用性作出任何明示或默示的保证。因使用本站内容产生的损失，本站不承担相应责任。"),
            .init(heading: "七、协议的修改", body: "我们可能适时修订本协议，修订后的协议将在本站公布。继续使用本站服务即视为接受修订后的协议。"),
            .init(heading: "八、争议解决", body: "因本协议产生的争议，双方应友好协商解决；协商不成的，依法向有管辖权的人民法院提起诉讼。"),
        ]
        case .copyright: return [
            .init(heading: "版权声明", body: "本站（MIMI Guitar）为学习与演示用途的复刻项目。站内曲谱数据来源于对公开网站 guistudy.com（谱全了）热门曲谱子集的迁移，仅用于功能研究、开发学习与非商业演示。曲谱及录音的著作权归原作者、原权利人所有。"),
            .init(heading: "侵权告知", body: "如果你认为本站展示的任何内容侵犯了你的合法权益，请向我们提供以下信息以便核查：权利人的身份证明、被侵权内容的链接与描述、你的联系方式。我们将在核实后尽快处理，包括对相关内容进行下架或标注。"),
            .init(heading: "投诉渠道", body: "请通过「联系我们」页面提交侵权投诉，或直接发送邮件至站内公示的联系邮箱，主题请注明「版权投诉」。"),
            .init(heading: "商用前须知", body: "本站当前为本地开发与学习演示版本。若计划将本项目用于正式商用，必须替换为已获得授权的内容，或与版权方签署相应授权协议；否则由此产生的法律风险由使用者自行承担。"),
        ]
        case .uploadPolicy: return [
            .init(heading: "一、可上传的内容", body: "本站支持上传 Guitar Pro 格式曲谱文件（.gp3 / .gp4 / .gp5 / .gpx / .gp），并自动解析谱面、生成可在线播放的谱面文件与首屏预览图。"),
            .init(heading: "二、上传者声明", body: "上传即表示你声明并保证：你对上传内容拥有相应权利，或已获得权利人的合法授权；上传内容不侵犯任何第三方的著作权、商标权、隐私权等合法权益。"),
            .init(heading: "三、审核机制", body: "上传作品将先进入「审核中」状态，经审核通过后方可公开展示。我们保留拒绝、下架或删除任何不符合本政策内容的权利。"),
            .init(heading: "四、禁止内容", body: "禁止上传以下内容：违法或侵权内容、恶意代码或病毒、批量灌水与重复内容、与音乐谱面无实质关系的内容等。"),
            .init(heading: "五、侵权处理", body: "如权利人认为某上传内容侵犯其权益，可通过「联系我们」页面提交投诉。我们将在核实后下架相关内容，并视情况对上传者账号作出处理。"),
            .init(heading: "六、免责说明", body: "本站为学习与演示用途的复刻项目，上传内容的版权责任由上传者自行承担。因上传内容引发的纠纷，本站不承担相应责任。"),
        ]
        case .help: return [
            .init(heading: "如何查找乐谱", body: "在首页排行榜或「吉他谱」「尤克里里」列表中浏览；也可以使用顶部的筛选（难度、调性、调弦、谱型、排序）缩小范围，或在搜索框输入曲名 / 艺人直接检索。"),
            .init(heading: "如何播放乐谱", body: "进入曲谱详情页，播放器会自动加载谱面。点击播放按钮即可试听，支持变速、节拍器、预备拍、变调夹、循环区间、音轨混音等控制。"),
            .init(heading: "如何打印乐谱", body: "使用播放器的「打印」功能，会重新渲染纯谱面并打开 macOS 打印面板；选择打印机或保存为 PDF。"),
            .init(heading: "如何保存乐谱为 PDF", body: "使用播放器的「PDF」按钮，谱面将按页面导出为 PDF，并通过保存面板选择位置；只有写入成功后才会报告成功。"),
            .init(heading: "乐谱难度如何划分", body: "难度分为零基础、初级、中级、高级、专业五档，对应 1 到 5 级。零基础适合刚接触吉他的新手，专业级通常包含复杂技巧或原版编配。"),
            .init(heading: "为什么有些谱没有难度标注", body: "部分曲谱在上传时未提供难度信息，这类谱在列表中不会显示难度标签，不影响查看与播放。"),
            .init(heading: "下载或播放遇到问题怎么办", body: "请先重试加载本地谱面；若曲库资源缺失，请打开「联系我们」页面查看反馈渠道。原生版本的账号服务需要配置有效地址。"),
        ]
        default: return []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: page == .help ? 32 : 21) {
            PaperPageHeader(eyebrow: eyebrow, title: page.title, subtitle: introductoryText)
            if page == .about { aboutContent }
            else if page == .contact { contactContent }
            else if page == .licenses { licensesContent }
            else { policyContent }
            HStack(spacing: 9) {
                if page != .help { documentButton("帮助中心", .help) }
                if page != .contact { documentButton("联系我们", .contact) }
                if page != .uploadPolicy { documentButton("上传政策", .uploadPolicy) }
                if page != .licenses { documentButton("授权说明", .licenses) }
            }.padding(.top, 4)
        }
        .frame(maxWidth: page == .help ? 768 : 900, alignment: .leading).frame(maxWidth: .infinity, alignment: .top).padding(.top, 9)
    }

    private var eyebrow: String {
        switch page { case .help: return "Help"; case .about: return "About"; case .privacy: return "Privacy"; case .agreement: return "Agreement"; case .copyright: return "Copyright"; case .licenses: return "Licenses"; case .contact: return "Contact"; case .uploadPolicy: return "Upload Policy" }
    }
    private var introductoryText: String {
        switch page {
        case .about: return "MIMI Guitar 是一个吉他与尤克里里专属的乐谱网站：在这里，你可以浏览、搜索海量曲谱，在线查看六线谱与和弦谱，并直接播放试听，跟练自己喜欢的歌曲。原生 Mac 版将个人收藏、练习与备份保存在本机。"
        case .licenses: return "本项目基于多个开源项目构建，以下为本项目依赖的主要开源组件及其许可证。请在使用与分发时遵守相应许可证条款。"
        case .contact: return "欢迎提供播放、下载、搜索问题反馈与功能建议；版权事项请注明「版权」或「商务」。"
        case .uploadPolicy: return "以下保留原站上传政策正文。Mac 原生版本的公开投稿入口维持关闭，本地个人曲谱导入不属于公开投稿。"
        case .privacy: return ""
        case .agreement: return ""
        case .copyright: return ""
        case .help: return ""
        }
    }
    private var policyContent: some View {
        VStack(alignment: .leading, spacing: page == .help ? 24 : 15) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 7) {
                    Text(section.heading).font(MIMITheme.displayFont(size: 20, weight: .semibold)).foregroundStyle(MIMITheme.ink)
                    Text(section.body).font(MIMITheme.bodyFont(size: 14)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                }.padding(page == .help ? 24 : 17).frame(maxWidth: .infinity, alignment: .leading).mimiCard(radius: 17, fill: MIMITheme.paperWhite, shadowOpacity: 0.02)
            }
            if page == .uploadPolicy { PaperNotice(text: "公开曲谱投稿当前暂停。上方原文保留为来源政策说明，不代表原生应用接受或提交投稿。") }
        }
    }
    private var aboutContent: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("本站是「谱全了」（guistudy.com）的功能复刻学习项目，采用其核心的产品形态与交互逻辑，并套用 refero「General Intelligence Company」编辑风设计系统重新落地视觉。项目从零实现了曲谱数据管线、在线播放器、排行榜、筛选排序、搜索、文章等内容。")
                .font(MIMITheme.bodyFont(size: 14)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(6)
            PaperSectionTitle(title: "核心能力")
            ForEach(["吉他谱 / 尤克里里谱：弹唱谱、指弹谱、和弦谱、六线谱", "在线播放：高亮同步、自动滚动、变速、节拍器、变调夹、循环、多音轨混音", "排行与筛选：热门 / 最新榜单，按难度、调性、调弦、谱型筛选", "导出：打印乐谱、生成 PDF 并选择保存位置", "搜索：按曲名 / 艺人检索全站曲谱", "个人资料：本地收藏、待练、导入、练习记录与完整备份"], id: \.self) { item in Label(item, systemImage: "checkmark.circle.fill").font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.bodyInk) }
            PaperSectionTitle(title: "就从今天，踏上你的音乐之旅")
            Text("无论你是零基础新手，还是想要进阶的乐手，这里都有适合你的曲谱。如有任何问题，欢迎通过联系我们与我们沟通。")
                .font(MIMITheme.bodyFont(size: 14)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(5)
        }.padding(21).mimiCard(radius: 19, fill: MIMITheme.paperWhite, shadowOpacity: 0.025)
    }
    private var contactContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 14) {
                contactCard(title: "功能建议 / 问题反馈", body: "在使用过程中遇到播放、下载、搜索等问题，或希望提出新功能建议，欢迎随时联系我们。", email: "support@mimi-guitar.local")
                contactCard(title: "版权与商务", body: "涉及曲谱版权、授权合作等事宜，请通过以下渠道联系，邮件主题请注明「版权」或「商务」。", email: "legal@mimi-guitar.local")
            }
            VStack(alignment: .leading, spacing: 7) { PaperSectionTitle(title: "项目说明"); Text("本项目是「谱全了」guistudy.com 的全站功能复刻学习项目，为本地开发与演示版本。如需部署、商用或数据授权，请通过上方联系方式沟通。")
                    .font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(5) }.padding(19).frame(maxWidth: .infinity, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
        }
    }
    private func contactCard(title: String, body: String, email: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { PaperSectionTitle(title: title); Text(body).font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(4); Button("邮箱：\(email)") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(email, forType: .string); model.presentAlert(title: "邮箱地址已复制", message: email) }.buttonStyle(.plain).font(MIMITheme.bodyFont(size: 11, weight: .semibold)).foregroundStyle(MIMITheme.darkGold) }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
    }
    private var licensesContent: some View {
        let sources: [(String, String, String, String)] = [
            ("Astro", "MIT License", "页面框架与 SSR 服务端渲染", "https://astro.build/"),
            ("Svelte 5", "MIT License", "播放器等交互岛屿组件", "https://svelte.dev/"),
            ("Tailwind CSS v4", "MIT License", "样式与设计系统落地", "https://tailwindcss.com/"),
            ("AlphaTab", "MPL-2.0", "乐谱解析、渲染与播放引擎", "https://alphatab.net/"),
            ("Prisma", "Apache-2.0", "数据库 ORM", "https://www.prisma.io/"),
            ("jsPDF", "MIT License", "谱面 PDF 生成", "https://github.com/parallax/jsPDF"),
            ("Fraunces / Inter 字体", "OFL-1.1", "标题与正文字体（本地自托管）", "https://fonts.google.com/"),
            ("sf2 音源", "演示用途", "按乐器分发的 General MIDI 音源（迁移自原站，商用需替换为授权音源）", "—"),
            ("SONiVOX SoundFont", "随包授权文件", "内置 General MIDI 音源；分发条件以随包授权和 NOTICE 为准", "https://www.sonivoxmi.com/")
        ]
        return VStack(alignment: .leading, spacing: 14) {
            Text(introductoryText).font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(5)
            ForEach(sources, id: \.0) { name, license, role, url in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) { Text(name).font(MIMITheme.bodyFont(size: 14, weight: .semibold)); Text(role).font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk) }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(license).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(MIMITheme.darkGold)
                        if url == "—" {
                            Text("—").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
                        } else {
                            Button("官网") { if let destination = URL(string: url) { NSWorkspace.shared.open(destination) } }.buttonStyle(.plain).font(MIMITheme.bodyFont(size: 10, weight: .medium)).foregroundStyle(MIMITheme.signalBlue)
                        }
                    }
                }.padding(.vertical, 9)
                Divider().overlay(MIMITheme.faintBorder)
            }
            if let resource = Bundle.main.resourceURL {
                VStack(alignment: .leading, spacing: 9) {
                    PaperSectionTitle(title: "随应用附带的许可与来源全文")
                    bundledLicenseButton("AlphaTab MPL-2.0 许可证全文", resource: resource, relativePath: "Player/third-party/alphaTab-MPL-2.0.txt")
                    bundledLicenseButton("AlphaTab 集成依赖清单", resource: resource, relativePath: "Player/third-party/alphaTab-integrated-libraries.txt")
                    bundledLicenseButton("Fraunces OFL-1.1 全文", resource: resource, relativePath: "Design/Fonts/OFL-Fraunces.txt")
                    bundledLicenseButton("Inter OFL-1.1 全文", resource: resource, relativePath: "Design/Fonts/OFL-Inter.txt")
                    bundledLicenseButton("SONiVOX SoundFont 授权全文", resource: resource, relativePath: "Licenses/SONiVOX/LICENSE.txt")
                    bundledLicenseButton("SONiVOX SoundFont NOTICE", resource: resource, relativePath: "Licenses/SONiVOX/NOTICE.md")
                    bundledLicenseButton("SONiVOX SoundFont 来源说明", resource: resource, relativePath: "Licenses/SONiVOX/README-source.md")
                    Text("按钮会从应用包打开实际随附文件；路径缺失时会显示明确提示。许可和 NOTICE 以应用包内原文为准。")
                        .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                }.padding(14).background(MIMITheme.paper, in: RoundedRectangle(cornerRadius: 14))
            }
        }.padding(20).mimiCard(radius: 19, fill: MIMITheme.paperWhite)
    }

    private func bundledLicenseButton(_ title: String, resource: URL, relativePath: String) -> some View {
        Button(title) {
            let file = relativePath.split(separator: "/").reduce(resource) { $0.appendingPathComponent(String($1)) }
            guard FileManager.default.fileExists(atPath: file.path) else {
                model.presentAlert(title: "许可文件未随包提供", message: "应用资源中找不到：\(relativePath)")
                return
            }
            NSWorkspace.shared.open(file)
        }.buttonStyle(PaperSecondaryButtonStyle())
    }
    private func documentButton(_ title: String, _ destination: DocumentPage) -> some View {
        Button(title) { model.navigate(.document(destination)) }.buttonStyle(PaperSecondaryButtonStyle())
    }
}

struct PublicUploadDisabledView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            PaperPageHeader(eyebrow: "Upload · 本地导入", title: "公开投稿已暂停", subtitle: "公开上传与审核仍关闭。原站上传 API 会返回“暂未开放”；本页面不会尝试提交或伪造审核结果。")
            VStack(alignment: .leading, spacing: 12) {
                Label("本地导入仍可使用", systemImage: "square.and.arrow.down.fill").font(MIMITheme.displayFont(size: 20, weight: .semibold)).foregroundStyle(MIMITheme.ink)
                Text("把你有权使用的曲谱导入本机个人资料。原件与可播放副本会分别保存；单个文件最大 30 MiB。导入内容不会公开发布。")
                    .font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(4)
                HStack { Button("导入到我的谱") { model.importScoreWithPanel() }.buttonStyle(PaperProminentButtonStyle()).disabled(model.isImporting); Button("查看数据与备份") { model.navigate(.dataSettings) }.buttonStyle(PaperSecondaryButtonStyle()) }
            }.padding(22).frame(maxWidth: 700, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
            VStack(alignment: .leading, spacing: 7) { PaperSectionTitle(title: "政策与联系"); Text("原站上传政策保留用于说明内容规范，但不表示当前公开投稿入口已经开放。版权投诉与授权问题请查看版权政策和联系我们页面。")
                .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk); HStack { documentButton("查看上传政策", .uploadPolicy); documentButton("版权政策", .copyright); documentButton("联系我们", .contact) } }
                .padding(18).frame(maxWidth: 700, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
        }.frame(maxWidth: 920, alignment: .leading).frame(maxWidth: .infinity, alignment: .top).padding(.top, 9)
    }
    private func documentButton(_ title: String, _ page: DocumentPage) -> some View { Button(title) { model.navigate(.document(page)) }.buttonStyle(PaperSecondaryButtonStyle()) }
}

