import SwiftUI

struct UpdateSettingsRow: View {
    private let controller = UpdateController.shared
    @Environment(\.tone) private var tone
    @State private var confirmMigration = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRow(label: UpdateController.text("title"), subtitle: UpdateController.text(controller.statusKey)) {
                if controller.needsMigration {
                    Button(UpdateController.text("migration")) { confirmMigration = true }
                        .disabled(controller.isFrozen)
                } else if controller.canRecover {
                    Button(UpdateController.text("recovery")) { controller.showRecovery() }
                } else if controller.canInstall {
                    Button(UpdateController.text("install")) { controller.install() }
                } else if controller.canApplyRuntime {
                    HStack(spacing: 8) {
                        Button(UpdateController.text("apply")) { controller.applyRuntime() }
                        Button(UpdateController.text("check")) { controller.check() }.disabled(!controller.canCheck)
                    }
                } else {
                    Button(UpdateController.text("check")) { controller.check() }
                        .disabled(!controller.canCheck)
                }
            }
            if let version = controller.offeredVersion {
                Text(verbatim: version).font(Face.secondary).foregroundStyle(tone.text2)
                    .padding(.horizontal, Grid.L)
            }
            if let progress = controller.progress {
                ProgressView(value: progress).padding(.horizontal, Grid.L)
            }
            if controller.canCancel || controller.canRequestOff {
                HStack(spacing: 8) {
                    if controller.canCancel {
                        Button(UpdateController.text("cancel")) { controller.cancelPending() }
                    }
                    if controller.canRequestOff {
                        Button(UpdateController.text("off")) { controller.requestOff() }
                    }
                }
                .padding(.horizontal, Grid.L)
                .padding(.bottom, 8)
            }
        }
        .confirmationDialog(UpdateController.text("migration_detail"), isPresented: $confirmMigration, titleVisibility: .visible) {
            Button(UpdateController.text("migration_confirm")) { controller.migrateClientsClosed() }
        }
    }
}
