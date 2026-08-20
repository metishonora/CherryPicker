import Foundation
import XCTest

@testable import CherryPickerCore

final class CandidateCardSimulationTests: XCTestCase {
    private let calculator = CandidateCardSimulationCalculator()

    func testEmptySelectionHasNoRateAndUnselectedRawPreviewConsumesNothing() throws {
        let transaction = fact(1, amount: 10_000)
        let result = try calculate(
            policy: policy(),
            facts: [transaction],
            classifications: [classification(transaction.id, benefitIDs: ["discount"])],
            selected: []
        )

        XCTAssertEqual(result.calculatorVersion, CandidateCardSimulationCalculator.calculatorVersion)
        XCTAssertEqual(result.selectedTransactionCount, 0)
        XCTAssertEqual(result.selectedTransactionAmount, 0)
        XCTAssertEqual(result.performanceAmount, range(0))
        XCTAssertEqual(result.benefitAmount, range(0))
        XCTAssertNil(result.pickingRatePercentage)
        XCTAssertNil(result.annualFeeAdjustedPickingRatePercentage)
        XCTAssertEqual(result.limitGroups.single?.usedAmount, range(0))
        XCTAssertEqual(result.limitGroups.single?.remainingAmount, range(15_000))
        XCTAssertEqual(result.transactions.single?.rawBenefitAmount, range(1_000))
        XCTAssertEqual(result.transactions.single?.appliedBenefitAmount, range(0))
        XCTAssertEqual(result.transactions.single?.missedBenefitAmount, range(1_000))
    }

    func testSelectedZeroBenefitStillBelongsToPickingRateDenominator() throws {
        let transaction = fact(1, amount: 100_000)
        let result = try calculate(
            policy: policy(),
            facts: [transaction],
            classifications: [classification(transaction.id, benefitIDs: [])],
            selected: [transaction.id]
        )

        XCTAssertEqual(result.selectedTransactionAmount, 100_000)
        XCTAssertEqual(result.benefitAmount, range(0))
        XCTAssertEqual(result.pickingRatePercentage, rate(0))
        XCTAssertEqual(result.annualFeeAdjustedPickingRatePercentage, rate(-1))
    }

    func testSelectionArrayOrderCannotChangeCapAllocation() throws {
        let early = fact(1, at: "2026-07-01T09:00:00+09:00", amount: 10_000)
        let late = fact(2, at: "2026-07-02T09:00:00+09:00", amount: 10_000)
        let cappedPolicy = policy(groupMaximum: 1_000)
        let classifications = [
            classification(early.id, benefitIDs: ["discount"]),
            classification(late.id, benefitIDs: ["discount"])
        ]

        let forward = try calculate(
            policy: cappedPolicy,
            facts: [late, early],
            classifications: classifications,
            selected: [early.id, late.id]
        )
        let reverse = try calculate(
            policy: cappedPolicy,
            facts: [early, late],
            classifications: classifications.reversed(),
            selected: [late.id, early.id]
        )

        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(forward.transactions.map(\.transactionID), [early.id, late.id])
        XCTAssertEqual(forward.transactions[0].appliedBenefitAmount, range(1_000))
        XCTAssertEqual(forward.transactions[1].appliedBenefitAmount, range(0))
        XCTAssertEqual(forward.transactions[1].missedBenefitAmount, range(1_000))
    }

    func testEqualTimestampUsesCanonicalUUIDAscendingOrder() throws {
        let lowerID = fact(1, amount: 10_000)
        let higherID = fact(2, amount: 10_000)
        let result = try calculate(
            policy: policy(groupMaximum: 1_000),
            facts: [higherID, lowerID],
            classifications: [
                classification(higherID.id, benefitIDs: ["discount"]),
                classification(lowerID.id, benefitIDs: ["discount"])
            ],
            selected: [higherID.id, lowerID.id]
        )

        XCTAssertEqual(result.transactions.map(\.transactionID), [lowerID.id, higherID.id])
        XCTAssertEqual(result.transactions[0].appliedBenefitAmount, range(1_000))
        XCTAssertEqual(result.transactions[1].appliedBenefitAmount, range(0))
    }

