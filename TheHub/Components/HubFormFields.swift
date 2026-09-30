import SwiftUI

/// Styled text field matching the app's dark theme.
struct HubTextField: View {
    let label: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .never
    var maxLength: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.hubTextSecondary)

            TextField("", text: $text)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.hubSurface)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.hubBorder, lineWidth: 1)
                )
                .onChange(of: text) {
                    if let maxLength, text.count > maxLength {
                        text = String(text.prefix(maxLength))
                    }
                }
        }
    }
}

/// Styled password field with show/hide toggle.
struct HubSecureField: View {
    let label: String
    @Binding var text: String
    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.hubTextSecondary)

            HStack {
                Group {
                    if isVisible {
                        TextField("", text: $text)
                    } else {
                        SecureField("", text: $text)
                    }
                }
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button {
                    isVisible.toggle()
                } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .foregroundStyle(Color.hubTextSecondary)
                }
                .accessibilityLabel(isVisible ? "Hide password" : "Show password")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.hubSurface)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.hubBorder, lineWidth: 1)
            )
        }
    }
}

/// Multi-line text field (notes, reasons) in the same chrome as HubTextField.
struct HubMultilineField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var lineRange: ClosedRange<Int> = 3...6
    var maxLength: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.hubTextSecondary)

            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(lineRange)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.hubSurface)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.hubBorder, lineWidth: 1)
                )
                .onChange(of: text) {
                    if let maxLength, text.count > maxLength {
                        text = String(text.prefix(maxLength))
                    }
                }
        }
    }
}

/// Caption label + segmented control for a small, closed set of options.
/// `selection` is optional so a form can start with nothing chosen.
struct HubSegmentedField<Option: Hashable>: View {
    let label: String
    @Binding var selection: Option?
    let options: [Option]
    let title: (Option) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.hubTextSecondary)

            Picker(label, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(title(option)).tag(Optional(option))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

/// Caption label + menu picker, for longer option lists.
struct HubMenuField<Option: Hashable>: View {
    let label: String
    @Binding var selection: Option?
    let options: [Option]
    let placeholder: String
    let title: (Option) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.hubTextSecondary)

            Menu {
                ForEach(options, id: \.self) { option in
                    Button(title(option)) { selection = option }
                }
            } label: {
                HStack {
                    Text(selection.map(title) ?? placeholder)
                        .foregroundStyle(selection == nil ? Color.hubTextSecondary : .white)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(Color.hubTextSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.hubSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.hubBorder, lineWidth: 1)
                )
            }
        }
    }
}

/// Full-width primary action button in Hub gold.
struct HubPrimaryButton: View {
    let label: String
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void

    init(
        _ label: String,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(label)
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .background(Color.hubPrimary.opacity(isDisabled ? 0.5 : 1))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .disabled(isLoading || isDisabled)
    }
}

/// Inline error message display.
struct HubErrorText: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(Color.hubError)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
