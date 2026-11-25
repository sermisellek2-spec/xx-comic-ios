import Foundation

/// Transparent multi-member failover wrapper preserving a single primary identity.
public final class FailoverComicSource: ComicSource, @unchecked Sendable {
    private static let viaPrefix = "@via~"
    private static let kanPathRegex = try! NSRegularExpression(pattern: #"^(?:.*/)?kan/(\d+)(?:[/?#].*)?$"#, options: [])
    private static let ehGidRegex = try! NSRegularExpression(pattern: #"^(\d+)-[0-9a-zA-Z]+$"#, options: [])
    private static let filterSynonymGroups: [[String]] = [
        ["连载", "连载中", "連載", "連載中", "ongoing"],
        ["完结", "已完结", "完結", "已完結", "completed"],
        ["日本", "日漫", "jp", "japan"],
        ["韩国", "韩漫", "kr", "korea"],
        ["大陆", "国产", "国漫", "内地", "中国", "cn", "china"],
        ["港台", "tw", "hk"],
        ["欧美", "欧漫", "us", "eu"],
        ["最新", "更新", "按更新", "最近更新"],
        ["最热", "热门", "人气", "点击"],
        ["评分", "好评"]
    ]

    private struct NotFoundOnMemberError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct ViaTarget {
        let memberId: String
        let rawId: String
    }

    public let identitySourceId: String
    public let displayName: String
    public let members: [ScriptComicSource]
    private let routeStore: FailoverRouteStore
    private let contextRegistry: FailoverContextRegistry

    private let stateLock = NSLock()
    private var filterCache: [String: [SourceFilterGroup]] = [:]
    private var internalActiveFilterOwner: ScriptComicSource
    private var internalLastCategoryMember: ScriptComicSource?
    private var hasMoreResults: [String: Bool] = [:]

    public init(
        identitySourceId: String,
        displayName: String,
        members: [ScriptComicSource],
        routeStore: FailoverRouteStore? = nil,
        contextRegistry: FailoverContextRegistry? = nil
    ) {
        precondition(!members.isEmpty, "FailoverComicSource requires at least one member")
        self.identitySourceId = identitySourceId
        self.displayName = displayName.isEmpty ? members[0].name : displayName
        self.members = members
        self.routeStore = routeStore ?? FailoverRouteStore(fileURL: nil)
        self.contextRegistry = contextRegistry ?? FailoverContextRegistry()
        self.internalActiveFilterOwner = members[0]
    }

    public var primaryMember: ScriptComicSource { members[0] }

    public var activeFilterOwner: ScriptComicSource {
        stateLock.lock()
        defer { stateLock.unlock() }
        return internalActiveFilterOwner
    }

    public var lastCategoryMember: ScriptComicSource? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return internalLastCategoryMember
    }

    public var hasBackups: Bool { members.count > 1 }
    public var hasBackupFailover: Bool { hasBackups }

    public static func isFailoverChain(_ source: (any ComicSource)?) -> Bool {
        guard let failover = source as? FailoverComicSource else { return false }
        return failover.hasBackups
    }

    public var id: String { identitySourceId }
    public var name: String { displayName }
    public var domain: String { members[0].domain }
    public var referer: String { members[0].referer }

    public var supportsSearch: Bool {
        members.contains { $0.supportsSearch }
    }

    public var searchRequiresVpn: Bool {
        members.first(where: { $0.supportsSearch })?.searchRequiresVpn ?? false
    }

    public func referer(forUrl url: String) -> String? {
        let ownerId = resolveOwnerMemberIdByUrl(url)
        return findMemberById(ownerId)?.referer ?? members[0].referer
    }

    public func seedFromSummary(_ summary: ComicSummary?) {
        guard let summary, !summary.comicId.isEmpty else { return }
        contextRegistry.recordSummary(identitySourceId: identitySourceId, summary: summary)
    }

    public func seedFromDetail(_ detail: ComicDetail?) {
        guard let detail, !detail.summary.comicId.isEmpty else { return }
        let comicId = detail.summary.comicId
        let via = parseViaTarget(comicId)
        let existing = contextRegistry.findBook(identitySourceId: identitySourceId, canonicalComicId: comicId)
        let hasNoRefs = existing == nil || existing!.referenceChapters.isEmpty
        let hasChapters = !detail.chapters.isEmpty
        let fromCanonicalOrigin = hasNoRefs && (via == nil || hasChapters)
        contextRegistry.recordDetail(
            identitySourceId: identitySourceId,
            canonicalComicId: comicId,
            detail: detail,
            fromNativePrimary: fromCanonicalOrigin
        )
        if hasChapters {
            for ch in detail.chapters where !ch.url.isEmpty {
                let ownerId = resolveOwnerMemberIdByUrl(ch.url, via: via)
                contextRegistry.recordChapter(
                    identitySourceId: identitySourceId,
                    observedUrl: ch.url,
                    canonicalComicId: comicId,
                    ownerMemberId: ownerId,
                    canonicalChapter: ch,
                    ownerRawUrl: ch.url
                )
            }
        }
    }

    public func seedChapter(comicId: String, title: String?, author: String?, chapter: Chapter?) {
        guard !comicId.isEmpty else { return }
        if let title, !title.isEmpty {
            contextRegistry.recordSummary(
                identitySourceId: identitySourceId,
                summary: ComicSummary(
                    sourceId: identitySourceId,
                    comicId: comicId,
                    title: title,
                    coverUrl: "",
                    subtitle: author ?? "",
                    tags: [],
                    latestChapter: ""
                )
            )
        }
        if let chapter, !chapter.url.isEmpty {
            let via = parseViaTarget(comicId)
            let ownerId = resolveOwnerMemberIdByUrl(chapter.url, via: via)
            contextRegistry.recordChapter(
                identitySourceId: identitySourceId,
                observedUrl: chapter.url,
                canonicalComicId: comicId,
                ownerMemberId: ownerId,
                canonicalChapter: chapter,
                ownerRawUrl: chapter.url
            )
        }
    }

    public func resolveOwnerMemberIdByUrl(_ chapterUrl: String) -> String {
        resolveOwnerMemberIdByUrl(chapterUrl, via: nil)
    }

    private func resolveOwnerMemberIdByUrl(_ chapterUrl: String, via: ViaTarget?) -> String {
        if let hostOwner = findMemberForUrlHost(chapterUrl) {
            return hostOwner.id
        }
        if let via, findMemberById(via.memberId) != nil {
            return via.memberId
        }
        return members[0].id
    }

    public func latest(page: Int) async throws -> [ComicSummary] {
        let safePage = max(1, page)
        return try await executeFailover(members) { member in
            let raw = try await member.latest(page: safePage)
            if safePage <= 1 && raw.isEmpty {
                throw RuleError("\(member.name) 最新列表为空")
            }
            return self.rewriteListing(servingMember: member, raw: raw, isSearch: false)
        }
    }

    public func search(keyword: String, page: Int) async throws -> [ComicSummary] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let searchable = members.filter { $0.supportsSearch }
        guard !searchable.isEmpty else { return [] }
        let safePage = max(1, page)
        return try await executeFailover(searchable) { member in
            let raw = try await member.search(keyword: trimmed, page: safePage)
            return self.rewriteListing(servingMember: member, raw: raw, isSearch: true)
        }
    }