    func testUnansweredAlternativesEvaluateGlobalCapAndDownstreamReallocationExactly() throws {
        let ambiguous = fact(1, at: "2026-07-01T09:00:00+09:00", amount: 10_000)
        let downstream = fact(2, at: "2026-07-02T09:00:00+09:00", amount: 8_000)
        let question = CandidateCardTransactionClassification(
            transactionID: ambiguous.id,
            question: "간편결제로 결제했나요?",
            alternatives: [
                alternative("yes", label: "예", benefitIDs: ["discount"]),
                alternative("no", label: "아니요", benefitIDs: [])
            ]
        )
        let cappedPolicy = policy(groupMaximum: 1_000)
        let facts = [ambiguous, downstream]
        let classifications = [question, classification(downstream.id, benefitIDs: ["discount"])]

        let unanswered = try calculate(
            policy: cappedPolicy,
            facts: facts,
            classifications: classifications,
            selected: facts.map(\.id)
        )
        XCTAssertEqual(unanswered.benefitAmount, CandidateCardIntegerRange(minimum: 800, maximum: 1_000))
        XCTAssertEqual(unanswered.transactions[0].appliedBenefitAmount, CandidateCardIntegerRange(minimum: 0, maximum: 1_000))
        XCTAssertEqual(unanswered.transactions[1].appliedBenefitAmount, CandidateCardIntegerRange(minimum: 0, maximum: 800))
        XCTAssertEqual(unanswered.limitGroups.single?.remainingAmount, CandidateCardIntegerRange(minimum: 0, maximum: 200))

        let yes = try calculate(
            policy: cappedPolicy,
            facts: facts,
            classifications: classifications,
            selected: facts.map(\.id),
            answers: [.init(transactionID: ambiguous.id, alternativeID: "yes")]
        )
        XCTAssertEqual(yes.benefitAmount, range(1_000))
        XCTAssertEqual(yes.transactions[0].appliedBenefitAmount, range(1_000))
        XCTAssertEqual(yes.transactions[1].appliedBenefitAmount, range(0))

        let no = try calculate(
            policy: cappedPolicy,
            facts: facts,
            classifications: classifications,
            selected: facts.map(\.id),
            answers: [.init(transactionID: ambiguous.id, alternativeID: "no")]
        )
        XCTAssertEqual(no.benefitAmount, range(800))
        XCTAssertEqual(no.transactions[0].appliedBenefitAmount, range(0))
        XCTAssertEqual(no.transactions[1].appliedBenefitAmount, range(800))
    }

    func testPerformanceAlternativesAndAssumptionBoundariesStayIndependent() throws {
        let transaction = fact(1, amount: 300_000)
        let classification = CandidateCardTransactionClassification(
            transactionID: transaction.id,
            question: "실적 제외 거래인가요?",
            alternatives: [
                alternative("included", label: "아니요", performance: .included, benefitIDs: ["discount"]),
                alternative("excluded", label: "예", performance: .excluded, benefitIDs: ["discount"])
            ]
        )
        let assumptions = [
            CandidateCardPerformanceAssumption(
                id: "below",
                label: "미달",
                previousMonthAmount: 299_999,
                isGrace: false,
                limitGroupMaximumAmounts: ["shared": 0]
            ),
            CandidateCardPerformanceAssumption(
                id: "qualified",
                label: "30만원",
                previousMonthAmount: 300_000,
                isGrace: false,
                limitGroupMaximumAmounts: ["shared": 15_000]
            ),
            CandidateCardPerformanceAssumption(
                id: "grace",
                label: "신규 발급 유예",
                previousMonthAmount: nil,
                isGrace: true,
                limitGroupMaximumAmounts: ["shared": 15_000]
            )
        ]
        let template = policy(assumptions: assumptions)

        let below = try calculate(
            policy: template,
            facts: [transaction],
            classifications: [classification],
            selected: [transaction.id],
            assumptionID: "below"
        )
        XCTAssertEqual(below.benefitAmount, range(0))
        XCTAssertEqual(below.performanceAmount, CandidateCardIntegerRange(minimum: 0, maximum: 300_000))
        XCTAssertEqual(below.nextPerformanceThreshold.thresholdAmount, CandidateCardIntegerRange(minimum: 300_000, maximum: 600_000))
        XCTAssertEqual(below.nextPerformanceThreshold.remainingAmount, range(300_000))

        let qualified = try calculate(
            policy: template,
            facts: [transaction],
            classifications: [classification],
            selected: [transaction.id],
            assumptionID: "qualified"
        )
        let grace = try calculate(
            policy: template,
            facts: [transaction],
            classifications: [classification],
            selected: [transaction.id],
            assumptionID: "grace"
        )
        XCTAssertEqual(qualified.benefitAmount, range(15_000))
        XCTAssertEqual(grace.benefitAmount, qualified.benefitAmount)
        XCTAssertEqual(grace.limitGroups, qualified.limitGroups)
    }

    func testNextThresholdRangesUseEveryReachablePerformanceAmount() throws {
        let transactions = [
            fact(1, at: "2026-07-01T09:00:00+09:00", amount: 100_000),
            fact(2, at: "2026-07-02T09:00:00+09:00", amount: 250_000),
            fact(3, at: "2026-07-03T09:00:00+09:00", amount: 400_000)
        ]
        let classifications = transactions.map { transaction in
            CandidateCardTransactionClassification(
                transactionID: transaction.id,
                question: "실적에 포함되나요?",
                alternatives: [
                    alternative("included", label: "포함", performance: .included, benefitIDs: []),
                    alternative("excluded", label: "제외", performance: .excluded, benefitIDs: [])
                ]
            )
        }

        let result = try calculate(
            policy: policy(),
            facts: transactions,
            classifications: classifications,
            selected: transactions.map(\.id)
        )

        XCTAssertEqual(result.performanceAmount, CandidateCardIntegerRange(minimum: 0, maximum: 750_000))
        XCTAssertEqual(
            result.nextPerformanceThreshold.thresholdAmount,
            CandidateCardIntegerRange(minimum: 300_000, maximum: 600_000)
        )
        XCTAssertEqual(
            result.nextPerformanceThreshold.remainingAmount,
            CandidateCardIntegerRange(minimum: 50_000, maximum: 300_000),
            "the 250,000 intermediate scenario must contribute the exact 50,000 remainder"
        )
        XCTAssertTrue(result.nextPerformanceThreshold.includesNoNextThreshold)
    }

