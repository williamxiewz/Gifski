import SwiftUI

enum CropHandlePosition: CaseIterable {
	case top
	case topRight
	case right
	case bottomRight
	case bottom
	case bottomLeft
	case left
	case topLeft
	case center

	var location: UnitPoint {
		sides.location
	}

	var isVerticalOnlyHandle: Bool {
		sides.isVerticalOnlyHandle
	}

	var isLeft: Bool {
		sides.isLeft
	}

	var isRight: Bool {
		sides.isRight
	}

	var isTop: Bool {
		sides.isTop
	}

	var isBottom: Bool {
		sides.isBottom
	}

	var isCorner: Bool {
		switch self {
		case .topLeft, .topRight, .bottomLeft, .bottomRight:
			true
		case .bottom, .top, .left, .right, .center:
			false
		}
	}

	var isEdge: Bool {
		switch self {
		case .top, .left, .right, .bottom:
			true
		case .topLeft, .topRight, .bottomLeft, .bottomRight, .center:
			false
		}
	}

	var sides: RectSides {
		switch self {
		case .top:
			.init(horizontal: .center, vertical: .primary)
		case .topRight:
			.init(horizontal: .secondary, vertical: .primary)
		case .right:
			.init(horizontal: .secondary, vertical: .center)
		case .bottomRight:
			.init(horizontal: .secondary, vertical: .secondary)
		case .bottom:
			.init(horizontal: .center, vertical: .secondary)
		case .bottomLeft:
			.init(horizontal: .primary, vertical: .secondary)
		case .left:
			.init(horizontal: .primary, vertical: .center)
		case .topLeft:
			.init(horizontal: .primary, vertical: .primary)
		case .center:
			.init(horizontal: .center, vertical: .center)
		}
	}

	private var frameResizePosition: FrameResizePosition {
		switch self {
		case .top:
			.top
		case .topRight:
			.topTrailing
		case .right:
			.trailing
		case .bottomRight:
			.bottomTrailing
		case .bottom:
			.bottom
		case .bottomLeft:
			.bottomLeading
		case .left:
			.leading
		case .topLeft:
			.topLeading
		case .center:
			.top // Unused since center uses grabIdle style instead.
		}
	}

	var pointerStyle: PointerStyle {
		if self == .center {
			return .grabIdle
		}

		return .frameResize(position: frameResizePosition)
	}
}

struct RectSides: Equatable, Hashable {
	let horizontal: Side
	let vertical: Side

	var isVerticalOnlyHandle: Bool {
		horizontal == .center && vertical != .center
	}

	var isLeft: Bool {
		horizontal == .primary
	}

	var isRight: Bool {
		horizontal == .secondary
	}

	var isTop: Bool {
		vertical == .primary
	}

	var isBottom: Bool {
		vertical == .secondary
	}

	var location: UnitPoint {
		.init(x: horizontal.location, y: vertical.location)
	}
}

/**
A position on a rectangle.

Primary means left or top, secondary means right or bottom. Center is in the center.
*/
enum Side: Hashable {
	case primary
	case center
	case secondary

	/**
	Location in the crop, from 0-1.
	*/
	var location: Double {
		switch self {
		case .primary:
			0
		case .center:
			0.5
		case .secondary:
			1
		}
	}
}
