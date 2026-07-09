import SwiftUI
import AppKit

// MARK: - Sidebar List View

struct SidebarListView<Item: SidebarItem>: View {
    let items: [Item]
    @Binding var selectedItem: Item?
    let onItemTap: (Item) -> Void
    let contextMenuItems: ((Item) -> [ContextMenuItem])?
    let trailingContent: ((Item) -> AnyView)?

    // Header configuration
    let headerTitle: String?
    let headerControls: AnyView?

    // Customization
    let showIcon: Bool
    let iconColor: Color
    let showCount: Bool

    // Reordering
    let reorderableFromIndex: Int?
    let onReorder: (([Item]) -> Void)?

    // Dropping tracks onto an item (e.g. add dragged tracks to a playlist)
    let onDropTracks: ((Item) -> Void)?

    // Optional multi-selection for bulk actions (e.g. delete several playlists).
    // When provided, ⌘/⇧-click builds this set; a plain click clears it.
    let multiSelection: Binding<Set<UUID>>?

    @State private var hoveredItemID: UUID?
    @State private var draggedItemID: UUID?
    @State private var dropTargetItemID: UUID?
    @State private var trackDropTargetID: UUID?

    init(
        items: [Item],
        selectedItem: Binding<Item?>,
        onItemTap: @escaping (Item) -> Void,
        contextMenuItems: ((Item) -> [ContextMenuItem])? = nil,
        headerTitle: String? = nil,
        headerControls: AnyView? = nil,
        showIcon: Bool = true,
        iconColor: Color = .secondary,
        showCount: Bool = false,
        trailingContent: ((Item) -> AnyView)? = nil,
        reorderableFromIndex: Int? = nil,
        onReorder: (([Item]) -> Void)? = nil,
        onDropTracks: ((Item) -> Void)? = nil,
        multiSelection: Binding<Set<UUID>>? = nil
    ) {
        self.items = items
        self._selectedItem = selectedItem
        self.onItemTap = onItemTap
        self.contextMenuItems = contextMenuItems
        self.headerTitle = headerTitle
        self.headerControls = headerControls
        self.showIcon = showIcon
        self.iconColor = iconColor
        self.showCount = showCount
        self.trailingContent = trailingContent
        self.reorderableFromIndex = reorderableFromIndex
        self.onReorder = onReorder
        self.onDropTracks = onDropTracks
        self.multiSelection = multiSelection
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            if headerTitle != nil || headerControls != nil {
                HStack {
                    if let title = headerTitle {
                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                    }

                    Spacer()

                    if let controls = headerControls {
                        controls
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()
            }

            // Content
            if items.isEmpty {
                emptyView
            } else {
                itemsList
            }
        }
    }

    // MARK: - Items List

    private var itemsList: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 1) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let isDraggable = isItemDraggable(at: index)

                    SidebarItemRow(
                        item: item,
                        isSelected: isRowSelected(item),
                        isHovered: hoveredItemID == item.id,
                        showIcon: showIcon,
                        iconColor: iconColor,
                        trailingContent: trailingContent,
                        onTap: {
                            handleItemTap(item)
                        },
                        onHover: { isHovered in
                            hoveredItemID = isHovered ? item.id : nil
                        }
                    )
                    .overlay(alignment: .top) {
                        if dropTargetItemID == item.id && draggedItemID != item.id && isDraggable {
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(height: 2)
                                .padding(.horizontal, 8)
                        }
                    }
                    .if(isDraggable) { view in
                        view.onDrag {
                            draggedItemID = item.id
                            return NSItemProvider(object: item.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [.text],
                            delegate: SidebarReorderDropDelegate(
                                targetItem: item,
                                targetIndex: index,
                                items: items,
                                reorderableFromIndex: reorderableFromIndex ?? 0,
                                draggedItemID: $draggedItemID,
                                dropTargetItemID: $dropTargetItemID,
                                onReorder: onReorder ?? { _ in }
                            )
                        )
                    }
                    .if(onDropTracks != nil) { view in
                        view
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentColor.opacity(trackDropTargetID == item.id ? 0.25 : 0))
                            )
                            .onDrop(of: [.chapariiTrackList], isTargeted: Binding(
                                get: { trackDropTargetID == item.id },
                                set: { trackDropTargetID = $0 ? item.id : nil }
                            )) { _ in
                                onDropTracks?(item)
                                trackDropTargetID = nil
                                return true
                            }
                    }
                    .contextMenu {
                        if let menuItems = contextMenuItems?(item) {
                            ForEach(Array(menuItems.enumerated()), id: \.offset) { _, menuItem in
                                contextMenuItem(menuItem)
                            }
                        }
                    }
                }

                if isReorderingEnabled {
                    // Drop zone for moving an item to the very bottom (dropping onto the last row
                    // only inserts above it).
                    Color.clear
                        .frame(height: 24)
                        .contentShape(Rectangle())
                        .onDrop(
                            of: [.text],
                            delegate: SidebarEndDropDelegate(
                                items: items,
                                reorderableFromIndex: reorderableFromIndex ?? 0,
                                draggedItemID: $draggedItemID,
                                dropTargetItemID: $dropTargetItemID,
                                onReorder: onReorder ?? { _ in }
                            )
                        )
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .onAppear {
            // Clear leftover drag state so a stale indicator can't leak in from another sidebar.
            draggedItemID = nil
            dropTargetItemID = nil
        }
    }

    // MARK: - Reordering Helpers

    private var isReorderingEnabled: Bool {
        reorderableFromIndex != nil && onReorder != nil
    }

    private func isItemDraggable(at index: Int) -> Bool {
        guard let fromIndex = reorderableFromIndex, onReorder != nil else { return false }
        return index >= fromIndex
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(.gray)

            Text("No Items")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Context Menu Helper

    @ViewBuilder
    private func contextMenuItem(_ item: ContextMenuItem) -> some View {
        ContextMenuItemView(item: item)
    }

    private func handleItemTap(_ item: Item) {
        if let multi = multiSelection {
            let flags = NSEvent.modifierFlags
            if flags.contains(.command) {
                if multi.wrappedValue.contains(item.id) {
                    multi.wrappedValue.remove(item.id)
                } else {
                    multi.wrappedValue.insert(item.id)
                }
                return
            } else if flags.contains(.shift),
                      let anchorID = selectedItem?.id,
                      let a = items.firstIndex(where: { $0.id == anchorID }),
                      let b = items.firstIndex(where: { $0.id == item.id }) {
                let range = a <= b ? a...b : b...a
                multi.wrappedValue = Set(items[range].map { $0.id })
                return
            } else {
                multi.wrappedValue = []   // plain click clears the bulk selection
            }
        }
        selectedItem = item
        onItemTap(item)
    }

    private func isRowSelected(_ item: Item) -> Bool {
        selectedItem?.id == item.id || (multiSelection?.wrappedValue.contains(item.id) ?? false)
    }
}