    func testAnnualFeeOnlyChangesAuxiliaryRate() throws {
        let transaction = fact(1, amount: 100_000)
        let result = try calculate(
            policy: policy(groupMaximum: 20_000, annualFee: 12_000),
            facts: [transaction],
            classifications: [classification(transaction.id, benefitIDs: ["discount"])],
            selected: [transaction.id]
        )

        XCTAssertEqual(result.benefitAmount, range(10_000))
        XCTAssertEqual(result.pickingRatePercentage, rate(10))
        XCTAssertEqual(result.annualFeeMonthlyAmount, 1_000)
        XCTAssertEqual(result.annualFeeAdjustedPickingRatePercentage, rate(9))
        XCTAssertEqual(result.transactions.single?.appliedBenefitAmount, result.benefitAmount)

        let fractionalMonthlyFee = try calculate(
            policy: policy(groupMaximum: 20_000, annualFee: 10_000),
            facts: [transaction],
            classifications: [classification(transaction.id, benefitIDs: ["discount"])],
            selected: [transaction.id]
        )
        XCTAssertEqual(fractionalMonthlyFee.annualFeeMonthlyAmount, 833)
    }

    func testRoundingPerTransactionMaximumMonthlyCountAndStackingAreExplicit() throws {
        let first = fact(1, at: "2026-07-01T09:00:00+09:00", amount: 1_100)
        let second = fact(2, at: "2026-07-02T09:00:00+09:00", amount: 1_100)
        let floor = benefit(
            id: "floor",
            rate: 500,
            perTransactionMaximum: 35,
            monthlyCount: 1,
            priority: 0,
            rounding: .init(unit: 10, direction: .floor)
        )
        let ceiling = benefit(
            id: "ceiling",
            rate: 500,
            priority: 1,
            rounding: .init(unit: 10, direction: .ceiling)
        )
        let template = policy(
            groupMaximum: 10_000,
            benefits: [floor, ceiling],
            stacking: .highestPriorityOnly
        )
        let classifications = [
            classification(first.id, benefitIDs: ["ceiling", "floor"]),
            classification(second.id, benefitIDs: ["floor", "ceiling"])
        ]

        let result = try calculate(
            policy: template,
            facts: [first, second],
            classifications: classifications,
            selected: [second.id, first.id]
        )

        XCTAssertEqual(result.transactions[0].rawBenefitAmount, range(35))
        XCTAssertEqual(result.transactions[0].appliedBenefitAmount, range(35))
        XCTAssertEqual(result.transactions[1].rawBenefitAmount, range(35))
        XCTAssertEqual(result.transactions[1].appliedBenefitAmount, range(0))
        XCTAssertEqual(result.transactions[1].missedBenefitAmount, range(35))
        XCTAssertEqual(result.benefitAmount, range(35))
    }

    func testAllEligibleStackingUsesEveryLimitGroupAndReleasesUnsharedRemainder() throws {
        let bothGroups = CandidateCardBenefitDefinition(
            id: "both",
            label: "두 한도",
            conditionSummary: "합성 조건",
            exclusionNotes: [],
            rateBasisPoints: 1_000,
            limitGroupIDs: ["a", "b"],
            priority: 0,
            rounding: .init(unit: 1, direction: .floor)
        )
        let onlyA = CandidateCardBenefitDefinition(
            id: "only-a",
            label: "A 한도",
            conditionSummary: "합성 조건",
            exclusionNotes: [],
            rateBasisPoints: 1_000,
            limitGroupIDs: ["a"],
            priority: 1,
            rounding: .init(unit: 1, direction: .floor)
        )
        let template = CandidateCardPolicyTemplate(
            snapshotID: uuid(900),
            cardName: "합성 카드",
            issuerName: "합성 카드사",
            productIdentifier: "synthetic",
            source: source,
            annualFeeAmount: 0,
            performanceThresholdAmounts: [],
            limitGroups: [
                .init(id: "a", label: "A"),
                .init(id: "b", label: "B")
            ],
            performanceAssumptions: [
                .init(
                    id: "qualified",
                    label: "달성",
                    previousMonthAmount: 300_000,
                    isGrace: false,
                    limitGroupMaximumAmounts: ["a": 1_000, "b": 500]
                )
            ],
            benefits: [bothGroups, onlyA],
            stacking: .allEligible,
            performanceExclusions: [],
            benefitExclusions: [],
            unsupportedPolicyConditions: []
        )
        let first = fact(1, at: "2026-07-01T09:00:00+09:00", amount: 10_000)
        let second = fact(2, at: "2026-07-02T09:00:00+09:00", amount: 10_000)
        let result = try calculate(
            policy: template,
            facts: [first, second],
            classifications: [
                classification(first.id, benefitIDs: ["both"]),
                classification(second.id, benefitIDs: ["only-a"])
            ],
            selected: [first.id, second.id]
        )

        XCTAssertEqual(result.benefitAmount, range(1_000))
        XCTAssertEqual(result.transactions[0].appliedBenefitAmount, range(500))
        XCTAssertEqual(result.transactions[1].appliedBenefitAmount, range(500))
        XCTAssertEqual(result.limitGroups.first(where: { $0.id == "a" })?.usedAmount, range(1_000))
        XCTAssertEqual(result.limitGroups.first(where: { $0.id == "b" })?.usedAmount, range(500))
    }