    public func hasMoreCategoryPage(_ results: [ComicSummary]) -> Bool {
        let key = Self.resultKey(results)
        stateLock.lock()
        let stored = hasMoreResults[key]
        stateLock.unlock()
        return stored ?? !results.isEmpty
    }

    public func hasMoreSearchPage(_ results: [ComicSummary]) -> Bool {
        hasMoreCategoryPage(results)
    }

    public func filterGroups() async throws -> [SourceFilterGroup] {
        try await executeFailover(members) { member in
            let groups = try await member.filterGroups()
            self.stateLock.lock()
            self.filterCache[member.id] = groups
            self.internalActiveFilterOwner = member
            self.stateLock.unlock()
            return groups
        }
    }

    public func filterGroupsForSelection(_ selection: [String: String]) -> [SourceFilterGroup] {
        activeFilterOwner.filterGroupsForSelection(selection)
    }

    public func dependentFilterKeys(_ changedKey: String) -> [String] {
        activeFilterOwner.dependentFilterKeys(changedKey)
    }

    public func category(filters: [String: String], page: Int) async throws -> [ComicSummary] {
        let safePage = max(1, page)
        let owner = activeFilterOwner
        let defaultFilter = Self.isDefaultFilter(filters)
        let order = orderWithPreferredFirst(owner)
        return try await executeFailover(order) { member in
            let effectiveFilters = try await self.translateFiltersForMember(owner: owner, target: member, filters: filters)
            let raw = try await member.category(filters: effectiveFilters, page: safePage)
            if safePage <= 1 && defaultFilter && raw.isEmpty {
                throw RuleError("\(member.name) 分类列表为空")
            }
            self.stateLock.lock()
            self.internalLastCategoryMember = member
            self.stateLock.unlock()
            return self.rewriteListing(servingMember: member, raw: raw, isSearch: false)
        }
    }

