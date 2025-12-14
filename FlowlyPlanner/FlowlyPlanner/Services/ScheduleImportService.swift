import Foundation
import Vision
import UIKit

struct ParsedLesson {
    let weekday: Weekday
    let subjectRaw: String
    let subject: String?
    let start: Date
    let end: Date
}

final class ScheduleImportService {
    private let calendar = Calendar.current

    func parse(image: UIImage, weekday: Weekday) async throws -> [ParsedLesson] {
        let text = try await recognizeText(in: image)
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parse(lines: lines, weekday: weekday)
    }

    private func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { return "" }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let text = request.results?
                    .compactMap { $0 as? VNRecognizedTextObservation }
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func parse(lines: [String], weekday: Weekday) -> [ParsedLesson] {
        let baseDay = calendar.startOfDay(for: Date())
        var parsed: [ParsedLesson] = []
        var pendingSubject: String?

        for line in lines {
            if let times = extractTimes(from: line) {
                let subjectLine = pendingSubject ?? line
                pendingSubject = nil
                let startString = times.start.replacingOccurrences(of: ".", with: ":")
                let endString = times.end.replacingOccurrences(of: ".", with: ":")
                guard
                    let startDate = time(from: startString, on: baseDay),
                    let endDate = time(from: endString, on: baseDay)
                else { continue }
                let subjectRaw = subjectLine.trimmingCharacters(in: .whitespacesAndNewlines)
                let subjectCode = extractSubjectCode(from: subjectRaw)
                let subject = normalizeSubject(subjectCode ?? subjectRaw) ?? subjectCode ?? subjectRaw
                parsed.append(ParsedLesson(weekday: weekday, subjectRaw: subjectRaw, subject: subject, start: startDate, end: endDate))
            } else {
                pendingSubject = line
            }
        }
        return parsed.sorted { $0.start < $1.start }
    }

    private func extractTimes(from line: String) -> (start: String, end: String)? {
        let patterns = [
            #"(?i)(\d{1,2}[:.]\d{2})\s*[-–]\s*(\d{1,2}[:.]\d{2})"#,
            #"(?i)(\d{1,2})[:.](\d{2})\s*[-–]\s*(\d{1,2})[:.](\d{2})"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(location: 0, length: line.utf16.count)
                if let match = regex.firstMatch(in: line, options: [], range: range),
                   match.numberOfRanges >= 3,
                   let startRange = Range(match.range(at: 1), in: line),
                   let endRange = Range(match.range(at: pattern == patterns[1] ? 3 : 2), in: line) {
                    return (String(line[startRange]), String(line[endRange]))
                }
            }
        }
        return nil
    }

    private func time(from string: String, on day: Date) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateFormat = "HH:mm"
        if let date = formatter.date(from: string) {
            return calendar.date(bySettingHour: calendar.component(.hour, from: date), minute: calendar.component(.minute, from: date), second: 0, of: day)
        }
        return nil
    }

    private func normalizeSubject(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = trimmed.uppercased()
        let mapping: [String: String] = [
            "WI": "Wiskunde",
            "NED": "Nederlands",
            "NL": "Nederlands",
            "ENG": "Engels",
            "EN": "Engels",
            "BIO": "Biologie",
            "NATUURKUNDE": "Natuurkunde",
            "NA": "Natuurkunde",
            "SCHEIKUNDE": "Scheikunde",
            "SK": "Scheikunde",
            "GES": "Geschiedenis",
            "GS": "Geschiedenis",
            "AK": "Aardrijkskunde",
            "ECO": "Economie",
            "LO": "Lichamelijke opvoeding"
        ]
        if let mapped = mapping[upper] { return mapped }
        if trimmed.count <= 3 { return nil }
        return trimmed
    }

    private func extractSubjectCode(from raw: String) -> String? {
        let separators: [Character] = ["–", "-", "—"]
        let parts = raw.split(whereSeparator: { separators.contains($0) })
        guard let first = parts.first else { return nil }
        return String(first).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