    func testTemplateInputAndResultAreCodableRoundTrips() throws {
        let template = policy()
        let transaction = fact(1, amount: 10_000)
        let input = CandidateCardSimulationInput(
            selectedTransactionIDs: [transaction.id],
            answers: [],
            performanceAssumptionID: "qualified"
        )
        let result = try calculator.calculate(
            policy: template,
            facts: [transaction],
            classifications: [classification(transaction.id, benefitIDs: ["discount"])],
            input: input
        )

        XCTAssertEqual(try roundTrip(template), template)
        XCTAssertEqual(try roundTrip(input), input)
        XCTAssertEqual(try roundTrip(result), result)
    }

    func testInvalidTemplatesAndStateReferencesAreRejectedBeforeCalculation() throws {
        let transaction = fact(1, amount: 10_000)
        let validClassification = classification(transaction.id, benefitIDs: ["discount"])

        XCTAssertThrowsError(try calculate(
            policy: policy(unsupported: ["매입일 기준 한도"]),
            facts: [transaction],
            classifications: [validClassification],
            selected: [transaction.id]
        )) { error in
            XCTAssertEqual(
                error as? CandidateCardSimulationError,
                .unsupportedPolicyConditions(["매입일 기준 한도"])
            )
        }

        let missingCoverage = CandidateCardPerformanceAssumption(
            id: "qualified",
            label: "달성",
            previousMonthAmount: 300_000,
            isGrace: false,
            limitGroupMaximumAmounts: [:]
        )
        XCTAssertThrowsError(try calculate(
            policy: policy(assumptions: [missingCoverage]),
            facts: [transaction],
            classifications: [validClassification],
            selected: [transaction.id]
        ))

        let invalidQuestion = CandidateCardTransactionClassification(
            transactionID: transaction.id,
            alternatives: [
                alternative("yes", benefitIDs: ["discount"]),
                alternative("no", benefitIDs: [])
            ]
        )
        XCTAssertThrowsError(try calculate(
            policy: policy(),
            facts: [transaction],
            classifications: [invalidQuestion],
            selected: [transaction.id]
        ))

        XCTAssertThrowsError(try calculate(
            policy: policy(),
            facts: [transaction],
            classifications: [validClassification],
            selected: [transaction.id],
            answers: [.init(transactionID: transaction.id, alternativeID: "unknown")]
        )) { error in
            XCTAssertEqual(
                error as? CandidateCardSimulationError,
                .invalidAnswer(transaction.id, "unknown")
            )
        }
    }

    func testUnknownAndDuplicateIDsAreRejected() throws {
        let transaction = fact(1, amount: 10_000)
        let unknown = uuid(999)
        XCTAssertThrowsError(try calculate(
            policy: policy(),
            facts: [transaction],
            classifications: [classification(transaction.id, benefitIDs: ["discount"])],
            selected: [transaction.id, transaction.id]
        )) { error in
            XCTAssertEqual(error as? CandidateCardSimulationError, .duplicateSelection(transaction.id))
        }
        XCTAssertThrowsError(try calculate(
            policy: policy(),
            facts: [transaction],
            classifications: [classification(transaction.id, benefitIDs: ["discount"])],
            selected: [unknown]
        )) { error in
            XCTAssertEqual(error as? CandidateCardSimulationError, .unknownSelectedTransaction(unknown))
        }

        let duplicateBenefits = [benefit(), benefit()]
        XCTAssertThrowsError(try calculate(
            policy: policy(benefits: duplicateBenefits),
            facts: [transaction],
            classifications: [classification(transaction.id, benefitIDs: ["discount"])],
            selected: []
        )) { error in
            XCTAssertEqual(
                error as? CandidateCardSimulationError,
                .duplicateIdentifier(kind: "benefit", id: "discount")
            )
        }
    }