// MARK: - Reorder Drop Delegate

private struct SidebarReorderDropDelegate<Item: SidebarItem>: DropDelegate {
    let targetItem: Item
    let targetIndex: Int
    let items: [Item]
    let reorderableFromIndex: Int
    @Binding var draggedItemID: UUID?
    @Binding var dropTargetItemID: UUID?
    let onReorder: ([Item]) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedItemID, draggedItemID != targetItem.id else { return }
        dropTargetItemID = targetItem.id
    }

    func dropExited(info: DropInfo) {
        if dropTargetItemID == targetItem.id {
            dropTargetItemID = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard draggedItemID != nil else { return nil }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        // Clear drag state on every exit, including no-op drops, so nothing stays stuck afterward.
        defer {
            draggedItemID = nil
            dropTargetItemID = nil
        }

        guard let draggedID = draggedItemID,
              let fromIndex = items.firstIndex(where: { $0.id == draggedID }),
              fromIndex >= reorderableFromIndex,
              targetIndex >= reorderableFromIndex else {
            return false
        }

        var reordered = items
        let movedItem = reordered.remove(at: fromIndex)

        let toIndex = fromIndex < targetIndex ? targetIndex - 1 : targetIndex
        let clampedIndex = max(reorderableFromIndex, min(toIndex, reordered.count))
        reordered.insert(movedItem, at: clampedIndex)

        onReorder(reordered)
        return true
    }
}

// MARK: - End Drop Delegate

/// Moves the dragged item to the end of the reorderable region (drops below the last row).
private struct SidebarEndDropDelegate<Item: SidebarItem>: DropDelegate {
    let items: [Item]
    let reorderableFromIndex: Int
    @Binding var draggedItemID: UUID?
    @Binding var dropTargetItemID: UUID?
    let onReorder: ([Item]) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard draggedItemID != nil else { return nil }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggedItemID = nil
            dropTargetItemID = nil
        }

        guard let draggedID = draggedItemID,
              let fromIndex = items.firstIndex(where: { $0.id == draggedID }),
              fromIndex >= reorderableFromIndex else {
            return false
        }

        var reordered = items
        let movedItem = reordered.remove(at: fromIndex)
        reordered.append(movedItem)

        onReorder(reordered)
        return true
    }
}

// MARK: - Convenience Extensions

extension SidebarListView where Item == LibrarySidebarItem {
    init(
        filterItems: [LibraryFilterItem],
        filterType: LibraryFilterType,
        totalTracksCount: Int,
        selectedItem: Binding<LibrarySidebarItem?>,
        onItemTap: @escaping (LibrarySidebarItem) -> Void,
        contextMenuItems: ((LibrarySidebarItem) -> [ContextMenuItem])? = nil
    ) {
        // Create items list
        var items: [LibrarySidebarItem] = []

        // Add "All" item first
        let allItem = LibrarySidebarItem(allItemFor: filterType, count: totalTracksCount)
        items.append(allItem)

        // Convert filter items to sidebar items
        let sidebarItems = filterItems.map { LibrarySidebarItem(filterItem: $0) }

        // Separate unknown and regular items
        let unknownItems = sidebarItems.filter { item in
            item.filterName == filterType.unknownPlaceholder ||
            item.title == filterType.unknownPlaceholder
        }
        let regularItems = sidebarItems.filter { item in
            item.filterName != filterType.unknownPlaceholder &&
            item.title != filterType.unknownPlaceholder
        }

        // Add regular items first, then unknown items at the end
        items.append(contentsOf: regularItems)
        items.append(contentsOf: unknownItems)

        self.init(
            items: items,
            selectedItem: selectedItem,
            onItemTap: onItemTap,
            contextMenuItems: contextMenuItems,
            showIcon: true,
            iconColor: .secondary,
            showCount: false
        )
    }
}
