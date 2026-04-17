import SwiftUI

struct AppSelectionView: View {
    @ObservedObject private var appList = AppListManager.shared
    @State private var showAddSheet = false
    @State private var newBundleId = ""
    @State private var newDisplayName = ""
    @State private var addError = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appList.monitoredApps.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(appList.monitoredApps) { app in
                            AppRow(app: app)
                        }
                    }
                }
            }

            Divider().background(Theme.border)

            Button("Add app") {
                showAddSheet = true
            }
            .buttonStyle(ThemedButtonStyle(filled: true))
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        .background(Theme.background)
        .sheet(isPresented: $showAddSheet) {
            addSheet
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No apps configured")
                .font(.system(size: 15, design: .monospaced))
                .foregroundColor(Theme.text)
                .padding(.top, 32)
                .padding(.horizontal, 16)
            Text("Add apps to monitor their notifications.")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Theme.dimText)
                .padding(.horizontal, 16)
            Spacer()
        }
    }

    private var addSheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 0) {
                fieldLabel("DISPLAY NAME")
                TextField("e.g. WhatsApp", text: $newDisplayName)
                    .textFieldStyle(AppTextFieldStyle())

                fieldLabel("BUNDLE IDENTIFIER")
                TextField("e.g. net.whatsapp.WhatsApp", text: $newBundleId)
                    .textFieldStyle(AppTextFieldStyle())
                    .autocapitalization(.none)
                    .keyboardType(.asciiCapable)

                if !addError.isEmpty {
                    Text(addError)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                Text("Tip: Find bundle IDs at AppID.net or similar lookup tools.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.dimText)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                Spacer()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Add App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        resetForm()
                        showAddSheet = false
                    }
                    .foregroundColor(Theme.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        commitAdd()
                    }
                    .foregroundColor(Theme.accent)
                    .disabled(newBundleId.trimmingCharacters(in: .whitespaces).isEmpty || newDisplayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func commitAdd() {
        let bid = newBundleId.trimmingCharacters(in: .whitespaces)
        let name = newDisplayName.trimmingCharacters(in: .whitespaces)
        guard !bid.isEmpty, !name.isEmpty else { addError = "Both fields are required."; return }
        guard !bid.contains(" ") else { addError = "Bundle ID cannot contain spaces."; return }
        appList.add(bundleId: bid, displayName: name)
        resetForm()
        showAddSheet = false
    }

    private func resetForm() {
        newBundleId = ""
        newDisplayName = ""
        addError = ""
    }

    @ViewBuilder
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(Theme.accent)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 4)
    }
}

struct AppRow: View {
    @State var app: MonitoredApp
    private let appList = AppListManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(app.displayName)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.text)
                Spacer()
                Button(role: .destructive) {
                    appList.remove(id: app.id)
                } label: {
                    Text("Remove")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Text(app.bundleIdentifier)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.dimText)
                .padding(.horizontal, 16)
                .padding(.top, 2)

            HStack(spacing: 0) {
                toggleCell(label: "Forward to band", isOn: $app.forwardToBand) {
                    appList.update(app)
                }
                Divider().frame(height: 44).background(Theme.border)
                toggleCell(label: "Shortcut trigger", isOn: $app.useAsShortcutTrigger) {
                    appList.update(app)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider().background(Theme.border)
        }
    }

    @ViewBuilder
    private func toggleCell(label: String, isOn: Binding<Bool>, onChange: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.dimText)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Theme.accent)
                .onChange(of: isOn.wrappedValue) { _ in onChange() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct AppTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 14, design: .monospaced))
            .foregroundColor(Theme.text)
            .padding(12)
            .background(Theme.surface)
            .overlay(Rectangle().stroke(Theme.border, lineWidth: 1))
            .padding(.horizontal, 16)
    }
}