    func testInvalidNumericPolicyAndUnknownReferencesAreRejected() throws {
        let transaction = fact(1, amount: 10_000)
        let transactionClassification = classification(transaction.id, benefitIDs: ["discount"])
        let invalidBenefits = [
            benefit(rate: -1),
            benefit(rate: 10_001),
            benefit(monthlyCount: 0),
            benefit(rounding: .init(unit: 0, direction: .floor)),
            benefit(limitGroupIDs: ["unknown"])
        ]

        for invalidBenefit in invalidBenefits {
            XCTAssertThrowsError(try calculate(
                policy: policy(benefits: [invalidBenefit]),
                facts: [transaction],
                classifications: [transactionClassification],
                selected: [transaction.id]
            ))
        }

        XCTAssertThrowsError(try calculate(
            policy: policy(schemaVersion: 2),
            facts: [transaction],
            classifications: [transactionClassification],
            selected: []
        )) { error in
            XCTAssertEqual(error as? CandidateCardSimulationError, .unsupportedSchemaVersion(2))
        }
        XCTAssertThrowsError(try calculate(
            policy: policy(performanceThresholdAmounts: [600_000, 300_000]),
            facts: [transaction],
            classifications: [transactionClassification],
            selected: []
        ))
    }

    func testFactClassificationAndAnswerCoverageMustBeOneToOne() throws {
        let transaction = fact(1, amount: 10_000)
        let other = fact(2, amount: 10_000)

        XCTAssertThrowsError(try calculate(
            policy: policy(),
            facts: [transaction],
            classifications: [],
            selected: []
        )) { error in
            XCTAssertEqual(error as? CandidateCardSimulationError, .missingClassification(transaction.id))
        }
        XCTAssertThrowsError(try calculate(
            policy: policy(),
            facts: [transaction],
            classifications: [classification(other.id, benefitIDs: [])],
            selected: []
        )) { error in
            XCTAssertEqual(error as? CandidateCardSimulationError, .classificationWithoutFact(other.id))
        }

        let ambiguous = CandidateCardTransactionClassification(
            transactionID: transaction.id,
            question: "결제 방식은?",
            alternatives: [
                alternative("a", label: "같음", benefitIDs: []),
                alternative("b", label: "같음", benefitIDs: [])
            ]
        )
        XCTAssertThrowsError(try calculate(
            policy: policy(),
            facts: [transaction],
            classifications: [ambiguous],
            selected: []
        ))

        let answerable = CandidateCardTransactionClassification(
            transactionID: transaction.id,
            question: "혜택 경로인가요?",
            alternatives: [
                alternative("eligible", label: "예", benefitIDs: ["discount"]),
                alternative("ineligible", label: "아니요", benefitIDs: [])
            ]
        )
        XCTAssertThrowsError(try calculate(
            policy: policy(),
            facts: [transaction],
            classifications: [answerable],
            selected: [],
            answers: [
                .init(transactionID: transaction.id, alternativeID: "eligible"),
                .init(transactionID: transaction.id, alternativeID: "eligible")
            ]
        )) { error in
            XCTAssertEqual(error as? CandidateCardSimulationError, .duplicateAnswer(transaction.id))
        }

        XCTAssertThrowsError(try calculate(
            policy: policy(),
            facts: [transaction],
            classifications: [classification(transaction.id, benefitIDs: [])],
            selected: [],
            answers: [
                .init(transactionID: transaction.id, alternativeID: "known")
            ]
        )) { error in
            XCTAssertEqual(
                error as? CandidateCardSimulationError,
                .invalidAnswer(transaction.id, "known")
            )
        }
    }

    func testQuestionShapeMustMatchComputationalAmbiguity() throws {
        let transaction = fact(1, amount: 10_000)
        let deterministicWithQuestion = CandidateCardTransactionClassification(
            transactionID: transaction.id,
            question: "불필요한 질문",
            alternatives: [alternative("known", benefitIDs: ["discount"])]
        )
        let deterministicWithAnswerLabel = CandidateCardTransactionClassification(
            transactionID: transaction.id,
            alternatives: [
                alternative("known", label: "불필요한 답", benefitIDs: ["discount"])
            ]
        )
        let sameOutcomeQuestion = CandidateCardTransactionClassification(
            transactionID: transaction.id,
            question: "계산은 같나요?",
            alternatives: [
                alternative("a", label: "A", benefitIDs: ["discount"]),
                alternative("b", label: "B", benefitIDs: ["discount"])
            ]
        )

        for invalid in [deterministicWithQuestion, deterministicWithAnswerLabel, sameOutcomeQuestion] {
            XCTAssertThrowsError(try calculate(
                policy: policy(),
                facts: [transaction],
                classifications: [invalid],
                selected: []
            ))
        }
    }

    func testQuestionOutcomeIdentityDoesNotCollideOnBenefitIDDelimiters() throws {
        let transaction = fact(1, amount: 10_000)
        let benefits = [
            benefit(id: "a", rate: 1_000, priority: 0),
            benefit(id: "b", rate: 1_000, priority: 1),
            benefit(id: "a,b", rate: 1_000, priority: 2)
        ]
        let classification = CandidateCardTransactionClassification(
            transactionID: transaction.id,
            question: "어느 혜택 조합인가요?",
            alternatives: [
                alternative("combined", label: "두 혜택", benefitIDs: ["a", "b"]),
                alternative("literal", label: "단일 혜택", benefitIDs: ["a,b"])
            ]
        )

        let result = try calculate(
            policy: policy(groupMaximum: 100_000, benefits: benefits),
            facts: [transaction],
            classifications: [classification],
            selected: [transaction.id]
        )

        XCTAssertEqual(
            result.benefitAmount,
            CandidateCardIntegerRange(minimum: 1_000, maximum: 2_000)
        )
    }