    public func detail(comicId: String) async throws -> ComicDetail {
        let via = parseViaTarget(comicId)
        let bookCtx = contextRegistry.findBook(identitySourceId: identitySourceId, canonicalComicId: comicId)
        let order = buildComicOrder(via: via, bookCtx: bookCtx)
        let originMemberId = via?.memberId ?? members[0].id

        return try await executeFailover(order) { member in
            let memberRawId = try await self.resolveMemberRawId(
                canonicalComicId: comicId,
                via: via,
                bookCtx: bookCtx,
                target: member
            )
            let memberFullId = "\(member.id):\(memberRawId)"
            let rawDetail = try await member.detail(comicId: memberFullId)
            let latest = !rawDetail.latestChapter.isEmpty
                ? rawDetail.latestChapter
                : (rawDetail.summary.latestChapter ?? "")
            let rewrittenSummary = ComicSummary(
                sourceId: self.identitySourceId,
                comicId: comicId,
                title: rawDetail.summary.title,
                coverUrl: rawDetail.summary.coverUrl,
                subtitle: rawDetail.summary.subtitle,
                tags: rawDetail.summary.tags,
                latestChapter: rawDetail.summary.latestChapter
            )
            let isOrigin = (member.id == originMemberId)
            let alignedChapters = self.processMemberChapters(
                canonicalComicId: comicId,
                member: member,
                rawChapters: rawDetail.chapters,
                isOrigin: isOrigin,
                bookCtx: bookCtx
            )
            let rewritten = ComicDetail(
                summary: rewrittenSummary,
                author: rawDetail.author,
                status: rawDetail.status,
                description: rawDetail.description,
                latestChapter: latest,
                chapters: alignedChapters
            )
            self.contextRegistry.recordDetail(
                identitySourceId: self.identitySourceId,
                canonicalComicId: comicId,
                detail: rewritten,
                fromNativePrimary: isOrigin
            )
            return rewritten
        }
    }

    public func chapters(comicId: String) async throws -> [Chapter] {
        let via = parseViaTarget(comicId)
        let bookCtx = contextRegistry.findBook(identitySourceId: identitySourceId, canonicalComicId: comicId)
        let order = buildComicOrder(via: via, bookCtx: bookCtx)
        let originMemberId = via?.memberId ?? members[0].id

        return try await executeFailover(order) { member in
            let memberRawId = try await self.resolveMemberRawId(
                canonicalComicId: comicId,
                via: via,
                bookCtx: bookCtx,
                target: member
            )
            let memberFullId = "\(member.id):\(memberRawId)"
            let rawChapters = try await member.chapters(comicId: memberFullId)
            if rawChapters.isEmpty {
                throw RuleError("\(member.name) 目录为空")
            }
            let isOrigin = (member.id == originMemberId)
            let aligned = self.processMemberChapters(
                canonicalComicId: comicId,
                member: member,
                rawChapters: rawChapters,
                isOrigin: isOrigin,
                bookCtx: bookCtx
            )
            self.contextRegistry.recordChapters(
                identitySourceId: self.identitySourceId,
                canonicalComicId: comicId,
                list: aligned,
                fromNativePrimary: isOrigin
            )
            return aligned
        }
    }

    public func chapter(url chapterUrl: String) async throws -> ChapterPage {
        if let chCtx = contextRegistry.findChapter(identitySourceId: identitySourceId, chapterUrl: chapterUrl) {
            let owner = findMemberById(chCtx.ownerMemberId)
            let order = orderWithPreferredFirst(owner)
            return try await executeFailover(order) { member in
                let targetUrl: String
                if member.id == chCtx.ownerMemberId {
                    targetUrl = chCtx.ownerRawUrl
                } else {
                    guard let matched = try await self.resolveChapterOnMember(
                        canonicalComicId: chCtx.comicId,
                        targetChapter: chCtx.canonicalChapter,
                        targetMember: member
                    ) else {
                        throw NotFoundOnMemberError(message: "\(member.name) 未收录该章节")
                    }
                    targetUrl = matched.url
                }
                let page = try await member.chapter(url: targetUrl)
                if page.imageUrls.isEmpty {
                    throw RuleError("\(member.name) 正文为空")
                }
                if !page.nextPageUrl.isEmpty {
                    self.contextRegistry.recordChapter(
                        identitySourceId: self.identitySourceId,
                        observedUrl: page.nextPageUrl,
                        canonicalComicId: chCtx.comicId,
                        ownerMemberId: member.id,
                        canonicalChapter: chCtx.canonicalChapter,
                        ownerRawUrl: page.nextPageUrl
                    )
                }
                return ChapterPage(
                    chapterId: chapterUrl,
                    title: page.title,
                    nextPageUrl: page.nextPageUrl,
                    imageUrls: page.imageUrls
                )
            }
        }

        if let hostOwner = findMemberForUrlHost(chapterUrl) {
            return try await executeSingleMember(hostOwner) {
                try await hostOwner.chapter(url: chapterUrl)
            }
        }

        return try await executeFailover(members) { member in
            let page = try await member.chapter(url: chapterUrl)
            if page.imageUrls.isEmpty {
                throw RuleError("\(member.name) 正文为空")
            }
            return page
        }
    }

