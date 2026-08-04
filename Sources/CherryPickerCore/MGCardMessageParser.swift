import Foundation

/// A Foundation-only parser for MG 더나은 체크카드 approval and cancellation
/// notification messages.
public struct MGCardMessageParser: Sendable {
    /// Bump this value whenever the extraction rules change. Persisting it with
    /// a transaction makes later re-parsing or diagnosis possible.
    public static let currentParserVersion = "mg-card-message-v2"

    public let parserVersion: String

    public init(parserVersion: String = MGCardMessageParser.currentParserVersion) {
        self.parserVersion = parserVersion
    }

    /// Parses a message without throwing. The original input is retained in
    /// either the successful transaction or the failure value.
    public func parse(_ originalMessage: String) -> ParseResult {
        let lines = normalizedLines(from: originalMessage)
        let compactMessage = lines.joined().filter { !$0.isWhitespace }

        guard !lines.isEmpty, !compactMessage.isEmpty else {
            return unsupported(originalMessage, reason: "The message is empty.")
        }

        // Check cancellation first because a cancellation can contain the word
        // approval in a quoted or explanatory line in some carrier variants.
        let kind: TransactionKind
        if compactMessage.contains("승인취소") {
            kind = .cancellation
        } else if compactMessage.contains("체크승인") {
            kind = .approval
        } else {
            return unsupported(originalMessage, reason: "No supported MG approval or cancellation marker was found.")
        }

        guard let cardLast4 = capture(
            1,
            from: firstMatch(in: originalMessage, pattern: Self.cardPattern),
            in: originalMessage
        ) else {
            return failed(originalMessage, reason: "The MG card suffix (four digits) could not be read.")
        }

        guard let amountMatch = firstAmountMatch(in: lines) else {
            return failed(originalMessage, reason: "The transaction amount could not be read.")
        }
        guard let transactionAmount = amount(from: amountMatch.match, in: amountMatch.line) else {
            return failed(originalMessage, reason: "The transaction amount is not a valid integer number of won.")
        }

        guard let dateMatch = firstDateMatch(in: lines, startingAt: amountMatch.lineIndex) else {
            return failed(originalMessage, reason: "The transaction month and day could not be read.")
        }

        guard let merchant = merchant(
            in: lines,
            dateMatch: dateMatch,
            kind: kind
        ) else {
            return failed(originalMessage, reason: "The merchant name could not be identified.")
        }

        let accountBalance: Int?
        if kind == .approval {
            accountBalance = lines
                .first(where: { compact($0).contains("통장잔액") })
                .flatMap { balance in
                    firstMatch(in: balance, pattern: Self.balancePattern)
                        .flatMap { amount(from: $0, in: balance) }
                }
        } else {
            accountBalance = nil
        }

        let transaction = ParsedTransaction(
            kind: kind,
            cardLast4: cardLast4,
            amount: transactionAmount,
            month: dateMatch.month,
            day: dateMatch.day,
            hour: kind == .approval ? dateMatch.hour : nil,
            minute: kind == .approval ? dateMatch.minute : nil,
            merchant: merchant,
            accountBalance: accountBalance,
            parserVersion: parserVersion,
            originalMessage: originalMessage
        )
        return .success(transaction)
    }

    /// A Result-shaped API for callers that prefer typed failures.
    public func parseResult(_ originalMessage: String) -> Result<ParsedTransaction, ParseError> {
        switch parse(originalMessage) {
        case let .success(transaction):
            return .success(transaction)
        case let .unsupported(failure):
            return .failure(.unsupported(failure))
        case let .failed(failure):
            return .failure(.failed(failure))
        }
    }

    /// A conventional throwing API. `parse(_:)` remains the recommended API for
    /// ingestion pipelines where a malformed notification must not interrupt
    /// saving the original message.
    public func parseThrowing(_ originalMessage: String) throws -> ParsedTransaction {
        switch parse(originalMessage) {
        case let .success(transaction):
            return transaction
        case let .unsupported(failure):
            throw ParseError.unsupported(failure)
        case let .failed(failure):
            throw ParseError.failed(failure)
        }
    }

    // MARK: - Patterns and extraction helpers

    private static let cardPattern = #"MG\s*(?:더\s*나은\s*)?(?:체크\s*)?카드\s*\(\s*([0-9]{4})\s*\)"#
    private static let amountPattern = #"(?<![0-9])([0-9][0-9,\.\s]*)\s*원"#
    private static let balancePattern = #"통장\s*잔액\s*([0-9][0-9,\.\s]*)\s*원"#
    private static let datePattern = #"(?<![0-9])([0-9]{1,2})\s*[/.-]\s*([0-9]{1,2})(?![0-9])"#
    private static let timePattern = #"(?<![0-9])([0-9]{1,2})\s*:\s*([0-9]{2})(?![0-9])"#

    private struct AmountMatch {
        let line: String
        let lineIndex: Int
        let match: NSTextCheckingResult
    }

    private struct DateMatch {
        let line: String
        let lineIndex: Int
        let dateRange: Range<String.Index>
        let suffixRange: Range<String.Index>
        let month: Int
        let day: Int
        let hour: Int?
        let minute: Int?
    }

