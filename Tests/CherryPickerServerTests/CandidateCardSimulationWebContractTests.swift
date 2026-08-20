import Foundation
import XCTest

import Hummingbird
import HummingbirdTesting

@testable import CherryPickerServer

@available(macOS 14.0, *)
final class CandidateCardSimulationWebContractTests: XCTestCase, @unchecked Sendable {
    func testSimulationIsGlobalNavigationWhileCardViewsRemainCardScoped() {
        let html = ProductWebPage.render(transactions: [], receipts: [])

        XCTAssertTrue(html.contains("data-view=\"simulation\""))
        XCTAssertTrue(html.contains("data-view=\"simulation\">카드 시뮬레이션"))
        XCTAssertEqual(html.components(separatedBy: "data-card-scoped").count - 1, 4)
        XCTAssertTrue(html.contains("$$('[data-card-scoped]').forEach"))
        XCTAssertTrue(html.contains("view === 'inbox' || view === 'simulation'"))
        XCTAssertTrue(html.contains("state.selectedCardId = null"))
        XCTAssertTrue(html.contains("return showView('inbox')"))
    }

    func testSimulationSurfacePreservesApprovedThreeStepAndAccessibilityBoundaries() {
        let html = ProductWebPage.render(transactions: [], receipts: [])

        XCTAssertTrue(html.contains("id=\"simulation-empty\""))
        XCTAssertTrue(html.contains("id=\"simulation-load-error\""))
        XCTAssertTrue(html.contains("id=\"simulation-retry\""))
        XCTAssertTrue(html.contains("id=\"simulation-draft\""))
        XCTAssertEqual(html.components(separatedBy: "data-simulation-step=").count - 1, 3)
        XCTAssertTrue(html.contains("id=\"simulation-screen-policy\""))
        XCTAssertTrue(html.contains("id=\"simulation-screen-questions\""))
        XCTAssertTrue(html.contains("id=\"simulation-screen-transactions\""))
        XCTAssertTrue(html.contains("id=\"simulation-calculation-details\""))
        XCTAssertTrue(html.contains("id=\"simulation-transaction-list\""))
        XCTAssertTrue(html.contains("id=\"simulation-benefit-policy-rules\""))
        XCTAssertTrue(html.contains("aria-labelledby=\"simulation-summary-title\""))
        XCTAssertEqual(html.components(separatedBy: "aria-live=\"polite\"").count - 1, 1)
        XCTAssertFalse(html.contains("review-screen"))
        XCTAssertFalse(html.contains("id=\"scenario\""))
    }

    func testSimulationFragmentKeepsServerAsCalculationAuthorityAndUsesSafeDOMBoundary() {
        let script = CandidateCardSimulationWeb.script

        XCTAssertTrue(script.contains("/api/v1/candidate-simulations/current"))
        XCTAssertTrue(script.contains("response.status === 404"))
        XCTAssertTrue(script.contains("method: 'PATCH'"))
        XCTAssertTrue(script.contains("const body = { ...patch, draftId: simulation.id, expectedState: simulation.state };"))
        XCTAssertTrue(script.contains("body: JSON.stringify(body)"))
        XCTAssertFalse(script.contains("body: JSON.stringify(patch)"))
        XCTAssertTrue(script.contains("candidateSimulationResponse = response"))
        XCTAssertTrue(script.contains("calculation.benefitAmount"))
        XCTAssertTrue(script.contains("calculation.pickingRatePercentage"))
        XCTAssertTrue(script.contains("result.appliedBenefitAmount"))
        XCTAssertTrue(script.contains("result.rawBenefitAmount.maximum > 0"))
        XCTAssertTrue(script.contains("result.benefits"))
        XCTAssertTrue(script.contains("result.benefitBreakdownIsAdditive"))
        XCTAssertTrue(script.contains("result.benefitBreakdownIsAdditive && result.benefits.length > 0"))
        XCTAssertTrue(script.contains("label: '전체 예상 혜택'"))
        XCTAssertTrue(script.contains("!result.benefitBreakdownIsAdditive && result.benefits.length > 0"))
        XCTAssertTrue(script.contains("allocation.benefitID"))
        XCTAssertTrue(script.contains("benefitByID.get(allocation.benefitID)?.label"))
        XCTAssertTrue(script.contains("policy.performanceExclusions"))
        XCTAssertTrue(script.contains("policy.benefitExclusions"))
        XCTAssertTrue(script.contains("benefit.conditionSummary"))
        XCTAssertTrue(script.contains("benefit.exclusionNotes"))
        XCTAssertTrue(script.contains("benefit.rateBasisPoints"))
        XCTAssertTrue(script.contains("benefit.minimumTransactionAmount"))
        XCTAssertTrue(script.contains("benefit.maximumTransactionAmount"))
        XCTAssertTrue(script.contains("benefit.perTransactionMaximumBenefitAmount"))
        XCTAssertTrue(script.contains("benefit.monthlyCountLimit"))
        XCTAssertTrue(script.contains("benefit.limitGroupIDs"))
        XCTAssertTrue(script.contains("benefit.priority"))
        XCTAssertTrue(script.contains("benefit.rounding"))
        XCTAssertTrue(script.contains("candidateStackingRuleLabel(policy.stacking)"))
        XCTAssertTrue(script.contains("candidateRoundingRuleLabel(benefit.rounding)"))
        XCTAssertTrue(script.contains("'제한 없음'"))
        XCTAssertTrue(script.contains("values.length > 0 ? values.join(' · ') : '월 한도 없음'"))
        XCTAssertTrue(script.contains("checkbox.setAttribute("))
        XCTAssertTrue(script.contains("'aria-label'"))
        XCTAssertTrue(script.contains("textContent"))
        XCTAssertTrue(script.contains("replaceChildren"))
        XCTAssertFalse(script.contains("innerHTML"))
        XCTAssertFalse(script.contains("insertAdjacentHTML"))
        XCTAssertFalse(script.contains("rawBenefitFor"))
        XCTAssertFalse(script.contains("allocateBenefits"))
        XCTAssertFalse(script.contains("pickingRate ="))
        XCTAssertFalse(script.contains("alternatives.some(value => value.benefitIDs.length > 0)"))
    }

