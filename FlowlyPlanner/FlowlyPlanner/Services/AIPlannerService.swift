import Foundation

struct AIPlannerResult: Decodable {
    let events: [AIPlannerEvent]
    let warnings: [String]?
}

struct AIPlannerEvent: Decodable {
    let title: String
    let start: String
    let end: String
    let kind: String?
}

enum AIPlannerError: Error, LocalizedError {
    case invalidURL
    case emptyResponse
    case dateParseFailed
    case missingStudyBlocks

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Ongeldige AI endpoint URL."
        case .emptyResponse: return "Lege AI-response."
        case .dateParseFailed: return "Kon tijden uit AI-response niet lezen."
        case .missingStudyBlocks: return "AI stuurde geen studie/huiswerkblokken terug."
        }
    }
}

final class AIPlannerService {
    private let calendar = Calendar.current

    func generatePlan(
        profile: ChildProfile,
        lessons: [Lesson],
        homeworkTasks: [HomeworkTask],
        exams: [ExamPreparation],
        endpoint: String
    ) async throws -> PlannerResult {
        guard let url = URL(string: endpoint) else { throw AIPlannerError.invalidURL }

        let payload = buildPayload(profile: profile, lessons: lessons, homeworkTasks: homeworkTasks, exams: exams)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "Onbekende fout"
            throw NSError(domain: "AIPlanner", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "AI call faalde: \(message)"])
        }

        guard !data.isEmpty else { throw AIPlannerError.emptyResponse }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let aiResponse = try decoder.decode(AIPlannerResult.self, from: data)

        let events = try aiResponse.events.compactMap { event -> PlanEvent in
            guard
                let startDate = ISO8601DateFormatter().date(from: event.start),
                let endDate = ISO8601DateFormatter().date(from: event.end)
            else {
                throw AIPlannerError.dateParseFailed
            }
            let kind = mapKind(event.kind)
            return PlanEvent(id: UUID(), title: event.title, start: startDate, end: endDate, kind: kind)
        }

        // Filter: verwijder AI-lessen (kind=lesson) of events (behalve examens) die exact over lessen heen vallen; behoud alle andere
        let studyEvents = events.filter { event in
            if event.kind == .lesson { return false }
            if event.kind != .exam && overlapsLesson(event, lessons: lessons) { return false }
            return true
        }

        if (!homeworkTasks.isEmpty || !exams.isEmpty) && studyEvents.isEmpty {
            throw AIPlannerError.missingStudyBlocks
        }

        // Altijd de originele lessen gebruiken, geen AI-lessen
        let originalLessons = lessons.map {
            PlanEvent(id: UUID(), title: $0.subject, start: $0.startTime, end: $0.endTime, kind: .lesson)
        }

        let combinedEvents = (studyEvents + originalLessons).sorted { $0.start < $1.start }
        let weekStart = startOfWeek(from: combinedEvents.map { $0.start }.min() ?? Date())
        return PlannerResult(plan: WeekPlan(weekStart: weekStart, events: combinedEvents, unplanned: aiResponse.warnings ?? []))
    }

    private func buildPayload(
        profile: ChildProfile,
        lessons: [Lesson],
        homeworkTasks: [HomeworkTask],
        exams: [ExamPreparation]
    ) -> AIRequestPayload {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return AIRequestPayload(
            timezone: TimeZone.current.identifier,
            profile: AIProfile(
                name: profile.name,
                schoolDays: profile.schoolDays.map { $0.rawValue },
                bedtime: isoFormatter.string(from: profile.bedtime),
                maxStudyMinutesPerDay: profile.maxStudyMinutesPerDay
            ),
            lessons: lessons.map { lesson in
                AILesson(
                    subject: lesson.subject,
                    weekday: lesson.weekday,
                    start: isoFormatter.string(from: lesson.startTime),
                    end: isoFormatter.string(from: lesson.endTime)
                )
            },
            homework: homeworkTasks.map { task in
                AIHomework(
                    title: task.title,
                    subject: task.subject,
                    deadline: isoFormatter.string(from: task.deadline),
                    estimatedMinutes: task.estimatedMinutes
                )
            },
            exams: exams.map { exam in
                AIExam(
                    subject: exam.subject,
                    examDate: isoFormatter.string(from: exam.examDate),
                    blocksNeeded: exam.blocksNeeded,
                    blockDurationMinutes: exam.blockDurationMinutes
                )
            }
        )
    }

    private func startOfWeek(from date: Date) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }

    private func mapKind(_ kind: String?) -> PlanEvent.Kind {
        guard let kind else { return .study }
        switch kind.lowercased() {
        case "lesson", "les": return .lesson
        case "homework": return .homework
        case "study": return .study
        case "exam", "toets": return .exam
        case "break": return .breakTime
        default: return .study
        }
    }

    private func isLessonEvent(_ event: PlanEvent, lessons: [Lesson]) -> Bool {
        return lessons.contains { lesson in
            abs(lesson.startTime.timeIntervalSince(event.start)) < 1 && abs(lesson.endTime.timeIntervalSince(event.end)) < 1
        }
    }

    private func isLessonTitle(_ title: String, lessons: [Lesson]) -> Bool {
        let lower = title.lowercased()
        return lessons.contains { $0.subject.lowercased() == lower }
    }

    private func overlapsLesson(_ event: PlanEvent, lessons: [Lesson]) -> Bool {
        for lesson in lessons {
            let overlaps = event.start < lesson.endTime && event.end > lesson.startTime
            if overlaps { return true }
        }
        return false
    }
}

// MARK: - Request payloads

private struct AIRequestPayload: Encodable {
    let timezone: String
    let profile: AIProfile
    let lessons: [AILesson]
    let homework: [AIHomework]
    let exams: [AIExam]
}

private struct AIProfile: Encodable {
    let name: String
    let schoolDays: [Int]
    let bedtime: String
    let maxStudyMinutesPerDay: Int
}

private struct AILesson: Encodable {
    let subject: String
    let weekday: Int
    let start: String
    let end: String
}

private struct AIHomework: Encodable {
    let title: String
    let subject: String
    let deadline: String
    let estimatedMinutes: Int
}

private struct AIExam: Encodable {
    let subject: String
    let examDate: String
    let blocksNeeded: Int
    let blockDurationMinutes: Int
}
