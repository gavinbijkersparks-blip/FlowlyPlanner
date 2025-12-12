import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [ChildProfile]
    @State private var name: String = ""
    @State private var selectedDays: Set<Weekday> = Set(Weekday.schoolDays)
    @State private var bedtime: Date = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var maxMinutes: Int = 90

    var body: some View {
        Form {
            Section(header: Text("Kindprofiel")) {
                TextField("Naam", text: $name)
                VStack(alignment: .leading) {
                    Text("Schooldagen")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
                        ForEach(Weekday.allCases) { day in
                            Button {
                                toggle(day)
                            } label: {
                                Text(day.label)
                                    .frame(maxWidth: .infinity)
                                    .padding(8)
                                    .background(selectedDays.contains(day) ? Color.accentColor.opacity(0.2) : Color.clear)
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
                DatePicker("Bedtijd", selection: $bedtime, displayedComponents: .hourAndMinute)
                Stepper("Max studietijd per dag: \(maxMinutes) min", value: $maxMinutes, in: 30...240, step: 15)
            }
            Button("Bewaar", action: saveProfile)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Kindprofiel")
        .onAppear(perform: loadProfile)
    }

    private func toggle(_ day: Weekday) {
        if selectedDays.contains(day) {
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
    }

    private func loadProfile() {
        guard let profile = profiles.first else { return }
        name = profile.name
        selectedDays = Set(profile.schoolDays)
        bedtime = profile.bedtime
        maxMinutes = profile.maxStudyMinutesPerDay
    }

    private func saveProfile() {
        let days = Array(selectedDays).sorted { $0.rawValue < $1.rawValue }
        if let profile = profiles.first {
            profile.name = name
            profile.schoolDays = days
            profile.bedtime = bedtime
            profile.maxStudyMinutesPerDay = maxMinutes
        } else {
            let newProfile = ChildProfile(name: name, schoolDays: days, bedtime: bedtime, maxStudyMinutesPerDay: maxMinutes)
            modelContext.insert(newProfile)
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
    .modelContainer(for: ChildProfile.self, inMemory: true)
}
