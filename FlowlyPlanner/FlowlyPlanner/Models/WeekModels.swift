import Foundation
import SwiftData

enum Weekday: Int, CaseIterable, Identifiable, Codable {
    case monday = 0, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .monday: return "Ma"
        case .tuesday: return "Di"
        case .wednesday: return "Wo"
        case .thursday: return "Do"
        case .friday: return "Vr"
        case .saturday: return "Za"
        case .sunday: return "Zo"
        }
    }

    static var schoolDays: [Weekday] { [.monday, .tuesday, .wednesday, .thursday, .friday] }
}

@Model
final class ChildProfile {
    var name: String
    var storedSchoolDays: [Int]
    var bedtime: Date
    var maxStudyMinutesPerDay: Int

    init(
        name: String = "",
        schoolDays: [Weekday] = Weekday.schoolDays,
        bedtime: Date = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) ?? Date(),
        maxStudyMinutesPerDay: Int = 90
    ) {
        self.name = name
        self.storedSchoolDays = schoolDays.map { $0.rawValue }
        self.bedtime = bedtime
        self.maxStudyMinutesPerDay = maxStudyMinutesPerDay
    }

    var schoolDays: [Weekday] {
        get { storedSchoolDays.compactMap { Weekday(rawValue: $0) }.sorted(by: { $0.rawValue < $1.rawValue }) }
        set { storedSchoolDays = newValue.map { $0.rawValue } }
    }
}

@Model
final class Lesson {
    var subject: String
    var weekday: Int
    var startTime: Date
    var endTime: Date
    var profile: ChildProfile?

    init(subject: String, weekday: Weekday, startTime: Date, endTime: Date, profile: ChildProfile? = nil) {
        self.subject = subject
        self.weekday = weekday.rawValue
        self.startTime = startTime
        self.endTime = endTime
        self.profile = profile
    }

    var day: Weekday { Weekday(rawValue: weekday) ?? .monday }
}

@Model
final class HomeworkTask {
    var title: String
    var subject: String
    var deadline: Date
    var estimatedMinutes: Int
    var profile: ChildProfile?

    init(title: String, subject: String, deadline: Date, estimatedMinutes: Int, profile: ChildProfile? = nil) {
        self.title = title
        self.subject = subject
        self.deadline = deadline
        self.estimatedMinutes = estimatedMinutes
        self.profile = profile
    }
}

@Model
final class ExamPreparation {
    var subject: String
    var examDate: Date
    var blocksNeeded: Int
    var blockDurationMinutes: Int
    var profile: ChildProfile?

    init(subject: String, examDate: Date, blocksNeeded: Int, blockDurationMinutes: Int, profile: ChildProfile? = nil) {
        self.subject = subject
        self.examDate = examDate
        self.blocksNeeded = blocksNeeded
        self.blockDurationMinutes = blockDurationMinutes
        self.profile = profile
    }
}

struct PlanEvent: Identifiable {
    enum Kind { case lesson, homework, homeworkDue, study, breakTime, exam }
    let id: UUID
    let title: String
    let start: Date
    let end: Date
    let kind: Kind
}

struct WeekPlan {
    let weekStart: Date
    let events: [PlanEvent]
    let unplanned: [String]
}

struct PlannerSettings {
    var minBreakMinutes: Int = 10
    var defaultHomeworkBlock: Int = 30
}
