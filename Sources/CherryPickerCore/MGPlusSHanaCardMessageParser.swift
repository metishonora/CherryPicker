import Foundation

/// Parses the confirmed MG+S 하나카드 approval layout.
///
/// Cancellation is deliberately unsupported until a privacy-safe real layout
/// is confirmed. The value stored in `cardLast4` is the message's A*C* masked
/// identifier; the owning card definition resolves it against card instances.
public struct MGPlusSHanaCardMessageParser: Sendable {
    public static let currentParserVersion = "hana-mg-plus-s-message-v1"

    public let parserVersion: String

    public init(parserVersion: String = MGPlusSHanaCardMessageParser.currentParserVersion) {
        self.parserVersion = parserVersion
    }

    public func parse(_ originalMessage: String) -> ParseResult {
        let normalized = originalMessage
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return unsupported(originalMessage, reason: "The message is empty.")
        }
        if normalized.filter({ !$0.isWhitespace }).contains("승인취소") {
            return unsupported(
                originalMessage,
                reason: "MG+S cancellation messages are not supported yet."
            )
        }
        guard let match = firstMatch(in: normalized, pattern: Self.approvalPattern) else {
            return unsupported(
                originalMessage,
                reason: "No supported MG+S approval layout was found."
            )
        }
        guard
            let cardIdentifier = capture(1, from: match, in: normalized),
            let amountText = capture(2, from: match, in: normalized),
            let amount = integer(from: amountText),
            let monthText = capture(3, from: match, in: normalized),
            let month = Int(monthText),
            (1...12).contains(month),
            let dayText = capture(4, from: match, in: normalized),
            let day = Int(dayText),
            (1...31).contains(day),
            let hourText = capture(5, from: match, in: normalized),
            let hour = Int(hourText),
            (0...23).contains(hour),
            let minuteText = capture(6, from: match, in: normalized),
            let minute = Int(minuteText),
            (0...59).contains(minute),
            let merchantText = capture(7, from: match, in: normalized)
        else {
            return failed(originalMessage, reason: "The MG+S approval fields are invalid.")
        }

        let merchant = merchantText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !merchant.isEmpty else {
            return failed(originalMessage, reason: "The merchant name could not be identified.")
        }

        return .success(ParsedTransaction(
            kind: .approval,
            cardLast4: cardIdentifier,
            amount: amount,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            merchant: merchant,
            parserVersion: parserVersion,
            originalMessage: originalMessage
        ))
    }

    private static let approvalPattern = #"MG\+\s*하나\s*([0-9]\*[0-9]\*)\s*승인(?!취소)\s+\S+\s+([0-9][0-9,]*)\s*원\s+\S+\s+([0-9]{1,2})\s*/\s*([0-9]{1,2})\s+([0-9]{1,2})\s*:\s*([0-9]{2})\s+(.+?)\s+누적\s*[0-9][0-9,]*\s*원"#

    private func firstMatch(in value: String, pattern: String) -> NSTextCheckingResult? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        return expression.firstMatch(
            in: value,
            range: NSRange(value.startIndex..<value.endIndex, in: value)
        )
    }

    private func capture(
        _ index: Int,
        from match: NSTextCheckingResult,
        in value: String
    ) -> String? {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: value) else {
            return nil
        }
        return String(value[range])
    }

    private func integer(from value: String) -> Int? {
        let digits = value.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    private func unsupported(_ originalMessage: String, reason: String) -> ParseResult {
        .unsupported(ParseFailure(
            kind: .unsupported,
            originalMessage: originalMessage,
            reason: reason,
            parserVersion: parserVersion
        ))
    }

    private func failed(_ originalMessage: String, reason: String) -> ParseResult {
        .failed(ParseFailure(
            kind: .failed,
            originalMessage: originalMessage,
            reason: reason,
            parserVersion: parserVersion
        ))
    }
}
