import SwiftUI

struct LocalMemoryDetailView: View {
    let entry: LocalMemoryEntry

    @State private var launchRequest: MemoryLaunchRequest?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(entry.title)
                    .font(.title2.weight(.bold))

                Button {
                    launchRequest = MemoryLaunchRequest(entries: [entry])
                } label: {
                    Label("Start New Chat", systemImage: "bubble.left.and.bubble.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                memoryInfo

                VStack(alignment: .leading, spacing: 8) {
                    Text("Revision History")
                        .font(.headline)

                    ForEach(entry.orderedRevisions.reversed()) { revision in
                        NavigationLink {
                            LocalMemoryRevisionDetailView(entry: entry, revision: revision)
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Revision \(revision.number)")
                                        .font(.body.weight(.semibold))
                                    Text(revision.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(revision.source)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                if let messageCount = revision.messageCount {
                                    Text("\(messageCount) msgs")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                            .padding(12)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $launchRequest) { request in
            MemoryLaunchSheet(entries: request.entries)
        }
    }

    private var memoryInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Revisions: \(entry.revisionCount)")
            Text("Created: \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
            Text("Updated: \(entry.updatedAt.formatted(date: .abbreviated, time: .shortened))")
            Text("Project: \(entry.projectName)")
            Text("Latest source: \(entry.source)")
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .textSelection(.enabled)
    }
}
