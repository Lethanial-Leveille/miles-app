import Foundation

// A row from GET /lists. unchecked is how many items are still to get; a list with
// everything checked off is still listed, at zero.
struct ShoppingList: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let unchecked: Int
}

// A row from GET /lists/{id}/items. A checked item is kept as purchase history, with when.
struct ListItem: Decodable, Identifiable {
    let id: Int
    let text: String
    var checked: Bool
    // Naive local time from the Pi, null while the item is unchecked
    var checkedAt: String?
    let createdAt: String?

    var checkedDate: Date? { ServerDate.parse(checkedAt) }
}