    public func healthCheck() async -> Bool {
        for m in orderByHealth(members) {
            if Self.isHealthCheckCancelled() { return false }
            if await m.healthCheck() {
                contextRegistry.markHealthy(m.id)
                return true
            }
            if Self.isHealthCheckCancelled() { return false }
            contextRegistry.markUnhealthy(m.id)
        }
        return false
    }

    private static func isHealthCheckCancelled() -> Bool {
        if Task.isCancelled { return true }
        return RuleCancelToken.current?.isCancelled == true
    }

    private func executeFailover<T>(
        _ candidates: [ScriptComicSource],
        action: (ScriptComicSource) async throws -> T
    ) async throws -> T {
        if Task.isCancelled || RuleCancelToken.current?.isCancelled == true {
            throw CancellationError()
        }
        var healthy = [ScriptComicSource]()
        var cooledDown = [ScriptComicSource]()
        for member in candidates {
            if contextRegistry.isHealthy(member.id) {
                healthy.append(member)
            } else {
                cooledDown.append(member)
            }
        }

        var lastFailure: Error?
        var notFound: NotFoundOnMemberError?

        for member in healthy + cooledDown {
            if Task.isCancelled || RuleCancelToken.current?.isCancelled == true {
                throw CancellationError()
            }
            do {
                let result = try await action(member)
                contextRegistry.markHealthy(member.id)
                return result
            } catch let missing as NotFoundOnMemberError {
                notFound = missing
            } catch {
                try Self.rethrowIfCancelled(error)
                contextRegistry.markUnhealthy(member.id)
                lastFailure = error
            }
        }

        if let lastFailure { throw lastFailure }
        if let notFound, !notFound.message.isEmpty {
            throw RuleError(notFound.message)
        }
        throw RuleError("\(displayName) 暂无可用源")
    }

    private func executeSingleMember<T>(
        _ member: ScriptComicSource,
        call: () async throws -> T
    ) async throws -> T {
        if Task.isCancelled || RuleCancelToken.current?.isCancelled == true {
            throw CancellationError()
        }
        do {
            let result = try await call()
            contextRegistry.markHealthy(member.id)
            return result
        } catch {
            try Self.rethrowIfCancelled(error)
            contextRegistry.markUnhealthy(member.id)
            throw error
        }
    }

    private func rewriteListing(
        servingMember: ScriptComicSource,
        raw: [ComicSummary],
        isSearch: Bool
    ) -> [ComicSummary] {
        let more = isSearch ? servingMember.hasMoreSearchPage(raw) : servingMember.hasMoreCategoryPage(raw)
        let anchor = members[0]
        var out = [ComicSummary]()
        out.reserveCapacity(raw.count)
        for item in raw {
            let servingRawId = Self.extractRawId(memberId: servingMember.id, fullOrRawId: item.comicId)
            let canonicalComicId = toCanonicalComicId(
                servingMember: servingMember,
                servingRawId: servingRawId,
                anchor: anchor
            )
            let rewritten = ComicSummary(
                sourceId: identitySourceId,
                comicId: canonicalComicId,
                title: item.title,
                coverUrl: item.coverUrl,
                subtitle: item.subtitle,
                tags: item.tags,
                latestChapter: item.latestChapter
            )
            contextRegistry.recordSummary(identitySourceId: identitySourceId, summary: rewritten)
            out.append(rewritten)
        }
        let key = Self.resultKey(out)
        stateLock.lock()
        if hasMoreResults.count >= 256 {
            hasMoreResults.removeAll(keepingCapacity: true)
        }
        hasMoreResults[key] = more
        stateLock.unlock()
        return out
    }

