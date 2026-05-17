import XCTest
@testable import ParsoMusic

final class SeekWheelViewModelTests: XCTestCase {

    private func makeVM(
        currentTime: TimeInterval = 0,
        duration: TimeInterval = 3600,
        onSeek: @escaping (TimeInterval) -> Void = { _ in }
    ) -> SeekWheelViewModel {
        let vm = SeekWheelViewModel()
        vm.currentTime = currentTime
        vm.duration = duration
        vm.onSeek = onSeek
        return vm
    }

    func test_dragClockwise_increasesSeekTime() {
        var result: TimeInterval = 0
        let vm = makeVM(currentTime: 1800, onSeek: { result = $0 })
        vm.simulateDrag(fromAngle: -.pi / 2, toAngle: 0, velocity: 1.0)
        XCTAssertGreaterThan(result, 1800)
    }

    func test_dragCounterClockwise_decreasesSeekTime() {
        var result: TimeInterval = 1800
        let vm = makeVM(currentTime: 1800, onSeek: { result = $0 })
        vm.simulateDrag(fromAngle: 0, toAngle: -.pi / 2, velocity: 1.0)
        XCTAssertLessThan(result, 1800)
    }

    func test_seekTimeClampsAtZero() {
        var result: TimeInterval = 5
        let vm = makeVM(currentTime: 5, onSeek: { result = $0 })
        vm.simulateDrag(fromAngle: -.pi / 2, toAngle: -.pi / 2 - 20, velocity: 0.5)
        XCTAssertGreaterThanOrEqual(result, 0)
    }

    func test_seekTimeClampsAtDuration() {
        var result: TimeInterval = 3595
        let vm = makeVM(currentTime: 3595, duration: 3600, onSeek: { result = $0 })
        vm.simulateDrag(fromAngle: -.pi / 2, toAngle: -.pi / 2 + 20, velocity: 0.5)
        XCTAssertLessThanOrEqual(result, 3600)
    }

    func test_fastDrag_seeksMoreThanSlowDrag_sameArc() {
        var slowResult: TimeInterval = 1800
        var fastResult: TimeInterval = 1800
        let arc: Double = .pi / 4

        let slowVM = makeVM(currentTime: 1800, onSeek: { slowResult = $0 })
        slowVM.simulateDrag(fromAngle: 0, toAngle: arc, velocity: 0.5)

        let fastVM = makeVM(currentTime: 1800, onSeek: { fastResult = $0 })
        fastVM.simulateDrag(fromAngle: 0, toAngle: arc, velocity: 8.0)

        XCTAssertGreaterThan(fastResult, slowResult)
    }

    func test_onSeekIsCalledOnDrag() {
        var callCount = 0
        let vm = makeVM(onSeek: { _ in callCount += 1 })
        vm.simulateDrag(fromAngle: 0, toAngle: .pi / 4, velocity: 1.0)
        XCTAssertEqual(callCount, 1)
    }

    func test_handleDragEnded_resetsState() {
        let vm = makeVM(currentTime: 1800)
        vm.simulateDrag(fromAngle: 0, toAngle: .pi / 4, velocity: 1.0)
        vm.handleDragEnded()
        var result: TimeInterval = 0
        vm.onSeek = { result = $0 }
        vm.simulateDrag(fromAngle: 0, toAngle: .pi / 8, velocity: 1.0)
        XCTAssertGreaterThan(result, 0)
    }
}
