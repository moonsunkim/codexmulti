import CoreGraphics
import Foundation
import XCTest
@testable import CodexMulti

final class AccountReorderTests: XCTestCase {
    private let midpoints: [CGFloat] = [28, 84, 140]

    func testDestinationIndexClampsToTheTopAndBottom() {
        XCTAssertEqual(AccountReorder.destinationIndex(
            rowMidpoints: midpoints, draggedIndex: 1, draggedMidY: -100), 0)
        XCTAssertEqual(AccountReorder.destinationIndex(
            rowMidpoints: midpoints, draggedIndex: 1, draggedMidY: 500), 2)
    }

    func testDestinationIndexKeepsTheSamePlaceUntilAnotherMidpointIsCrossed() {
        XCTAssertEqual(AccountReorder.destinationIndex(
            rowMidpoints: midpoints, draggedIndex: 1, draggedMidY: 84), 1)
        XCTAssertEqual(AccountReorder.destinationIndex(
            rowMidpoints: midpoints, draggedIndex: 0, draggedMidY: 84), 0)
        XCTAssertEqual(AccountReorder.destinationIndex(
            rowMidpoints: midpoints, draggedIndex: 0, draggedMidY: 84.1), 1)
    }

    func testDestinationIndexHandlesEmptyAndSingleRowLists() {
        XCTAssertNil(AccountReorder.destinationIndex(
            rowMidpoints: [], draggedIndex: 0, draggedMidY: 0))
        XCTAssertEqual(AccountReorder.destinationIndex(
            rowMidpoints: [28], draggedIndex: 0, draggedMidY: 500), 0)
    }

    func testOptimisticMovePersistsUntilTheNextProjectionReplacesIt() throws {
        let projection = try JSONDecoder().decode(
            Projection.self, from: Data(contentsOf: Fixtures.exported("unified-proxy-order")))
        let projectedRows = projection.view.unified_rows
        var order = OptimisticAccountOrder(projectedKeys: projectedRows.map(\.key))

        XCTAssertTrue(order.move(from: 2, to: 0))
        XCTAssertEqual(order.keys, [projectedRows[2].key, projectedRows[0].key, projectedRows[1].key])
        XCTAssertEqual(order.rows(from: projectedRows).map(\.key), order.keys)
        XCTAssertTrue(order.awaitingProjection)

        let nextProjectionRows = [projectedRows[1], projectedRows[2], projectedRows[0]]
        order.receiveProjection(keys: nextProjectionRows.map(\.key))
        XCTAssertEqual(order.rows(from: nextProjectionRows), nextProjectionRows)
        XCTAssertEqual(order.keys, nextProjectionRows.map(\.key))
        XCTAssertFalse(order.awaitingProjection)
    }

    func testOptimisticMoveRejectsSamePlaceAndOneRowMoves() {
        var many = OptimisticAccountOrder(projectedKeys: [10, 20, 30])
        XCTAssertFalse(many.move(from: 1, to: 1))
        XCTAssertEqual(many.keys, [10, 20, 30])
        XCTAssertFalse(many.awaitingProjection)

        var one = OptimisticAccountOrder(projectedKeys: [10])
        XCTAssertFalse(one.move(from: 0, to: 0))
        XCTAssertEqual(one.keys, [10])
        XCTAssertFalse(one.awaitingProjection)
    }
}