    private func toCanonicalComicId(
        servingMember: ScriptComicSource,
        servingRawId: String,
        anchor: ScriptComicSource
    ) -> String {
        if servingMember.id == identitySourceId {
            return "\(identitySourceId):\(servingRawId)"
        }
        if let mapped = Self.mapDeterministic(from: servingMember, fromRawId: servingRawId, to: anchor) {
            return "\(identitySourceId):\(mapped)"
        }
        if let cached = routeStore.findCanonicalComicId(memberId: servingMember.id, memberRawId: servingRawId),
           cached.hasPrefix(identitySourceId + ":") {
            return cached
        }
        return "\(identitySourceId):\(Self.viaPrefix)\(servingMember.id)~\(servingRawId)"
    }

    private func processMemberChapters(
        canonicalComicId: String,
        member: ScriptComicSource,
        rawChapters: [Chapter],
        isOrigin: Bool,
        bookCtx: FailoverContextRegistry.BookContext?
    ) -> [Chapter] {
        guard !rawChapters.isEmpty else { return [] }
        contextRegistry.putMemberChapters(
            identitySourceId: identitySourceId,
            canonicalComicId: canonicalComicId,
            memberId: member.id,
            list: rawChapters
        )
        let references = bookCtx?.referenceChapters ?? []
        let aligned = (isOrigin || references.isEmpty)
            ? rawChapters
            : FailoverChapterAligner.alignChapters(references: references, candidates: rawChapters)
        for i in 0..<aligned.count {
            let alignedCh = aligned[i]
            let rawCh = rawChapters[i]
            contextRegistry.recordChapter(
                identitySourceId: identitySourceId,
                observedUrl: alignedCh.url,
                canonicalComicId: canonicalComicId,
                ownerMemberId: member.id,
                canonicalChapter: alignedCh,
                ownerRawUrl: rawCh.url
            )
        }
        return aligned
    }

    private func resolveChapterOnMember(
        canonicalComicId: String,
        targetChapter: Chapter?,
        targetMember: ScriptComicSource
    ) async throws -> Chapter? {
        guard let targetChapter else {
            throw NotFoundOnMemberError(message: "缺少目标章节信息")
        }
        if let cached = contextRegistry.getMemberChapters(
            identitySourceId: identitySourceId,
            canonicalComicId: canonicalComicId,
            memberId: targetMember.id
        ) {
            if let match = FailoverChapterAligner.findMatchingChapter(target: targetChapter, candidates: cached) {
                return match
            }
        }
        let via = parseViaTarget(canonicalComicId)
        let bookCtx = contextRegistry.findBook(identitySourceId: identitySourceId, canonicalComicId: canonicalComicId)
        let rawId = try await resolveMemberRawId(
            canonicalComicId: canonicalComicId,
            via: via,
            bookCtx: bookCtx,
            target: targetMember
        )
        let fresh = try await targetMember.chapters(comicId: "\(targetMember.id):\(rawId)")
        if fresh.isEmpty {
            throw RuleError("\(targetMember.name) 目录为空")
        }
        contextRegistry.putMemberChapters(
            identitySourceId: identitySourceId,
            canonicalComicId: canonicalComicId,
            memberId: targetMember.id,
            list: fresh
        )
        return FailoverChapterAligner.findMatchingChapter(target: targetChapter, candidates: fresh)
    }

    private func buildComicOrder(
        via: ViaTarget?,
        bookCtx: FailoverContextRegistry.BookContext?
    ) -> [ScriptComicSource] {
        guard let via else { return members }
        var ordered = [ScriptComicSource]()
        let primary = members[0]
        let origin = findMemberById(via.memberId)
        let tryPrimaryFirst = primary.id != via.memberId
            && contextRegistry.isHealthy(primary.id)
            && primary.supportsSearch
            && bookCtx != nil
            && !(bookCtx?.title.isEmpty ?? true)
        if tryPrimaryFirst {
            ordered.append(primary)
        }
        if let origin, !ordered.contains(where: { $0.id == origin.id }) {
            ordered.append(origin)
        }
        for m in members where !ordered.contains(where: { $0.id == m.id }) {
            ordered.append(m)
        }
        return ordered
    }

