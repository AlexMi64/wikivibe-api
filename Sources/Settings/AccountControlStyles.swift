import SwiftUI

/// Account-window-only colors. No environment defaults leak into the widget.
enum AccountControlPalette {
    static let accent = Color(red: 0.15, green: 0.39, blue: 0.98)
    static func panel(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.045, green: 0.065, blue: 0.10) : Color(nsColor: .controlBackgroundColor)
    }
    static func surface(_ scheme: ColorScheme) -> Color {
        (scheme == .dark ? Color.white : Color.black).opacity(0.055)
    }
}

struct AetherCheckboxStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(configuration.isOn ? AccountControlPalette.accent : AccountControlPalette.surface(colorScheme))
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 17, height: 17)
                configuration.label.foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(configuration.isOn ? AccountControlPalette.accent.opacity(0.12) : AccountControlPalette.surface(colorScheme),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(configuration.isOn ? AccountControlPalette.accent.opacity(0.40) : Color.primary.opacity(0.10), lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
    }
}

/// A real styled list, not an NSMenu with a custom label. Native Buttons retain
/// keyboard activation and accessibility while both surfaces share the palette.
struct AetherSelectionMenu<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    let enabled: (Value) -> Bool
    let label: String
    let identifier: String?
    let accent: Color
    @State private var expanded = false
    @State private var triggerWidth: CGFloat = 260
    @FocusState private var triggerFocused: Bool
    @FocusState private var focusedOption: Int?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    init(_ label: String, selection: Binding<Value>, options: [Value], accent: Color = AccountControlPalette.accent,
         identifier: String? = nil, title: @escaping (Value) -> String,
         enabled: @escaping (Value) -> Bool = { _ in true }) {
        self.label = label
        self._selection = selection
        self.options = options
        self.accent = accent
        self.identifier = identifier
        self.title = title
        self.enabled = enabled
    }

    var body: some View {
        Button { expanded.toggle() } label: {
            HStack(spacing: 8) {
                Text(title(selection)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold)).foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
            .aetherControlSurface(accent: accent)
            .overlay {
                if triggerFocused {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(accent, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .focused($triggerFocused)
        .focusEffectDisabled()
        .opacity(isEnabled ? 1 : 0.4)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { triggerWidth = $0 }
        .accessibilityLabel(label)
        .accessibilityValue(title(selection))
        .accessibilityIdentifier(identifier ?? label)
        .onKeyPress(.downArrow) {
            guard isEnabled else { return .ignored }
            expanded = true
            return .handled
        }
        .popover(isPresented: $expanded, arrowEdge: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(options.indices, id: \.self) { index in
                            let option = options[index]
                            Button {
                                selection = option
                                expanded = false
                            } label: {
                                HStack(spacing: 10) {
                                    Text(title(option)).frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "checkmark").opacity(selection == option ? 1 : 0)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .contentShape(RoundedRectangle(cornerRadius: 6))
                                .background(selection == option || focusedOption == index ? accent.opacity(0.18) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .disabled(!enabled(option))
                            .opacity(enabled(option) ? 1 : 0.4)
                            .focused($focusedOption, equals: index)
                            .focusEffectDisabled()
                            .accessibilityAddTraits(selection == option ? .isSelected : [])
                            .accessibilityIdentifier((identifier ?? label) + ".option.\(index)")
                            .id(index)
                        }
                    }
                    .padding(6)
                }
                .frame(width: min(380, max(240, triggerWidth)), height: min(300, CGFloat(options.count) * 35 + 12))
                .onAppear {
                    let index = options.firstIndex(of: selection) ?? 0
                    focusedOption = options.indices.contains(index) && enabled(options[index]) ? index : options.firstIndex(where: enabled)
                    proxy.scrollTo(focusedOption ?? 0, anchor: .center)
                }
                .onChange(of: focusedOption) { _, option in
                    if let option { proxy.scrollTo(option, anchor: .center) }
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(.primary)
            .background(AccountControlPalette.panel(colorScheme))
            .presentationBackground(AccountControlPalette.panel(colorScheme))
            .onKeyPress(.escape) { expanded = false; return .handled }
            .onKeyPress(.upArrow) { moveFocus(-1); return .handled }
            .onKeyPress(.downArrow) { moveFocus(1); return .handled }
        }
        .onChange(of: expanded) { _, value in if !value { triggerFocused = true } }
    }

    private func moveFocus(_ step: Int) {
        let current = focusedOption ?? -1
        var index = current + step
        while options.indices.contains(index) {
            if enabled(options[index]) { focusedOption = index; return }
            index += step
        }
    }
}

extension View {
    func aetherControlSurface(accent: Color = AccountControlPalette.accent) -> some View {
        modifier(AccountControlSurface(accent: accent))
    }
}

private struct AccountControlSurface: ViewModifier {
    let accent: Color
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        content.padding(.horizontal, 11).padding(.vertical, 8)
            .background(AccountControlPalette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(accent.opacity(0.24), lineWidth: 1)
            }
    }
}
