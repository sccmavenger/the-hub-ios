import SwiftUI

/// Chips with remove buttons plus an add field, enforcing the board limits
/// (10 tags × 30 characters) client-side; the server check is authoritative.
struct TagEditor: View {
    @Binding var tags: [String]
    var isEditable = true
    var onCommit: (([String]) -> Void)? = nil

    @State private var draft = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if tags.isEmpty && !isEditable {
                Text("No tags")
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                            if isEditable {
                                Button {
                                    commit(tags.filter { $0 != tag })
                                } label: {
                                    Image(systemName: "xmark").font(.caption2.bold())
                                }
                                .accessibilityLabel("Remove tag \(tag)")
                            }
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.hubSurfaceElevated)
                        .clipShape(Capsule())
                    }
                }
            }

            if isEditable {
                HStack(spacing: 8) {
                    TextField("Add a tag", text: $draft)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .onSubmit(add)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.hubSurfaceElevated)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .disabled(tags.count >= BoardEntry.maxTags)
                    Button("Add", action: add)
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.hubPrimary)
                        .disabled(draft.isBlank || tags.count >= BoardEntry.maxTags)
                }
                HStack {
                    Text("\(tags.count)/\(BoardEntry.maxTags) tags · up to \(BoardEntry.maxTagLength) characters each")
                        .font(.caption2)
                        .foregroundStyle(Color.hubTextSecondary)
                    Spacer()
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundStyle(Color.hubError)
                    }
                }
            }
        }
    }

    private func add() {
        let value = draft.trimmed
        guard !value.isEmpty else { return }
        commit(tags + [value])
    }

    private func commit(_ proposed: [String]) {
        do {
            let cleaned = try BoardTags.clean(proposed)
            errorMessage = nil
            draft = ""
            tags = cleaned
            onCommit?(cleaned)
        } catch BoardTags.ValidationError.tooLong {
            errorMessage = "Tags must be \(BoardEntry.maxTagLength) characters or fewer."
        } catch {
            errorMessage = "A prospect can have at most \(BoardEntry.maxTags) tags."
        }
    }
}

/// Horizontal stage filter with counts: All · Watching · Evaluating · …
struct StageChipBar: View {
    @Binding var selection: PipelineStage?
    let counts: [String: Int]

    private var total: Int { counts.values.reduce(0, +) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", count: total, tint: Color.hubPrimary, isOn: selection == nil) { selection = nil }
                ForEach(PipelineStage.allCases, id: \.self) { stage in
                    chip(stage.displayName, count: counts[stage.rawValue] ?? 0, tint: stage.color, isOn: selection == stage) {
                        selection = stage
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func chip(_ label: String, count: Int, tint: Color, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                Text("\(count)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isOn ? Color.white.opacity(0.25) : tint.opacity(0.2))
                    .clipShape(Capsule())
            }
            .font(.caption.bold())
            .foregroundStyle(isOn ? .white : tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isOn ? tint : Color.hubSurface)
            .clipShape(Capsule())
        }
        .accessibilityLabel("\(label), \(count)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
