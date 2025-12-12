import Foundation

struct PlannerResult {
    let plan: WeekPlan
}

final class PlannerService {
    private let calendar: Calendar
    private let settings: PlannerSettings

    init(calendar: Calendar = .current, settings: PlannerSettings = PlannerSettings()) {
        self.calendar = calendar
        self.settings = settings
    }

    func generatePlan(
        profile: ChildProfile,
        lessons: [Lesson],
        homeworkTasks: [HomeworkTask],
        exams: [ExamPreparation]
    ) -> PlannerResult {
        let weekStart = startOfWeek()
        var availability = buildInitialAvailability(profile: profile, weekStart: weekStart, lessons: lessons)
        // Block lessons
        for lesson in lessons {
            guard let date = calendar.date(byAdding: .day, value: lesson.day.rawValue, to: weekStart) else { continue }
            let start = combine(time: lesson.startTime, with: date)
            let end = combine(time: lesson.endTime, with: date)
            availability[lesson.day] = removeInterval(availability[lesson.day] ?? [], removing: DateInterval(start: start, end: end))
        }

        var events: [PlanEvent] = []
        var unplanned: [String] = []
        var perDayMinutes: [Weekday: Int] = [:]

        // Place homework by deadline (earliest first)
        let sortedHomework = homeworkTasks.sorted { $0.deadline < $1.deadline }
        for task in sortedHomework {
            var remaining = task.estimatedMinutes
            var currentDate = min(task.deadline, endOfWeek(for: weekStart))
            while remaining > 0, currentDate >= weekStart {
                let day = weekday(for: currentDate)
                if perDayMinutes[day, default: 0] >= profile.maxStudyMinutesPerDay {
                    currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate) ?? weekStart
                    continue
                }
                let duration = min(settings.defaultHomeworkBlock, remaining)
                if var windows = availability[day], let slot = placeBlock(durationMinutes: duration, on: &windows) {
                    availability[day] = windows
                    events.append(PlanEvent(
                        id: UUID(),
                        title: "Huiswerk – \(task.subject)",
                        start: slot.start,
                        end: slot.end,
                        kind: .homework
                    ))
                    perDayMinutes[day, default: 0] += duration
                    remaining -= duration
                } else {
                    currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate) ?? weekStart
                }
            }
            if remaining > 0 {
                unplanned.append(task.title)
            }
        }

        // Place exam prep blocks spread backwards from exam date
        for exam in exams {
            var blocksLeft = exam.blocksNeeded
            var currentDate = min(exam.examDate, endOfWeek(for: weekStart))
            while blocksLeft > 0, currentDate >= weekStart {
                let day = weekday(for: currentDate)
                if perDayMinutes[day, default: 0] >= profile.maxStudyMinutesPerDay {
                    currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate) ?? weekStart
                    continue
                }
                if var windows = availability[day], let slot = placeBlock(durationMinutes: exam.blockDurationMinutes, on: &windows) {
                    availability[day] = windows
                    events.append(PlanEvent(
                        id: UUID(),
                        title: "Leren – \(exam.subject)",
                        start: slot.start,
                        end: slot.end,
                        kind: .study
                    ))
                    perDayMinutes[day, default: 0] += exam.blockDurationMinutes
                    blocksLeft -= 1
                } else {
                    currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate) ?? weekStart
                }
            }
            if blocksLeft > 0 {
                unplanned.append("Toets: \(exam.subject)")
            }
        }

        // Add lessons as events for display
        for lesson in lessons {
            guard let date = calendar.date(byAdding: .day, value: lesson.day.rawValue, to: weekStart) else { continue }
            let start = combine(time: lesson.startTime, with: date)
            let end = combine(time: lesson.endTime, with: date)
            events.append(PlanEvent(id: UUID(), title: "Les – \(lesson.subject)", start: start, end: end, kind: .lesson))
        }

        // Add exam events for display (1 uur blok op examDate)
        for exam in exams {
            let start = exam.examDate
            let end = calendar.date(byAdding: .minute, value: 60, to: start) ?? start.addingTimeInterval(3600)
            events.append(PlanEvent(id: UUID(), title: "Toets – \(exam.subject)", start: start, end: end, kind: .exam))
        }

        let sortedEvents = events.sorted { $0.start < $1.start }
        return PlannerResult(plan: WeekPlan(weekStart: weekStart, events: sortedEvents, unplanned: unplanned))
    }

    private func startOfWeek() -> Date {
        let now = Date()
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        return calendar.date(from: components) ?? now
    }

    private func endOfWeek(for weekStart: Date) -> Date {
        calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
    }

    private func weekday(for date: Date) -> Weekday {
        let start = startOfWeek()
        let diff = calendar.dateComponents([.day], from: start, to: date).day ?? 0
        return Weekday(rawValue: max(0, min(6, diff))) ?? .monday
    }

    private func buildInitialAvailability(profile: ChildProfile, weekStart: Date, lessons: [Lesson]) -> [Weekday: [DateInterval]] {
        var availability: [Weekday: [DateInterval]] = [:]
        let bedtimeComponents = calendar.dateComponents([.hour, .minute], from: profile.bedtime)
        let lessonsByDay = Dictionary(grouping: lessons, by: { $0.day })

        for day in Weekday.allCases {
            let isSchoolDay = profile.schoolDays.contains(day)
            let dayLessons = lessonsByDay[day] ?? []

            // Start na laatste les of minimaal 16:00 op schooldagen, anders 09:00
            let defaultSchoolStart = timeOfDay(hour: 16, minute: 0, on: weekStart, dayOffset: day.rawValue)
            let lastLessonEnd = dayLessons
                .map { combine(time: $0.endTime, with: calendar.date(byAdding: .day, value: day.rawValue, to: weekStart) ?? weekStart) }
                .max()
            let startDate: Date
            if isSchoolDay {
                startDate = max(lastLessonEnd ?? defaultSchoolStart, defaultSchoolStart)
            } else {
                startDate = timeOfDay(hour: 9, minute: 0, on: weekStart, dayOffset: day.rawValue)
            }

            guard
                let baseDate = calendar.date(byAdding: .day, value: day.rawValue, to: weekStart),
                let dayEnd = calendar.date(bySettingHour: bedtimeComponents.hour ?? 21, minute: bedtimeComponents.minute ?? 0, second: 0, of: baseDate)
            else { continue }
            if startDate < dayEnd {
                availability[day] = [DateInterval(start: startDate, end: dayEnd)]
            } else {
                availability[day] = []
            }
        }
        return availability
    }

    private func combine(time: Date, with day: Date) -> Date {
        let components = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: day) ?? day
    }

    private func timeOfDay(hour: Int, minute: Int, on weekStart: Date, dayOffset: Int) -> Date {
        let baseDate = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) ?? weekStart
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDate) ?? baseDate
    }

    private func placeBlock(durationMinutes: Int, on intervals: inout [DateInterval]) -> DateInterval? {
        let duration = TimeInterval(durationMinutes * 60)
        intervals.sort { $0.start < $1.start }
        for (index, interval) in intervals.enumerated() {
            if interval.duration >= duration {
                let start = interval.start
                let end = start.addingTimeInterval(duration)
                let breakDuration = TimeInterval(settings.minBreakMinutes * 60)
                var newIntervals: [DateInterval] = []
                if interval.start < start {
                    newIntervals.append(DateInterval(start: interval.start, end: start))
                }
                let afterStart = end.addingTimeInterval(breakDuration)
                if afterStart < interval.end {
                    newIntervals.append(DateInterval(start: afterStart, end: interval.end))
                }
                intervals.remove(at: index)
                intervals.insert(contentsOf: newIntervals, at: index)
                return DateInterval(start: start, end: end)
            }
        }
        return nil
    }

    private func removeInterval(_ intervals: [DateInterval], removing: DateInterval) -> [DateInterval] {
        var updated: [DateInterval] = []
        for interval in intervals {
            if removing.end <= interval.start || removing.start >= interval.end {
                updated.append(interval)
                continue
            }
            if removing.start > interval.start {
                updated.append(DateInterval(start: interval.start, end: removing.start))
            }
            if removing.end < interval.end {
                updated.append(DateInterval(start: removing.end, end: interval.end))
            }
        }
        return updated.sorted { $0.start < $1.start }
    }
}
