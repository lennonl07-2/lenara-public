import SwiftUI

struct WidgetsGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Recordatorios desde la pantalla bloqueada")
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                        .foregroundStyle(LenaraColors.textPrimary)
                    instruction("1", "Mantén pulsada la pantalla bloqueada y toca Personalizar → Pantalla bloqueada.")
                    instruction("2", "Quita uno de los controles inferiores, toca + y busca Lenara.")
                    instruction("3", "Elige Dictar recordatorio. También puedes añadirlo al Centro de control.")
                    Text("Mantén pulsado el control de Lenara. iOS desbloquea el iPhone y abre solo la pantalla de dictado, que permanece encendida. Di qué recordar y cuándo y toca Enviar. Guarda el recordatorio y cierra el dictado sin abrir el chat ni mostrar una conversación de confirmación. Cancelar descarta el dictado.")
                        .font(.footnote).foregroundStyle(LenaraColors.textSecondary)
                    Divider()
                    Text("Ten a Lenara en tu pantalla de inicio")
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                        .foregroundStyle(LenaraColors.textPrimary)
                    instruction("1", "Mantén pulsado un espacio vacío de la pantalla de inicio del iPhone.")
                    instruction("2", "Toca Editar y luego Añadir widget (+).")
                    instruction("3", "Busca Lenara y elige Micrófono de Lenara o Tareas de Lenara.")
                    instruction("4", "Pulsa Añadir widget y colócalo donde quieras.")
                    Text("El widget de inicio del micrófono abre la pantalla de dictado de Lenara.")
                        .font(.footnote).foregroundStyle(LenaraColors.textSecondary)
                    Spacer()
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LenaraColors.background.ignoresSafeArea())
            }
            .navigationTitle("Widgets de Lenara")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func instruction(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.headline).foregroundStyle(LenaraColors.onAccent)
                .frame(width: 28, height: 28).background(LenaraColors.accent, in: Circle())
            Text(text).font(.body).foregroundStyle(LenaraColors.textPrimary)
        }
    }
}