    func testSimulationLoadFailureStopsLoadingAndOffersAnAnnouncedRetry() {
        let script = CandidateCardSimulationWeb.script

        XCTAssertTrue(script.contains("function candidateShowLoadError()"))
        XCTAssertTrue(script.contains("$('#simulation-loading').hidden = true"))
        XCTAssertTrue(script.contains("$('#simulation-load-error').hidden = false"))
        XCTAssertTrue(script.contains("toast('시뮬레이션을 불러오지 못했습니다. 다시 시도해 주세요.')"))
        XCTAssertTrue(script.contains("candidateRestoreFocus({ type: 'id', id: 'simulation-retry' })"))
        XCTAssertTrue(script.contains("} catch (error) {"))
        XCTAssertEqual(
            script.components(separatedBy: "candidateShowLoadError();").count - 1,
            1
        )
        XCTAssertTrue(script.contains("$('#simulation-retry').addEventListener('click', () => loadCandidateCardSimulation())"))
    }

    func testPatchSuccessAnnouncesServerReturnedCalculationAndQuestionLinksTargetTheirTransaction() {
        let script = CandidateCardSimulationWeb.script

        XCTAssertTrue(script.contains("function candidateCalculationAnnouncement(response, message)"))
        XCTAssertTrue(script.contains("calculation.selectedTransactionCount"))
        XCTAssertTrue(script.contains("candidateWonRange(calculation.benefitAmount)"))
        XCTAssertTrue(script.contains("candidateRateRange(calculation.pickingRatePercentage)"))
        XCTAssertTrue(script.contains("toast(candidateCalculationAnnouncement(response, options.message))"))
        XCTAssertTrue(script.contains("type: 'question'"))
        XCTAssertTrue(script.contains("transactionID: classification.transactionID"))
        XCTAssertTrue(script.contains("element?.scrollIntoView({ block: 'center' })"))
        XCTAssertFalse(script.contains("review.addEventListener('click', () => candidateSetStep('questions', true))"))
    }

    func testAuthenticatedProductEntryComposesSimulationIntoTheRealRootRoute() async throws {
        let databaseURL = try candidateTemporaryDatabaseURL()
        defer { candidateRemoveDatabaseFiles(at: databaseURL) }
        let store = try SQLiteEventStore(databaseURL: databaseURL)
        let app = try CherryPickerHTTPApplication(
            store: store,
            authorizer: TailscaleIdentityAuthorizer(
                allowedLogin: "candidate-ui-fixture@example.test"
            ),
            codec: OutboxJSONCodec()
        ).application

        try await app.test(.router) { client in
            var headers: HTTPFields = [:]
            headers[.init("Tailscale-User-Login")!] = "candidate-ui-fixture@example.test"
            try await client.execute(uri: "/", method: .get, headers: headers) { response in
                XCTAssertEqual(response.status, .ok)
                let html = String(decoding: response.body.readableBytesView, as: UTF8.self)
                XCTAssertTrue(html.contains("data-view=\"simulation\""))
                XCTAssertTrue(html.contains("id=\"view-simulation\""))
                XCTAssertTrue(html.contains("/api/v1/candidate-simulations/current"))
                XCTAssertTrue(html.contains("loadCards().then"))
                XCTAssertTrue(html.contains("return showView('inbox')"))
            }
        }
    }

    private func candidateTemporaryDatabaseURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CandidateCardSimulationWebContractTests-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        return url
    }

    private func candidateRemoveDatabaseFiles(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
}
