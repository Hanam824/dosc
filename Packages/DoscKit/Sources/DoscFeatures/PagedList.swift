import DoscCore
import Foundation
import Observation

/// An item together with the account it came from.
public struct Sourced<Item: Identifiable & Sendable>: Identifiable, Sendable where Item.ID: Sendable {
    public struct ID: Hashable, Sendable {
        let accountID: UUID
        let itemID: Item.ID
    }

    public let account: Account
    public let item: Item
    public var id: ID { ID(accountID: account.id, itemID: item.id) }
}

/// A paged list filled from one or more accounts at once. Each account keeps its own cursor;
/// pages are merged with `areInOrder` (newest first, usually) so mixed accounts read as one list.
@MainActor @Observable
final class PagedList<Item: Identifiable & Sendable> where Item.ID: Sendable {
    typealias Fetch = @Sendable (PageCursor?) async throws -> Page<Item>

    struct Source {
        let account: Account
        let fetch: Fetch
    }

    enum Phase {
        case idle, loading, loaded
        case failed(String)
    }

    private(set) var items: [Sourced<Item>] = []
    private(set) var phase: Phase = .idle
    /// Accounts whose last load failed while others worked, with the reason.
    private(set) var partialFailures: [String] = []
    private(set) var isLoadingMore = false

    @ObservationIgnored private var sources: [Source] = []
    @ObservationIgnored private var cursors: [UUID: PageCursor] = [:]
    @ObservationIgnored private let areInOrder: ((Item, Item) -> Bool)?

    init(areInOrder: ((Item, Item) -> Bool)? = nil) {
        self.areInOrder = areInOrder
    }

    var hasMore: Bool { !cursors.isEmpty }

    /// Loads the first page from each source, replacing what was there.
    func load(_ sources: [Source]) async {
        self.sources = sources
        if items.isEmpty { phase = .loading }
        let results = await fetchAll(sources.map { ($0, nil) })
        guard !Task.isCancelled else { return }
        cursors = [:]
        var collected: [Sourced<Item>] = []
        var failures: [String] = []
        for (source, result) in results {
            switch result {
            case .success(let page):
                collected += page.items.map { Sourced(account: source.account, item: $0) }
                if let next = page.next { cursors[source.account.id] = next }
            case .failure(let error):
                failures.append("\(source.account.label): \(error.localizedDescription)")
            }
        }
        items = sorted(collected)
        partialFailures = failures
        if !sources.isEmpty && failures.count == sources.count {
            phase = .failed(failures.joined(separator: "\n"))
        } else {
            phase = .loaded
        }
    }

    /// Loads the next page of every source that has one.
    func loadMore() async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let pending = sources.compactMap { s in cursors[s.account.id].map { (s, Optional($0)) } }
        let results = await fetchAll(pending)
        for (source, result) in results {
            switch result {
            case .success(let page):
                items += page.items.map { Sourced(account: source.account, item: $0) }
                cursors[source.account.id] = page.next
            case .failure:
                // Stop paging that account rather than retrying the same page forever.
                cursors[source.account.id] = nil
            }
        }
        items = sorted(items)
    }

    private func sorted(_ list: [Sourced<Item>]) -> [Sourced<Item>] {
        guard let areInOrder, sources.count > 1 else { return list }
        return list.sorted { areInOrder($0.item, $1.item) }
    }

    private func fetchAll(_ requests: [(Source, PageCursor?)]) async -> [(Source, Result<Page<Item>, any Error>)] {
        await withTaskGroup(of: (Int, Result<Page<Item>, any Error>).self) { group in
            for (i, (source, cursor)) in requests.enumerated() {
                let fetch = source.fetch
                group.addTask {
                    do { return (i, .success(try await fetch(cursor))) } catch { return (i, .failure(error)) }
                }
            }
            var out: [(Int, Result<Page<Item>, any Error>)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map { (requests[$0.0].0, $0.1) }
        }
    }
}

/// Loads one value and remembers whether it's loading, loaded or failed.
@MainActor @Observable
final class Loader<Value: Sendable> {
    enum Phase {
        case loading
        case loaded(Value)
        case failed(String)
    }

    private(set) var phase: Phase = .loading

    var value: Value? {
        if case .loaded(let v) = phase { return v }
        return nil
    }

    func load(_ fetch: @Sendable () async throws -> Value) async {
        if value == nil { phase = .loading }
        do {
            let v = try await fetch()
            phase = .loaded(v)
        } catch is CancellationError {
            return
        } catch {
            if value == nil { phase = .failed(error.localizedDescription) }
        }
    }
}
