import Foundation

/// SF Symbol for a Hue room archetype. Zones use a house unless their archetype is specific.
/// (SF Symbols has no chef's hat, so kitchens get a frying pan.)
nonisolated enum RoomIcon {
    static let fallback = "lightbulb"

    static let symbols: [String: String] = [
        "living_room": "sofa", "lounge": "sofa", "man_cave": "sofa",
        "kitchen": "frying.pan", "dining": "fork.knife", "barbecue": "flame",
        "bedroom": "bed.double", "guest_room": "bed.double", "kids_bedroom": "teddybear", "nursery": "teddybear",
        "bathroom": "shower", "toilet": "toilet",
        "office": "display", "computer": "display", "studio": "display",
        "tv": "tv", "recreation": "gamecontroller", "music": "music.note", "reading": "book",
        "gym": "dumbbell", "pool": "figure.pool.swim",
        "hallway": "figure.walk", "staircase": "stairs", "front_door": "door.left.hand.closed",
        "garage": "car", "carport": "car", "driveway": "car",
        "terrace": "sun.max", "balcony": "sun.max", "porch": "sun.max", "garden": "tree",
        "closet": "cabinet", "storage": "cabinet", "laundry_room": "washer",
        "home": "house", "downstairs": "house", "upstairs": "house", "top_floor": "house", "attic": "house",
    ]

    static func symbol(archetype: String, kind: RoomKind) -> String {
        if let s = symbols[archetype] { return s }
        return kind == .zone ? "house" : fallback
    }
}