    private func normalizedLines(from originalMessage: String) -> [String] {
        let normalized = originalMessage
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        return normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func firstAmountMatch(in lines: [String]) -> AmountMatch? {
        for (lineIndex, line) in lines.enumerated() {
            // Shortcuts can flatten the entire message to one line. Choose an
            // amount before the balance marker instead of skipping that whole
            // line, while still ignoring a standalone balance line.
            let balanceLocation = firstMatch(in: line, pattern: Self.balancePattern)?.range.location
            if let match = allMatches(in: line, pattern: Self.amountPattern).first(where: {
                guard let balanceLocation else { return true }
                return $0.range.location < balanceLocation
            }) {
                return AmountMatch(line: line, lineIndex: lineIndex, match: match)
            }
        }
        return nil
    }

    private func firstDateMatch(in lines: [String], startingAt start: Int) -> DateMatch? {
        guard !lines.isEmpty else { return nil }
        let firstIndex = max(0, min(start, lines.count - 1))
        for lineIndex in firstIndex..<lines.count {
            let line = lines[lineIndex]
            guard let date = firstMatch(in: line, pattern: Self.datePattern),
                  let monthText = capture(1, from: date, in: line),
                  let dayText = capture(2, from: date, in: line),
                  let month = Int(monthText),
                  let day = Int(dayText),
                  (1...12).contains(month),
                  (1...31).contains(day),
                  let dateRange = Range(date.range, in: line) else {
                continue
            }

            var suffixEnd = dateRange.upperBound
            var hour: Int?
            var minute: Int?
            let dateSuffix = String(line[dateRange.upperBound...])
            if let time = firstMatch(in: dateSuffix, pattern: Self.timePattern),
               let hourText = capture(1, from: time, in: dateSuffix),
               let minuteText = capture(2, from: time, in: dateSuffix),
               let parsedHour = Int(hourText),
               let parsedMinute = Int(minuteText),
               (0...23).contains(parsedHour),
               (0...59).contains(parsedMinute),
               let timeRange = Range(time.range, in: dateSuffix) {
                hour = parsedHour
                minute = parsedMinute
                let suffixDistance = dateSuffix.distance(
                    from: dateSuffix.startIndex,
                    to: timeRange.upperBound
                )
                suffixEnd = line.index(dateRange.upperBound, offsetBy: suffixDistance)
            }

            return DateMatch(
                line: line,
                lineIndex: lineIndex,
                dateRange: dateRange,
                suffixRange: suffixEnd..<line.endIndex,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        }
        return nil
    }

    private func merchant(in lines: [String], dateMatch: DateMatch, kind: TransactionKind) -> String? {
        // Some gateways put the next field after a period on the same line as
        // the date. Use it when it is clearly a merchant, but skip cancellation
        // status text such as "취소완료".
        let suffix = String(dateMatch.line[dateMatch.suffixRange])
        if let candidate = merchantCandidate(suffix), !isStatus(candidate) {
            return candidate
        }

        if dateMatch.lineIndex + 1 < lines.count {
            for line in lines[(dateMatch.lineIndex + 1)...] {
                let candidate = merchantCandidate(line)
                guard let candidate, !isStatus(candidate) else { continue }
                if compact(candidate).contains("통장잔액") { continue }
                return candidate
            }
        }

        // `kind` is intentionally consumed here to make the distinction
        // explicit at the call site; both kinds currently use the same layout
        // after the date, while retaining this parameter allows future variants
        // to diverge without changing parse(_:)'s control flow.
        _ = kind
        return nil
    }

    private func merchantCandidate(_ value: String) -> String? {
        var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)

        // A flattened approval has the balance after the merchant on the same
        // line. It is not part of the merchant name.
        if let balanceRange = candidate.range(
            of: #"통장\s*잔액"#,
            options: .regularExpression
        ) {
            candidate = String(candidate[..<balanceRange.lowerBound])
        }

        // A flattened cancellation keeps the status marker between the date
        // and merchant. Remove only a leading marker and its separators.
        candidate = candidate.replacingOccurrences(
            of: #"^\s*[.·]*\s*취소\s*완료\s*[.·]*\s*"#,
            with: "",
            options: .regularExpression
        )
        candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: ".·"))
        candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? nil : candidate
    }

    private func isStatus(_ value: String) -> Bool {
        let normalized = compact(value)
        return normalized == "취소완료"
            || normalized == "승인취소"
            || normalized == "체크승인"
            || normalized.contains("통장잔액")
            || normalized == "원"
    }

    private func amount(from match: NSTextCheckingResult, in line: String) -> Int? {
        guard let text = capture(1, from: match, in: line) else { return nil }
        let digits = text.filter { $0 >= "0" && $0 <= "9" }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    private func compact(_ value: String) -> String {
        value.filter { !$0.isWhitespace }
    }

    private func firstMatch(in value: String, pattern: String) -> NSTextCheckingResult? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.firstMatch(in: value, options: [], range: range)
    }

    private func allMatches(in value: String, pattern: String) -> [NSTextCheckingResult] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, options: [], range: range)
    }

    private func capture(
        _ index: Int,
        from match: NSTextCheckingResult?,
        in value: String
    ) -> String? {
        guard let match, index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: value) else {
            return nil
        }
        return String(value[range])
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
