import Foundation

/// Bounds the dynamic lists so settings never need a scrolling container.
struct SettingsPagination {
    let count: Int
    let pageSize: Int
    let page: Int

    init(count: Int, pageSize: Int, requestedPage: Int) {
        self.count = max(0, count)
        self.pageSize = max(1, pageSize)
        let lastPage = max(0, (self.count - 1) / self.pageSize)
        self.page = min(max(0, requestedPage), lastPage)
    }

    var pageCount: Int { max(1, (count + pageSize - 1) / pageSize) }
    var range: Range<Int> {
        let start = min(page * pageSize, count)
        return start..<min(start + pageSize, count)
    }
}
