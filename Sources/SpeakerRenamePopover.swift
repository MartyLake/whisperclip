import SwiftUI

struct SpeakerRenamePopover: View {
    let currentName: String
    let save: (String) async throws -> String
    @ObservedObject private var store = VoiceProfileStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var message: String?
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Name speaker").font(.headline)
            TextField("Speaker name", text: $name).onSubmit { submit() }
            ForEach(store.profiles.filter { name.isEmpty || $0.name.localizedCaseInsensitiveContains(name) }.prefix(5)) { profile in
                Button(profile.name) { name = profile.name }.buttonStyle(.plain)
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") { submit() }
                    .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding().frame(width: 310)
        .onAppear { name = currentName }
    }

    private func submit() {
        guard !saving else { return }
        saving = true
        Task { @MainActor in
            do {
                message = try await save(name)
                try await Task.sleep(for: .seconds(2))
                dismiss()
            } catch {
                message = error.localizedDescription
            }
            saving = false
        }
    }
}
