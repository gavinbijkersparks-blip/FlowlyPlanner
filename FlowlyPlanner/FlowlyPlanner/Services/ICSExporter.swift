import Foundation

struct ICSExporter {
    func export(events: [PlanEvent]) -> String {
        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//WeekplannerKids//MVP//NL"
        ]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]

        for event in events {
            let uid = event.id.uuidString
            let start = formatter.string(from: event.start)
            let end = formatter.string(from: event.end)
            lines.append(contentsOf: [
                "BEGIN:VEVENT",
                "UID:\(uid)",
                "SUMMARY:\(event.title)",
                "DTSTART:\(start)",
                "DTEND:\(end)",
                "BEGIN:VALARM",
                "TRIGGER:-PT10M",
                "ACTION:DISPLAY",
                "DESCRIPTION:Reminder",
                "END:VALARM",
                "END:VEVENT"
            ])
        }
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\n")
    }
}
