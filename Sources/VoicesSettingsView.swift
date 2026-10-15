import SwiftUI

struct VoicesSettingsView: View {
    @ObservedObject private var store = VoiceProfileStore.shared
    @State private var selection = Set<UUID>()
    @State private var name = ""
    @State private var deleteConfirmation = false
    @State private var deleteAllConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voices").font(.title2)
            if store.profiles.isEmpty {
                Text("Rename a speaker in a meeting to save their voice for future meetings.")
                    .foregroundStyle(.secondary)
            }
            List(selection: $selection) {
                ForEach(store.profiles) { profile in
                    HStack {
                        Text(profile.name)
                        Spacer()
                        Text("\(profile.samples.count) samples").foregroundStyle(.secondary)
                        Text(profile.updatedAt, style: .date).foregroundStyle(.secondary)
                    }.tag(profile.id)
                }
            }
            HStack {
                TextField("Profile name", text: $name)
                Button("Rename") {
                    perform { if let id = selection.first { try store.rename(id, to: name) } }
                }.disabled(selection.count != 1 || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Menu("Merge into") {
                    ForEach(store.profiles.filter { selection.contains($0.id) }) { target in
                        Button(target.name) {
                            perform {
                                for id in selection where id != target.id { try store.merge(id, into: target.id) }
                                selection = [target.id]
                            }
                        }
                    }
                }.disabled(selection.count != 2)
                Button("Delete", role: .destructive) { deleteConfirmation = true }.disabled(selection.isEmpty)
            }
            Button("Delete all voices", role: .destructive) { deleteAllConfirmation = true }
                .disabled(store.profiles.isEmpty)
            Text("Voice data is biometric data stored only on this Mac. Deleting voices removes samples and linked voice embeddings from meetings. Meeting text keeps its names.")
                .font(.caption).foregroundStyle(.secondary)
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .padding()
        .tabItem { Label("Voices", systemImage: "person.wave.2") }
        .confirmationDialog("Delete selected voices?", isPresented: $deleteConfirmation) {
            Button("Delete", role: .destructive) {
                perform { for id in selection { try store.delete(id) }; selection = [] }
            }
        }
        .confirmationDialog("Delete all saved voices?", isPresented: $deleteAllConfirmation) {
            Button("Delete all voices", role: .destructive) { perform { try store.deleteAll(); selection = [] } }
        }
        .onChange(of: selection) { _, ids in
            name = ids.count == 1 ? store.profiles.first { ids.contains($0.id) }?.name ?? "" : ""
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}
