import Foundation
import SwiftData
import Combine

@MainActor
final class ProfileSelectionStore: ObservableObject {
    @Published var selectedProfileID: PersistentIdentifier?
}