    func testPerformanceAssumptionGraceSemanticsAreUnambiguous() throws {
        let transaction = fact(1, amount: 10_000)
        let classification = classification(transaction.id, benefitIDs: [])
        let grace = CandidateCardPerformanceAssumption(
            id: "grace",
            label: "유예",
            previousMonthAmount: nil,
            isGrace: true,
            limitGroupMaximumAmounts: ["shared": 15_000]
        )
        let secondGrace = CandidateCardPerformanceAssumption(
            id: "second-grace",
            label: "다른 유예",
            previousMonthAmount: nil,
            isGrace: true,
            limitGroupMaximumAmounts: ["shared": 15_000]
        )
        let graceWithAmount = CandidateCardPerformanceAssumption(
            id: "grace",
            label: "유예",
            previousMonthAmount: 0,
            isGrace: true,
            limitGroupMaximumAmounts: ["shared": 15_000]
        )
        let regularWithoutAmount = CandidateCardPerformanceAssumption(
            id: "regular",
            label: "일반",
            previousMonthAmount: nil,
            isGrace: false,
            limitGroupMaximumAmounts: ["shared": 15_000]
        )

        for invalidAssumptions in [
            [grace, secondGrace],
            [graceWithAmount],
            [regularWithoutAmount]
        ] {
            XCTAssertThrowsError(try calculate(
                policy: policy(assumptions: invalidAssumptions),
                facts: [transaction],
                classifications: [classification],
                selected: [],
                assumptionID: invalidAssumptions[0].id
            ))
        }
    }

    func testInt64RateArithmeticOverflowIsReported() throws {
        let transaction = fact(1, amount: Int.max)
        XCTAssertThrowsError(try calculate(
            policy: policy(benefits: [benefit(rate: 10_000)]),
            facts: [transaction],
            classifications: [classification(transaction.id, benefitIDs: ["discount"])],
            selected: [transaction.id]
        )) { error in
            XCTAssertEqual(error as? CandidateCardSimulationError, .arithmeticOverflow)
        }
    }

    func testTwentyBinaryQuestionsUseExactStateDedupInsteadOfCartesianRejection() throws {
        let transactions = (1...20).map {
            fact($0, at: String(format: "2026-07-%02dT09:00:00+09:00", $0), amount: 1_000)
        }
        let classifications = transactions.map {
            CandidateCardTransactionClassification(
                transactionID: $0.id,
                question: "예 또는 아니요?",
                alternatives: [
                    alternative("yes", label: "예", benefitIDs: ["discount"]),
                    alternative("no", label: "아니요", benefitIDs: [])
                ]
            )
        }

        let result = try calculate(
            policy: policy(groupMaximum: 750),
            facts: transactions,
            classifications: classifications,
            selected: transactions.map(\.id)
        )

        XCTAssertEqual(result.performanceAmount, range(20_000))
        XCTAssertEqual(result.benefitAmount, CandidateCardIntegerRange(minimum: 0, maximum: 750))
        XCTAssertEqual(result.limitGroups.single?.usedAmount, CandidateCardIntegerRange(minimum: 0, maximum: 750))
        XCTAssertEqual(result.limitGroups.single?.remainingAmount, CandidateCardIntegerRange(minimum: 0, maximum: 750))
        XCTAssertEqual(result.transactions.count, 20)
        XCTAssertTrue(result.transactions.allSatisfy {
            $0.rawBenefitAmount == CandidateCardIntegerRange(minimum: 0, maximum: 100)
        })
    }

    func testDistinctPerformanceChoicesDoNotMultiplyBenefitEvaluationStates() throws {
        let transactions = (1...17).map {
            fact(
                $0,
                at: String(format: "2026-07-%02dT09:00:00+09:00", $0),
                amount: 1 << ($0 - 1)
            )
        }
        let classifications = transactions.map {
            CandidateCardTransactionClassification(
                transactionID: $0.id,
                question: "실적에 포함되나요?",
                alternatives: [
                    alternative("included", label: "포함", performance: .included, benefitIDs: []),
                    alternative("excluded", label: "제외", performance: .excluded, benefitIDs: [])
                ]
            )
        }

        let result = try calculate(
            policy: policy(),
            facts: transactions,
            classifications: classifications,
            selected: transactions.map(\.id)
        )

        XCTAssertEqual(
            result.performanceAmount,
            CandidateCardIntegerRange(minimum: 0, maximum: 131_071)
        )
        XCTAssertEqual(result.benefitAmount, range(0))
        XCTAssertEqual(result.nextPerformanceThreshold.thresholdAmount, range(300_000))
        XCTAssertEqual(
            result.nextPerformanceThreshold.remainingAmount,
            CandidateCardIntegerRange(minimum: 168_929, maximum: 300_000)
        )
        XCTAssertFalse(result.nextPerformanceThreshold.includesNoNextThreshold)
    }