    private func resolveMemberRawId(
        canonicalComicId: String,
        via: ViaTarget?,
        bookCtx: FailoverContextRegistry.BookContext?,
        target: ScriptComicSource
    ) async throws -> String {
        if let via {
            if target.id == via.memberId { return via.rawId }
            if let cached = routeStore.findMemberRawId(canonicalComicId, memberId: target.id), !cached.isEmpty {
                return cached
            }
            if let origin = findMemberById(via.memberId),
               let deterministic = Self.mapDeterministic(from: origin, fromRawId: via.rawId, to: target) {
                return deterministic
            }
            return try await resolveByTitleMatch(canonicalComicId: canonicalComicId, bookCtx: bookCtx, target: target)
        }

        let owner = members[0]
        let ownerRawId = Self.extractRawId(memberId: identitySourceId, fullOrRawId: canonicalComicId)
        if target.id == owner.id { return ownerRawId }

        if let cached = routeStore.findMemberRawId(canonicalComicId, memberId: target.id), !cached.isEmpty {
            return cached
        }
        if let deterministic = Self.mapDeterministic(from: owner, fromRawId: ownerRawId, to: target) {
            return deterministic
        }
        return try await resolveByTitleMatch(canonicalComicId: canonicalComicId, bookCtx: bookCtx, target: target)
    }

    private func resolveByTitleMatch(
        canonicalComicId: String,
        bookCtx: FailoverContextRegistry.BookContext?,
        target: ScriptComicSource
    ) async throws -> String {
        guard let bookCtx, !bookCtx.title.isEmpty else {
            throw NotFoundOnMemberError(message: "\(target.name) 缺少匹配作品标题")
        }
        let useFeed = (target.rule.fallbackMode == "feed") || !target.supportsSearch
        var candidates = [ComicSummary]()
        if useFeed {
            candidates.append(contentsOf: try await target.latest(page: 1))
            if Self.pickBestMatch(candidates: candidates, ctx: bookCtx) == nil {
                do {
                    candidates.append(contentsOf: try await target.latest(page: 2))
                } catch {
                    try Self.rethrowIfCancelled(error)
                }
            }
        } else {
            let cleanQuery = FailoverChapterAligner.stripTitleTags(bookCtx.title)
            candidates.append(contentsOf: try await target.search(keyword: cleanQuery, page: 1))
            let trimmedTitle = bookCtx.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.pickBestMatch(candidates: candidates, ctx: bookCtx) == nil && cleanQuery != trimmedTitle {
                candidates.append(contentsOf: try await target.search(keyword: trimmedTitle, page: 1))
            }
        }

        guard let matched = Self.pickBestMatch(candidates: candidates, ctx: bookCtx) else {
            throw NotFoundOnMemberError(message: "\(target.name) 未找到同名作品")
        }
        let rawId = Self.extractRawId(memberId: target.id, fullOrRawId: matched.comicId)
        routeStore.saveRoute(comicId: canonicalComicId, memberId: target.id, memberRawId: rawId)
        return rawId
    }

    private static func pickBestMatch(
        candidates: [ComicSummary],
        ctx: FailoverContextRegistry.BookContext
    ) -> ComicSummary? {
        var best: ComicSummary?
        var bestRank = -1
        for cand in candidates {
            let titleScore = FailoverChapterAligner.titleMatchScore(candidateTitle: cand.title, targetTitle: ctx.title)
            if titleScore < 9500 { continue }
            var rank = titleScore
            if !ctx.author.isEmpty && !cand.subtitle.isEmpty {
                let lowerAuthor = ctx.author.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let lowerSub = cand.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if FailoverChapterAligner.titleMatchScore(candidateTitle: cand.subtitle, targetTitle: ctx.author) >= 9500
                    || lowerSub.contains(lowerAuthor)
                    || lowerAuthor.contains(lowerSub) {
                    rank += 200
                }
            }
            if !ctx.latestChapter.isEmpty, let candLatest = cand.latestChapter, !candLatest.isEmpty {
                let targetKey = FailoverChapterAligner.extractChapterKey(ctx.latestChapter)
                let candKey = FailoverChapterAligner.extractChapterKey(candLatest)
                if (!targetKey.isEmpty && targetKey == candKey)
                    || FailoverChapterAligner.titleMatchScore(candidateTitle: candLatest, targetTitle: ctx.latestChapter) >= 9500 {
                    rank += 100
                }
            }
            if rank > bestRank {
                bestRank = rank
                best = cand
            }
        }
        return best
    }

