import SwiftUI
import SwiftData
import UIKit

struct PlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var profileStore: ProfileSelectionStore
    @Query private var profiles: [ChildProfile]
    @Query(sort: \Lesson.weekday) private var lessons: [Lesson]
    @Query private var homework: [HomeworkTask]
    @Query private var exams: [ExamPreparation]

    @State private var weekPlan: WeekPlan?
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var warning: String?
    @State private var useAIPlanner = false
    @State private var aiEndpoint: String = "https://bijkersparks.nl/api/ai-planner.php"
    @State private var isGenerating = false
    @State private var aiPlanUsed: Bool?

    private let plannerService = PlannerService()
    private let aiPlannerService = AIPlannerService()
    private let exporter = ICSExporter()

    private var activeProfile: ChildProfile? {
        guard let id = profileStore.selectedProfileID else { return nil }
        return profiles.first(where: { $0.persistentModelID == id })
    }

    private var filteredLessons: [Lesson] {
        guard let id = profileStore.selectedProfileID else { return lessons }
        return lessons.filter { $0.profile?.persistentModelID == id || $0.profile == nil }
    }
    private var filteredHomework: [HomeworkTask] {
        guard let id = profileStore.selectedProfileID else { return homework }
        return homework.filter { $0.profile?.persistentModelID == id || $0.profile == nil }
    }
    private var filteredExams: [ExamPreparation] {
        guard let id = profileStore.selectedProfileID else { return exams }
        return exams.filter { $0.profile?.persistentModelID == id || $0.profile == nil }
    }

    var body: some View {
        VStack {
            if let profile = activeProfile {
                profileChip(profile)
            } else {
                Text("Selecteer een profiel via het avatar-overzicht.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            settingsRow
            debugInfo
            if let plan = weekPlan {
                planList(plan)
            } else {
                ContentUnavailableView(
                    "Geen planning",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Voer profiel, rooster en taken in en genereer een weekplanning.")
                )
            }
            if let warning = warning {
                Text(warning)
                    .foregroundStyle(.orange)
                    .padding()
            }
            Spacer()
        }
        .navigationTitle("Planner")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink(destination: ProfileView()) {
                    Image(systemName: "person.crop.circle")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        generatePlan()
                    } label: {
                        if isGenerating {
                            Label("Bezig…", systemImage: "hourglass")
                        } else {
                            Label("Genereer", systemImage: "sparkles")
                        }
                    }
                    if weekPlan != nil {
                        Button("Export .ics", action: exportPlan)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = shareURL {
                ShareSheet(activityItems: [url])
            }
        }
    }

    @ViewBuilder
    private func planList(_ plan: WeekPlan) -> some View {
        List {
            ForEach(upcomingDays(), id: \.self) { day in
                let dayEvents = plan.events
                    .filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
                    .filter { $0.kind != .lesson } // Toon alleen huiswerk/studie/toets, geen lessen
                Section(header: Text(dateLabel(for: day))) {
                    if dayEvents.isEmpty {
                        Text("Geen blokken")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(dayEvents) { event in
                            HStack(spacing: 12) {
                                icon(for: event)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(event.title)
                                        .font(.headline)
                                    Text("\(timeString(event.start)) – \(timeString(event.end))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(background(for: event))
                            .cornerRadius(12)
                        }
                    }
                }
            }
            if !plan.unplanned.isEmpty {
                Section(header: Text("Niet ingepland")) {
                    ForEach(plan.unplanned, id: \.self) { item in
                        Text(item)
                    }
                }
            }
        }
    }

    private func generatePlan() {
        guard let profile = profiles.first else {
            warning = "Maak eerst een kindprofiel"
            return
        }
        guard let activeProfile = activeProfile else {
            warning = "Selecteer een profiel via het avatar-overzicht"
            return
        }
        warning = nil
        isGenerating = true

        if useAIPlanner {
            Task {
                do {
                    let result = try await aiPlannerService.generatePlan(
                        profile: activeProfile,
                        lessons: filteredLessons,
                        homeworkTasks: filteredHomework,
                        exams: filteredExams,
                        endpoint: aiEndpoint
                    )
                    await MainActor.run {
                        weekPlan = result.plan
                        warning = result.plan.unplanned.isEmpty ? nil : result.plan.unplanned.joined(separator: "\n")
                        isGenerating = false
                        aiPlanUsed = true
                    }
                } catch {
                    if let aiError = error as? AIPlannerError, aiError == .missingStudyBlocks {
                        await MainActor.run {
                            warning = "AI gaf geen studie/huiswerkblokken. Valt terug op lokale planner."
                        }
                        let result = plannerService.generatePlan(profile: profile, lessons: lessons, homeworkTasks: homework, exams: exams)
                        await MainActor.run {
                            weekPlan = result.plan
                            isGenerating = false
                            aiPlanUsed = false
                        }
                        return
                    }
                    await MainActor.run {
                        warning = "AI planner faalde: \(error.localizedDescription)"
                        isGenerating = false
                    }
                }
            }
        } else {
            let result = plannerService.generatePlan(profile: activeProfile, lessons: filteredLessons, homeworkTasks: filteredHomework, exams: filteredExams)
            weekPlan = result.plan
            isGenerating = false
            aiPlanUsed = false
        }
    }

    private func exportPlan() {
        guard let plan = weekPlan else { return }
        let icsString = exporter.export(events: plan.events)
        let url = saveICS(content: icsString)
        shareURL = url
        showShare = url != nil
    }

    private func saveICS(content: String) -> URL? {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("weekplanner.ics")
        do {
            try content.data(using: .utf8)?.write(to: tempURL)
            return tempURL
        } catch {
            warning = "Kon .ics niet opslaan"
            return nil
        }
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private var settingsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Gebruik AI planner", isOn: $useAIPlanner)
            if useAIPlanner {
                TextField("AI endpoint", text: $aiEndpoint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.URL)
                if let usedAI = aiPlanUsed {
                    Text(usedAI ? "Laatst: AI" : "Laatst: lokale planner")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }

    // Kleine debug-info om te zien wat er beschikbaar is bij het plannen
    private var debugInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Lessen: \(filteredLessons.count)  |  Huiswerk: \(filteredHomework.count)  |  Toetsen: \(filteredExams.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if filteredHomework.isEmpty && filteredExams.isEmpty {
                Text("Geen huiswerk/toetsen aanwezig om in te plannen.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal)
    }

    private func icon(for event: PlanEvent) -> some View {
        let symbol: String
        let color: Color
        switch event.kind {
        case .homework:
            symbol = "doc.text"
            color = .blue
        case .homeworkDue:
            symbol = "tray.and.arrow.up.fill"
            color = .green
        case .study:
            symbol = "brain.head.profile"
            color = .orange
        case .exam:
            symbol = "checkmark.seal.fill"
            color = .green
        case .lesson:
            symbol = "book"
            color = .gray
        case .breakTime:
            symbol = "cup.and.saucer.fill"
            color = .mint
        }
        return Image(systemName: symbol)
            .foregroundStyle(color)
            .font(.title3)
    }

    private func background(for event: PlanEvent) -> Color {
        switch event.kind {
        case .exam:
            Color.green.opacity(0.15)
        case .homework:
            Color.blue.opacity(0.12)
        case .homeworkDue:
            Color.green.opacity(0.18)
        case .study:
            Color.orange.opacity(0.12)
        case .breakTime:
            Color.mint.opacity(0.12)
        default:
            Color.secondary.opacity(0.08)
        }
    }

    // Helpers voor weergave
    private func upcomingDays() -> [Date] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        return (0..<30).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: start)
        }
    }

    private func dateLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateFormat = "EEE dd MMM"
        return formatter.string(from: date)
    }

    @ViewBuilder
    private func profileChip(_ profile: ChildProfile) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay(Text(initials(for: profile.name)).font(.headline))
            Text(profile.name.isEmpty ? "Naamloos" : profile.name)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        if let first = parts.first?.first {
            if let last = parts.dropFirst().first?.first {
                return "\(first)\(last)"
            }
            return "\(first)"
        }
        return "?"
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack { PlannerView() }
        .modelContainer(for: [ChildProfile.self, Lesson.self, HomeworkTask.self, ExamPreparation.self], inMemory: true)
}
