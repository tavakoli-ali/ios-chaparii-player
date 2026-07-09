#if os(macOS)
import SwiftUI


// MARK: - TrackTableOptionsDropdown

struct TrackTableOptionsDropdown: View {
    @Binding var sortOrder: [KeyPathComparator<Track>]
    @Binding var tableRowSize: TableRowSize
    private let playlistID: UUID?
    private let showCustomSort: Bool
    @State private var isCustomSort = false

    init(
        sortOrder: Binding<[KeyPathComparator<Track>]>,
        tableRowSize: Binding<TableRowSize>,
        playlistID: UUID? = nil,
        showCustomSort: Bool = false
    ) {
        self._sortOrder = sortOrder
        self._tableRowSize = tableRowSize
        self.playlistID = playlistID
        self.showCustomSort = showCustomSort
    }

    private var currentSortField: TrackSortField {
        if isCustomSort {
            return .custom
        }
        return TrackSortField.detect(from: sortOrder)
    }

    private var isAscending: Bool {
        TrackSortField.isAscending(from: sortOrder)
    }

    private var canChangeSortOrder: Bool {
        !isCustomSort && TrackSortField.sortFields.contains(currentSortField)
    }

    var body: some View {
        Menu {
            Section("Sort by") {
                ForEach(TrackSortField.sortFields, id: \.self) { field in
                    Toggle(field.displayName, isOn: Binding(
                        get: { currentSortField == field },
                        set: { _ in setSortField(field) }
                    ))
                }

                if showCustomSort {
                    Divider()

                    Toggle(TrackSortField.custom.displayName, isOn: Binding(
                        get: { isCustomSort },
                        set: { _ in setSortField(.custom) }
                    ))
                }
            }

            Divider()

            Section("Sort order") {
                Toggle("Ascending", isOn: Binding(
                    get: { isAscending },
                    set: { _ in setSortAscending(true) }
                ))

                Toggle("Descending", isOn: Binding(
                    get: { !isAscending },
                    set: { _ in setSortAscending(false) }
                ))
            }
            .disabled(!canChangeSortOrder)

            Divider()

            Section("Row size") {
                ForEach([TableRowSize.expanded, TableRowSize.compact], id: \.self) { size in
                    Toggle(size.displayName, isOn: Binding(
                        get: { tableRowSize == size },
                        set: { _ in setRowSize(size) }
                    ))
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: 14)
        .hoverEffect(activeBackgroundColor: Color(NSColor.controlColor))
        .help("Sort and display options")
        .onAppear {
            syncCustomSortState()
        }
        .onChange(of: sortOrder) {
            // When parent updates sortOrder (e.g. playlist switch), re-sync custom state
            syncCustomSortState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .trackTableSortChanged)) { notification in
            if notification.userInfo?["fromTable"] as? Bool == true,
               let newSortOrder = notification.userInfo?["sortOrder"] as? [KeyPathComparator<Track>] {
                sortOrder = newSortOrder
                // Table column header click overrides custom sort
                if isCustomSort {
                    isCustomSort = false
                }
            }
            if let customSort = notification.userInfo?["isCustomSort"] as? Bool {
                isCustomSort = customSort
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .trackTableRowSizeChanged)) { notification in
            if notification.userInfo?["fromTable"] as? Bool == true,
               let newRowSize = notification.userInfo?["rowSize"] as? TableRowSize {
                tableRowSize = newRowSize
            }
        }
    }

    // MARK: - Helper Methods

    private func syncCustomSortState() {
        if let playlistID = playlistID {
            isCustomSort = PlaylistSortManager.shared.getSortField(for: playlistID) == .custom
        } else {
            isCustomSort = false
        }
    }

    private func setSortField(_ field: TrackSortField) {
        let isCustom = field == .custom
        isCustomSort = isCustom

        if let playlistID = playlistID {
            PlaylistSortManager.shared.setSortField(field, for: playlistID)
        }

        let newComparator = field.getComparator(ascending: isAscending)
        let userDefaultsKey = playlistID != nil ? "playlistTableSortOrder" : "trackTableSortOrder"

        NotificationCenter.default.post(
            name: .trackTableSortChanged,
            object: nil,
            userInfo: [
                "sortOrder": [newComparator],
                "userDefaultsKey": userDefaultsKey,
                "isCustomSort": isCustom
            ]
        )
    }

    private func setSortAscending(_ ascending: Bool) {
        let newComparator = currentSortField.getComparator(ascending: ascending)

        let userDefaultsKey = playlistID != nil ? "playlistTableSortOrder" : "trackTableSortOrder"

        if let playlistID = playlistID {
            PlaylistSortManager.shared.setSortAscending(ascending, for: playlistID)
        }

        NotificationCenter.default.post(
            name: .trackTableSortChanged,
            object: nil,
            userInfo: [
                "sortOrder": [newComparator],
                "userDefaultsKey": userDefaultsKey,
                "isCustomSort": false
            ]
        )
    }

    private func setRowSize(_ size: TableRowSize) {
        UserDefaults.standard.set(size.rawValue, forKey: "trackTableRowSize")

        NotificationCenter.default.post(
            name: .trackTableRowSizeChanged,
            object: nil,
            userInfo: ["rowSize": size]
        )
    }
}

#endif
