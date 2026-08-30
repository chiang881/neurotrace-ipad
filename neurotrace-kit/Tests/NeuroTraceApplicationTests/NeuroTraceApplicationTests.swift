import XCTest
import NeuroTraceDomain
@testable import NeuroTraceApplication

final class NeuroTraceApplicationTests: XCTestCase {
    func testTaskRunHappyPath() throws {
        var machine = TaskRunStateMachine()

        XCTAssertEqual(try machine.send(.start), .recording)
        XCTAssertEqual(try machine.send(.end(hasValidInput: true)), .review)
        XCTAssertEqual(try machine.send(.beginSaving), .saving)
        XCTAssertEqual(try machine.send(.saved), .completed)
    }

    func testNoInputCanBeRedone() throws {
        var machine = TaskRunStateMachine(state: .recording)

        XCTAssertEqual(try machine.send(.end(hasValidInput: false)), .failed("No valid input"))
        XCTAssertEqual(try machine.send(.redo), .ready)
    }

    func testExitMarksRunInterruptedAndInvalidTransitionThrows() throws {
        var machine = TaskRunStateMachine(state: .recording)
        XCTAssertEqual(try machine.send(.exit), .failed("Interrupted"))
        XCTAssertThrowsError(try machine.send(.saved))
    }

    func testFakeSubjectRepositoryCRUDAndSearch() async throws {
        let repository = FakeSubjectRepository()
        let subject = NeuroTraceDomain.Subject(
            id: UUID(),
            code: "S-LEFT-001",
            age: 66,
            sex: "female",
            dominantHand: "left",
            researchGroup: "baseline",
            notes: ""
        )

        await repository.save(subject)
        let searchResults = await repository.subjects(matching: "left")
        let storedSubject = await repository.subject(id: subject.id)
        XCTAssertEqual(searchResults, [subject])
        XCTAssertEqual(storedSubject, subject)

        await repository.delete(id: subject.id)
        let remainingSubjects = await repository.subjects(matching: "")
        XCTAssertTrue(remainingSubjects.isEmpty)
    }
}