    func testLargeThresholdUsesSparseExactPerformanceReachability() throws {
        let transactions = [
            fact(1, amount: 10_000_000),
            fact(2, amount: 10_000_001)
        ]
        let classifications = transactions.map {
            CandidateCardTransactionClassification(
                transactionID: $0.id,
                question: "실적에 포함되나요?",
                alternatives: [
                    alternative("included", label: "포함", performance: .included, benefitIDs: []),
                    alternative("excluded", label: "제외", performance: .excluded, benefitIDs: [])
                ]
            )
        }

        let result = try calculate(
            policy: policy(performanceThresholdAmounts: [20_000_002]),
            facts: transactions,
            classifications: classifications,
            selected: transactions.map(\.id)
        )

        XCTAssertEqual(
            result.performanceAmount,
            CandidateCardIntegerRange(minimum: 0, maximum: 20_000_001)
        )
        XCTAssertEqual(result.nextPerformanceThreshold.thresholdAmount, range(20_000_002))
        XCTAssertEqual(
            result.nextPerformanceThreshold.remainingAmount,
            CandidateCardIntegerRange(minimum: 1, maximum: 20_000_002)
        )
        XCTAssertFalse(result.nextPerformanceThreshold.includesNoNextThreshold)
    }

    func testPerBenefitAllocationsSumToTransactionAndTotalForAllEligibleStacking() throws {
        let primary = benefit(id: "primary", rate: 1_000, priority: 0)
        let secondary = benefit(id: "secondary", rate: 500, priority: 1)
        let transaction = fact(1, amount: 10_000)
        let result = try calculate(
            policy: policy(
                groupMaximum: 1_200,
                benefits: [secondary, primary],
                stacking: .allEligible
            ),
            facts: [transaction],
            classifications: [
                classification(transaction.id, benefitIDs: ["secondary", "primary"])
            ],
            selected: [transaction.id]
        )

        let row = try XCTUnwrap(result.transactions.single)
        XCTAssertEqual(row.rawBenefitAmount, range(1_500))
        XCTAssertEqual(row.appliedBenefitAmount, range(1_200))
        XCTAssertEqual(row.missedBenefitAmount, range(300))
        XCTAssertEqual(row.benefits.map(\.benefitID), ["primary", "secondary"])
        XCTAssertEqual(row.benefits[0].rawBenefitAmount, range(1_000))
        XCTAssertEqual(row.benefits[0].appliedBenefitAmount, range(1_000))
        XCTAssertEqual(row.benefits[0].missedBenefitAmount, range(0))
        XCTAssertEqual(row.benefits[1].rawBenefitAmount, range(500))
        XCTAssertEqual(row.benefits[1].appliedBenefitAmount, range(200))
        XCTAssertEqual(row.benefits[1].missedBenefitAmount, range(300))
        XCTAssertTrue(row.benefitBreakdownIsAdditive)
        XCTAssertEqual(row.benefits.reduce(0) { $0 + $1.rawBenefitAmount.minimum }, row.rawBenefitAmount.minimum)
        XCTAssertEqual(row.benefits.reduce(0) { $0 + $1.appliedBenefitAmount.minimum }, row.appliedBenefitAmount.minimum)
        XCTAssertEqual(row.benefits.reduce(0) { $0 + $1.missedBenefitAmount.minimum }, row.missedBenefitAmount.minimum)
        XCTAssertEqual(row.appliedBenefitAmount, result.benefitAmount)
    }

    func testMutuallyExclusiveBenefitRangesDoNotInflateAggregateTransactionRange() throws {
        let large = benefit(id: "large", rate: 1_000, priority: 0)
        let small = benefit(id: "small", rate: 500, priority: 1)
        let transaction = fact(1, amount: 10_000)
        let question = CandidateCardTransactionClassification(
            transactionID: transaction.id,
            question: "어느 혜택 조건인가요?",
            alternatives: [
                alternative("large", label: "큰 혜택", benefitIDs: ["large"]),
                alternative("small", label: "작은 혜택", benefitIDs: ["small"])
            ]
        )
        let result = try calculate(
            policy: policy(groupMaximum: 10_000, benefits: [large, small]),
            facts: [transaction],
            classifications: [question],
            selected: [transaction.id]
        )

        let row = try XCTUnwrap(result.transactions.single)
        XCTAssertEqual(row.rawBenefitAmount, CandidateCardIntegerRange(minimum: 500, maximum: 1_000))
        XCTAssertEqual(row.appliedBenefitAmount, row.rawBenefitAmount)
        XCTAssertEqual(row.missedBenefitAmount, range(0))
        XCTAssertEqual(result.benefitAmount, row.appliedBenefitAmount)
        XCTAssertEqual(row.benefits.map(\.benefitID), ["large", "small"])
        XCTAssertEqual(row.benefits[0].rawBenefitAmount, CandidateCardIntegerRange(minimum: 0, maximum: 1_000))
        XCTAssertEqual(row.benefits[1].rawBenefitAmount, CandidateCardIntegerRange(minimum: 0, maximum: 500))
        XCTAssertFalse(row.benefitBreakdownIsAdditive)
        XCTAssertEqual(row.rawBenefitAmount.maximum, 1_000, "mutually exclusive maxima must not be summed")
    }
}

