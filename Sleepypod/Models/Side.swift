import Foundation

enum Side: String, Codable, CaseIterable, Sendable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        }
    }

    var initial: String {
        switch self {
        case .left: "L"
        case .right: "R"
        }
    }
}

enum SideSelection: Equatable, Sendable {
    case left
    case right
    case both

    var sides: [Side] {
        switch self {
        case .left: [.left]
        case .right: [.right]
        case .both: [.left, .right]
        }
    }

    var primarySide: Side {
        switch self {
        case .left, .both: .left
        case .right: .right
        }
    }
}
