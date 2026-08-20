import Foundation
import XCTest

import CherryPickerCore
import CherryPickerServer

final class CandidateSimulationDocumentationContractTests: XCTestCase {
    func testDocumentedPutRequestDecodesAndPassesCalculatorValidation() throws {
        let exampleURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/examples/candidate-card-simulation-put-request.json")
        let request = try OutboxJSONCodec().decode(
            CandidateSimulationPutRequest.self,
            from: Data(contentsOf: exampleURL)
        )
        let facts = request.classifications.enumerated().map { index, classification in
            CandidateCardTransactionFact(
                id: classification.transactionID,
                occurredAt: Date(timeIntervalSince1970: 1_788_200_000 + Double(index * 60)),
                amount: 20_000 + index * 10_000,
                merchant: "합성 문서 거래 \(index + 1)"
            )
        }

        let result = try CandidateCardSimulationCalculator().calculate(
            policy: request.policy,
            facts: facts,
            classifications: request.classifications,
            input: CandidateCardSimulationInput(
                selectedTransactionIDs: [],
                answers: [],
                performanceAssumptionID: request.defaultPerformanceAssumptionId
            )
        )

        XCTAssertEqual(request.analysisMonth, "2026-07")
        XCTAssertEqual(request.policy.schemaVersion, CandidateCardPolicyTemplate.currentSchemaVersion)
        XCTAssertEqual(result.selectedTransactionCount, 0)
        XCTAssertNil(result.pickingRatePercentage)
    }
}