private extension CandidateCardSimulationTests {
    var source: CandidateCardPolicySource {
        CandidateCardPolicySource(
            name: "합성 약관",
            reference: "fixture://candidate-card",
            effectiveDate: date("2026-07-01T00:00:00+09:00"),
            structuredAt: date("2026-08-20T09:00:00+09:00")
        )
    }

    func policy(
        schemaVersion: Int = CandidateCardPolicyTemplate.currentSchemaVersion,
        groupMaximum: Int = 15_000,
        annualFee: Int = 12_000,
        performanceThresholdAmounts: [Int] = [300_000, 600_000],
        assumptions: [CandidateCardPerformanceAssumption]? = nil,
        benefits: [CandidateCardBenefitDefinition]? = nil,
        stacking: CandidateCardBenefitStackingPolicy = .allEligible,
        unsupported: [String] = []
    ) -> CandidateCardPolicyTemplate {
        CandidateCardPolicyTemplate(
            schemaVersion: schemaVersion,
            snapshotID: uuid(900),
            cardName: "합성 카드",
            issuerName: "합성 카드사",
            productIdentifier: "synthetic-card",
            source: source,
            annualFeeAmount: annualFee,
            performanceThresholdAmounts: performanceThresholdAmounts,
            limitGroups: [.init(id: "shared", label: "통합 한도")],
            performanceAssumptions: assumptions ?? [
                .init(
                    id: "qualified",
                    label: "30만원",
                    previousMonthAmount: 300_000,
                    isGrace: false,
                    limitGroupMaximumAmounts: ["shared": groupMaximum]
                )
            ],
            benefits: benefits ?? [benefit()],
            stacking: stacking,
            performanceExclusions: ["상품권"],
            benefitExclusions: ["상품권"],
            unsupportedPolicyConditions: unsupported
        )
    }

    func benefit(
        id: String = "discount",
        rate: Int = 1_000,
        perTransactionMaximum: Int? = nil,
        monthlyCount: Int? = nil,
        limitGroupIDs: [String] = ["shared"],
        priority: Int = 0,
        rounding: CandidateCardRoundingRule = .init(unit: 1, direction: .floor)
    ) -> CandidateCardBenefitDefinition {
        CandidateCardBenefitDefinition(
            id: id,
            label: id,
            conditionSummary: "합성 혜택 조건",
            exclusionNotes: [],
            rateBasisPoints: rate,
            minimumTransactionAmount: nil,
            maximumTransactionAmount: nil,
            perTransactionMaximumBenefitAmount: perTransactionMaximum,
            monthlyCountLimit: monthlyCount,
            limitGroupIDs: limitGroupIDs,
            priority: priority,
            rounding: rounding
        )
    }

    func fact(
        _ number: Int,
        at occurredAt: String = "2026-07-01T09:00:00+09:00",
        amount: Int
    ) -> CandidateCardTransactionFact {
        CandidateCardTransactionFact(
            id: uuid(number),
            occurredAt: date(occurredAt),
            amount: amount,
            merchant: "가맹점 \(number)"
        )
    }

    func classification(
        _ transactionID: UUID,
        benefitIDs: [String]
    ) -> CandidateCardTransactionClassification {
        CandidateCardTransactionClassification(
            transactionID: transactionID,
            alternatives: [alternative("known", benefitIDs: benefitIDs)]
        )
    }

    func alternative(
        _ id: String,
        label: String? = nil,
        performance: CandidateCardPerformanceDecision = .included,
        benefitIDs: [String]
    ) -> CandidateCardClassificationAlternative {
        CandidateCardClassificationAlternative(
            id: id,
            answerLabel: label,
            performance: performance,
            performanceReason: performance == .included ? "실적 인정" : "실적 제외",
            benefitIDs: benefitIDs,
            benefitReason: benefitIDs.isEmpty ? "혜택 없음" : "혜택 조건 충족"
        )
    }

    func calculate(
        policy: CandidateCardPolicyTemplate,
        facts: [CandidateCardTransactionFact],
        classifications: [CandidateCardTransactionClassification],
        selected: [UUID],
        answers: [CandidateCardTransactionAnswer] = [],
        assumptionID: String = "qualified"
    ) throws -> CandidateCardSimulationResult {
        try calculator.calculate(
            policy: policy,
            facts: facts,
            classifications: classifications,
            input: CandidateCardSimulationInput(
                selectedTransactionIDs: selected,
                answers: answers,
                performanceAssumptionID: assumptionID
            )
        )
    }

    func range(_ value: Int) -> CandidateCardIntegerRange {
        CandidateCardIntegerRange(minimum: value, maximum: value)
    }

    func rate(_ value: Double) -> CandidateCardRateRange {
        CandidateCardRateRange(minimum: value, maximum: value)
    }

    func uuid(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }

    func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    func roundTrip<Value: Codable>(_ value: Value) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
    }
}

private extension Collection {
    var single: Element? { count == 1 ? first : nil }
}