    public static func mapDeterministic(
        from: ScriptComicSource?,
        fromRawId: String,
        to: ScriptComicSource?
    ) -> String? {
        guard let from, let to, !fromRawId.isEmpty else { return nil }
        if from.id == to.id { return fromRawId }

        // Direct Primary -> Backup relation
        if !from.rule.isFallback && to.rule.fallbackOf == from.id {
            return applyForwardMode(mode: to.rule.fallbackMode, primaryRawId: fromRawId)
        }

        // Reverse Backup -> Primary relation
        if from.rule.isFallback && from.rule.fallbackOf == to.id {
            return applyReverseMode(mode: from.rule.fallbackMode, backupRawId: fromRawId)
        }

        // Sibling backups of the same primary
        if from.rule.isFallback && from.rule.fallbackOf == to.rule.fallbackOf {
            let mode = from.rule.fallbackMode
            if mode == to.rule.fallbackMode && (mode == "sameId" || mode == "kanId" || mode == "ehGid") {
                return fromRawId
            }
            if let primaryRaw = applyReverseMode(mode: mode, backupRawId: fromRawId) {
                return applyForwardMode(mode: to.rule.fallbackMode, primaryRawId: primaryRaw)
            }
        }
        return nil
    }

    private static func applyForwardMode(mode: String, primaryRawId: String) -> String? {
        switch mode {
        case "sameId":
            return primaryRawId
        case "kanId":
            if let match = firstGroup(kanPathRegex, in: primaryRawId) {
                return match
            }
            return primaryRawId.range(of: #"^\d+$"#, options: .regularExpression) != nil ? primaryRawId : nil
        case "ehGid":
            return firstGroup(ehGidRegex, in: primaryRawId)
        default:
            return nil
        }
    }

    private static func applyReverseMode(mode: String, backupRawId: String) -> String? {
        switch mode {
        case "sameId":
            return backupRawId
        case "kanId":
            if backupRawId.range(of: #"^\d+$"#, options: .regularExpression) != nil {
                return "/kan/" + backupRawId
            }
            return firstGroup(kanPathRegex, in: backupRawId) != nil ? backupRawId : nil
        default:
            return nil
        }
    }

    private static func firstGroup(_ regex: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let gRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[gRange])
    }

    private func translateFiltersForMember(
        owner: ScriptComicSource,
        target: ScriptComicSource,
        filters: [String: String]
    ) async throws -> [String: String] {
        if filters.isEmpty || Self.isDefaultFilter(filters) {
            return filters
        }
        if owner.id == target.id { return filters }

        var sourceGroups: [SourceFilterGroup]
        do {
            sourceGroups = try await getOrLoadFilterGroups(owner)
        } catch {
            try Self.rethrowIfCancelled(error)
            contextRegistry.markUnhealthy(owner.id)
            sourceGroups = []
        }
        let targetGroups = try await getOrLoadFilterGroups(target)
        if targetGroups.isEmpty { return [:] }
        if !sourceGroups.isEmpty && Self.schemasMatch(sourceGroups, targetGroups) {
            return filters
        }

        var translated = [String: String]()
        for (srcKey, srcVal) in filters {
            if srcVal.isEmpty || srcVal == "all" { continue }
            var srcLabel = Self.findOptionLabel(groups: sourceGroups, key: srcKey, value: srcVal)
            if srcLabel.isEmpty { srcLabel = srcVal }
            if let match = Self.findMatchingFilterOption(targetGroups: targetGroups, preferredKey: srcKey, srcLabel: srcLabel) {
                translated[match.key] = match.value
            }
        }
        return translated
    }

    private func getOrLoadFilterGroups(_ member: ScriptComicSource) async throws -> [SourceFilterGroup] {
        stateLock.lock()
        let cached = filterCache[member.id]
        stateLock.unlock()
        if let cached { return cached }
        let loaded = try await member.filterGroups()
        stateLock.lock()
        filterCache[member.id] = loaded
        stateLock.unlock()
        return loaded
    }

    private static func schemasMatch(_ a: [SourceFilterGroup], _ b: [SourceFilterGroup]) -> Bool {
        guard a.count == b.count else { return false }
        for i in 0..<a.count {
            let ga = a[i]
            let gb = b[i]
            if ga.key != gb.key || ga.options.count != gb.options.count { return false }
            for j in 0..<ga.options.count {
                if ga.options[j].value != gb.options[j].value { return false }
            }
        }
        return true
    }

    private static func findOptionLabel(groups: [SourceFilterGroup], key: String, value: String) -> String {
        for g in groups where g.key == key {
            for o in g.options where o.value == value {
                return o.label
            }
        }
        return ""
    }

    private static func findMatchingFilterOption(
        targetGroups: [SourceFilterGroup],
        preferredKey: String,
        srcLabel: String
    ) -> (key: String, value: String)? {
        let normSrc = normalizeFilterLabel(srcLabel)
        for g in targetGroups where g.key == preferredKey {
            if let found = matchOptionInGroup(g, normSrc: normSrc) {
                return (g.key, found.value)
            }
        }
        for g in targetGroups {
            if let found = matchOptionInGroup(g, normSrc: normSrc) {
                return (g.key, found.value)
            }
        }
        return nil
    }

