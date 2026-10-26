import SwiftUI
import SwiftData

// MARK: - Memory Tab
struct MemoryTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Memory.createdAt, order: .reverse) private var storedMemories: [Memory]
    @State private var searchText = ""
    @State private var showAddMemory = false

    private var memories: [Memory] { storedMemories }

    private var filteredMemories: [Memory] {
        if searchText.isEmpty {
            return memories
        }
        return memories.filter { memory in
            memory.title.localizedCaseInsensitiveContains(searchText) ||
            memory.content.localizedCaseInsensitiveContains(searchText) ||
            memory.tags.contains(where: { $0.lowercased().contains(searchText.lowercased()) })
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    Text("Memoria")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .tracking(-0.6)
                        .foregroundStyle(LenaraColors.textPrimary)
                    Spacer()
                    Button { showAddMemory = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(LenaraColors.logoMint)
                            .frame(width: 44, height: 44)
                            .background(LenaraColors.surface.opacity(0.88), in: Circle())
                    }
                    .accessibilityLabel("Añadir recuerdo")
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 14)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(LenaraColors.textTertiary)
                    TextField("Buscar recuerdos", text: $searchText)
                        .font(.body)
                        .tint(LenaraColors.logoMint)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(LenaraColors.textTertiary)
                        }
                        .accessibilityLabel("Borrar búsqueda")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(LenaraColors.surface.opacity(0.88), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(LenaraColors.divider.opacity(0.65), lineWidth: 1))
                .padding(.horizontal, 22)
                .padding(.bottom, 16)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        if filteredMemories.isEmpty {
                            emptyState
                        } else {
                            ForEach(filteredMemories) { memory in
                                memoryCard(memory)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                }
            }
            .background(LenaraBackground().ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAddMemory) {
                AddMemorySheet()
            }
        }
    }

    private func memoryCard(_ memory: Memory) -> some View {
        HStack(spacing: 10) {
            NavigationLink {
                MemoryDetailView(memory: memory)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(memory.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(LenaraColors.textPrimary)
                            .lineLimit(2)
                        if let category = memory.category {
                            Text(category.rawValue)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(LenaraColors.logoMint)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(LenaraColors.logoMint.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(memory.content)
                        .font(.subheadline)
                        .foregroundStyle(LenaraColors.textSecondary)
                        .lineLimit(2)
                    HStack {
                        if !memory.tags.isEmpty {
                            Text(memory.tags.prefix(3).map { "#\($0)" }.joined(separator: "  "))
                                .font(.caption2)
                                .foregroundStyle(LenaraColors.logoMint.opacity(0.9))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(memory.createdAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(LenaraColors.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LenaraColors.textTertiary)

            Button(role: .destructive) {
                deleteMemory(memory)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LenaraColors.error)
                    .frame(width: 34, height: 40)
            }
            .accessibilityLabel("Eliminar \(memory.title)")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 13)
        .background(LenaraColors.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(LenaraColors.divider.opacity(0.65), lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 50))
                .foregroundColor(LenaraColors.accent.opacity(0.5))

            Text("Sin recuerdos")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(LenaraColors.textPrimary)

            Text("Guarda tus primeras ideas y recuerdos desde el chat o tocando el botón +")
                .font(.body)
                .foregroundColor(LenaraColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(LenaraColors.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(LenaraColors.divider.opacity(0.65), lineWidth: 1))
    }

    private func deleteMemory(_ memory: Memory) {
        modelContext.delete(memory)
        try? modelContext.save()
    }
}

// MARK: - Add Memory Sheet
struct AddMemorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var title = ""
    @State private var content = ""
    @State private var category: MemoryCategory = .idea
    @State private var tags: String = ""
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                LenaraBackground().ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TÍTULO").font(.caption.weight(.medium)).foregroundStyle(LenaraColors.textTertiary)
                            TextField("¿Qué quieres recordar?", text: $title)
                                .foregroundStyle(LenaraColors.textPrimary)
                                .tint(LenaraColors.logoMint)
                            Rectangle().fill(LenaraColors.divider.opacity(0.7)).frame(height: 1)
                            Text("CONTENIDO").font(.caption.weight(.medium)).foregroundStyle(LenaraColors.textTertiary).padding(.top, 4)
                            TextEditor(text: $content)
                                .frame(minHeight: 150)
                                .foregroundStyle(LenaraColors.textPrimary)
                                .tint(LenaraColors.logoMint)
                                .scrollContentBackground(.hidden)
                        }
                        .padding(18)
                        .background(LenaraColors.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(LenaraColors.divider.opacity(0.65), lineWidth: 1))

                        VStack(spacing: 0) {
                            Picker("Categoría", selection: $category) {
                                ForEach(MemoryCategory.allCases, id: \.self) { item in
                                    Text(item.rawValue).tag(item)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(LenaraColors.accent)
                            Rectangle().fill(LenaraColors.divider.opacity(0.6)).frame(height: 1)
                            TextField("Etiquetas separadas por comas", text: $tags)
                                .autocorrectionDisabled()
                                .foregroundStyle(LenaraColors.textPrimary)
                                .tint(LenaraColors.logoMint)
                                .padding(.top, 14)
                        }
                        .padding(18)
                        .background(LenaraColors.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(LenaraColors.divider.opacity(0.65), lineWidth: 1))
                    }
                    .padding(22)
                }
            }
            .navigationTitle("Nueva memoria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(LenaraColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        saveMemory()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .alert("No se pudo guardar", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("Aceptar", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
    }

    private func saveMemory() {
        let memory = Memory(
            title: title.trimmingCharacters(in: .whitespaces),
            content: content.trimmingCharacters(in: .whitespaces),
            category: category,
            tags: tags.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        )
        modelContext.insert(memory)
        do { try modelContext.save(); dismiss() }
        catch { modelContext.rollback(); saveError = error.localizedDescription }
    }
}

// MARK: - Memory Detail View
struct MemoryDetailView: View {
    let memory: Memory
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var editTitle = ""
    @State private var editContent = ""
    @State private var editCategory: MemoryCategory?
    @State private var saveError: String?

    init(memory: Memory) {
        self.memory = memory
        _editTitle = State(initialValue: memory.title)
        _editContent = State(initialValue: memory.content)
        _editCategory = State(initialValue: memory.category)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LenaraBackground().ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("EDITAR")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(LenaraColors.textTertiary)
                                .padding(.bottom, 12)
                            TextField("Título", text: $editTitle)
                                .font(.body)
                                .foregroundStyle(LenaraColors.textPrimary)
                                .padding(.bottom, 12)
                            divider
                            TextEditor(text: $editContent)
                                .font(.body)
                                .foregroundStyle(LenaraColors.textPrimary)
                                .tint(LenaraColors.logoMint)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 170)
                                .padding(.top, 10)
                            divider
                            Picker("Categoría", selection: $editCategory) {
                                Text("Sin categoría").tag(nil as MemoryCategory?)
                                ForEach(MemoryCategory.allCases, id: \.self) { category in
                                    Text(category.rawValue).tag(category as MemoryCategory?)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(LenaraColors.accent)
                            .padding(.top, 8)
                        }
                        .padding(18)
                        .background(LenaraColors.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(LenaraColors.divider.opacity(0.65), lineWidth: 1))

                        VStack(alignment: .leading, spacing: 0) {
                            Text("DETALLES")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(LenaraColors.textTertiary)
                                .padding(.bottom, 10)
                            detailRow("Creado", value: memory.createdAt.formatted(date: .numeric, time: .shortened))
                            detailDivider
                            detailRow("Modificado", value: memory.updatedAt.formatted(date: .numeric, time: .shortened))
                            if !memory.tags.isEmpty {
                                detailDivider
                                detailRow("Etiquetas", value: memory.tags.joined(separator: ", "))
                            }
                            detailDivider
                            detailRow("Fuente", value: memory.source?.rawValue ?? "Manual")
                        }
                        .padding(18)
                        .background(LenaraColors.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(LenaraColors.divider.opacity(0.65), lineWidth: 1))

                        Button(role: .destructive) {
                            modelContext.delete(memory)
                            try? modelContext.save()
                            dismiss()
                        } label: {
                            Text("Eliminar recuerdo")
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(LenaraColors.error)
                        .background(LenaraColors.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(22)
                }
            }
            .navigationTitle("Recuerdo")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(LenaraColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .accessibilityLabel("Volver a Memoria")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save)
                        .disabled(editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("No se pudo guardar", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("Aceptar", role: .cancel) { saveError = nil }
            } message: { Text(saveError ?? "") }
        }
        .preferredColorScheme(.dark)
    }

    private var divider: some View {
        Rectangle().fill(LenaraColors.divider.opacity(0.7)).frame(height: 1)
    }

    private var detailDivider: some View {
        divider.padding(.vertical, 11)
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(title).foregroundStyle(LenaraColors.textPrimary)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(LenaraColors.textSecondary).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func save() {
        memory.title = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        memory.content = editContent.trimmingCharacters(in: .whitespacesAndNewlines)
        memory.category = editCategory
        memory.updatedAt = .now
        do { try modelContext.save(); dismiss() }
        catch { modelContext.rollback(); saveError = error.localizedDescription }
    }
}
