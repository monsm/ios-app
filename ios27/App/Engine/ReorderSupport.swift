// ReorderSupport.swift —— iOS 27 原生拖拽排序的**差异应用**辅助。
//
// 为什么要有这个文件：
//   iOS 27 的 `reorderable()` / `reorderContainer(for:)` 只把"从哪挪到哪"交给你，
//   **不替你改数据**（Apple 文档明确要求调用方自己应用 `ReorderDifference`）。
//   这段实现取自 SwiftUI 官方示例。
//
// 语义要点（容易写错的地方）：
//   `sources` 是**用户选中的顺序**，不是它们在集合里的当前顺序 ——
//   所以要先按 `sources` 取出来，再从原集合里删掉，最后插到目标位置。
//   如果直接按集合顺序插，多选拖动时顺序会反。
import SwiftUI

extension ReorderDifference where CollectionID == ReorderableSingleCollectionIdentifier {
    func apply<Items>(to items: inout Items)
    where Items: RangeReplaceableCollection,
          Items.Element: Identifiable,
          Items.Element.ID == ItemID {
        let relocated = sources.compactMap { sourceID in
            items.first { $0.id == sourceID }
        }
        let sourceIDs = Set(sources)
        items.removeAll { sourceIDs.contains($0.id) }

        switch destination.position {
        case .before(let followingID):
            let insertionPoint = items.firstIndex { $0.id == followingID } ?? items.endIndex
            items.insert(contentsOf: relocated, at: insertionPoint)
        case .end:
            items.append(contentsOf: relocated)
        }
    }
}