    private static func matchOptionInGroup(_ g: SourceFilterGroup, normSrc: String) -> SourceFilterOption? {
        for o in g.options where o.value != "all" {
            let normLabel = normalizeFilterLabel(o.label)
            let normValue = normalizeFilterLabel(o.value)
            if normLabel == normSrc
                || normValue == normSrc
                || areFilterSynonyms(normSrc, normLabel)
                || areFilterSynonyms(normSrc, normValue) {
                return o
            }
        }
        return nil
    }

    private static func areFilterSynonyms(_ a: String, _ b: String) -> Bool {
        for group in filterSynonymGroups {
            if group.contains(a) && group.contains(b) { return true }
        }
        return false
    }

    private static func normalizeFilterLabel(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isDefaultFilter(_ filters: [String: String]) -> Bool {
        for val in filters.values where !val.isEmpty && val != "all" {
            return false
        }
        return true
    }

    private func parseViaTarget(_ canonicalComicId: String) -> ViaTarget? {
        guard !canonicalComicId.isEmpty else { return nil }
        let marker = ":" + Self.viaPrefix
        guard let markerRange = canonicalComicId.range(of: marker) else { return nil }
        let rest = String(canonicalComicId[markerRange.upperBound...])
        guard let tilde = rest.firstIndex(of: "~"),
              tilde > rest.startIndex,
              rest.index(after: tilde) < rest.endIndex else {
            return nil
        }
        let backupId = String(rest[..<tilde])
        let rawId = String(rest[rest.index(after: tilde)...])
        guard backupId.range(of: #"^[a-z][a-z0-9_]{1,63}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return ViaTarget(memberId: backupId, rawId: rawId)
    }

    private static func extractRawId(memberId: String, fullOrRawId: String) -> String {
        let prefix = memberId + ":"
        return fullOrRawId.hasPrefix(prefix) ? String(fullOrRawId.dropFirst(prefix.count)) : fullOrRawId
    }

    private func findMemberById(_ memberId: String) -> ScriptComicSource? {
        guard !memberId.isEmpty else { return nil }
        return members.first { $0.id == memberId }
    }

    private func findMemberForUrlHost(_ url: String) -> ScriptComicSource? {
        guard !url.isEmpty,
              let clean = url.components(separatedBy: "#").first,
              let parsed = URL(string: clean),
              let host = parsed.host, !host.isEmpty else {
            return nil
        }
        if let exact = members.first(where: { $0.domain.caseInsensitiveCompare(host) == .orderedSame }) {
            return exact
        }
        return members.first(where: { $0.rule.allows(host) })
    }

    private func orderWithPreferredFirst(_ preferred: ScriptComicSource?) -> [ScriptComicSource] {
        guard let preferred else { return members }
        var order = [preferred]
        for m in members where !order.contains(where: { $0.id == m.id }) {
            order.append(m)
        }
        return order
    }

    private func orderByHealth(_ list: [ScriptComicSource]) -> [ScriptComicSource] {
        var healthy = [ScriptComicSource]()
        var cooled = [ScriptComicSource]()
        for m in list {
            if contextRegistry.isHealthy(m.id) {
                healthy.append(m)
            } else {
                cooled.append(m)
            }
        }
        return healthy + cooled
    }

    private static func rethrowIfCancelled(_ error: Error) throws {
        if Task.isCancelled || RuleCancelToken.current?.isCancelled == true {
            throw error
        }
        if error is CancellationError || error is RuleCancelledError {
            throw error
        }
        if let urlError = error as? URLError {
            if urlError.code == .cancelled {
                throw error
            }
            if urlError.code == .timedOut {
                return
            }
        }
        #if canImport(ObjectiveC)
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            throw error
        }
        let lower = error.localizedDescription.lowercased()
        #else
        let lower = ((error as? LocalizedError)?.errorDescription ?? String(describing: error)).lowercased()
        #endif
        if lower.contains("timeout") || lower.contains("timed out") || lower.contains("超时") {
            return
        }
        if lower.contains("已取消") || lower.contains("规则调用已取消") || lower.contains("interrupt") {
            throw error
        }
    }

    private static func resultKey(_ items: [ComicSummary]) -> String {
        items.map(\.comicId).joined(separator: ",")
    }
}
