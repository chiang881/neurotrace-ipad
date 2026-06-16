import SwiftData
import SwiftUI

private struct SubjectEditorDestination: Identifiable {
    let id = UUID()
    let subject: Subject?
}

struct SubjectsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Subject.updatedAt, order: .reverse) private var subjects: [Subject]
    @State private var editor: SubjectEditorDestination?
    @State private var subjectPendingDeletion: Subject?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppleGlassBackdrop().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        ScreenTitle(title: "受试者管理", subtitle: "只保存研究所需的最小信息")
                        Spacer()
                        Button {
                            editor = SubjectEditorDestination(subject: nil)
                        } label: {
                            Label("新增受试者", systemImage: "plus")
                                .font(.headline)
                                .frame(width: 170, height: 48)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.blue)
                    }

                    if subjects.isEmpty {
                        EmptyStateView(
                            symbol: "person.crop.circle.badge.plus",
                            title: "尚无受试者",
                            message: "新建研究编号后才能开始测试。"
                        )
                    } else {
                        ForEach(subjects) { subject in
                            NavigationLink {
                                SubjectDetailView(subject: subject)
                            } label: {
                                subjectRow(subject)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("编辑", systemImage: "pencil") {
                                    editor = SubjectEditorDestination(subject: subject)
                                }
                                Button("删除", systemImage: "trash", role: .destructive) {
                                    subjectPendingDeletion = subject
                                }
                            }
                        }
                    }
                }
                .appScreenPadding()
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("受试者")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editor) { destination in
            SubjectEditorView(subject: destination.subject)
        }
        .alert("删除受试者及其全部测试？", isPresented: Binding(
            get: { subjectPendingDeletion != nil },
            set: { if !$0 { subjectPendingDeletion = nil } }
        )) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                guard let subject = subjectPendingDeletion else { return }
                Task { await delete(subject) }
            }
        } message: {
            Text("此操作会同时删除本地原始数据，无法撤销。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func subjectRow(_ subject: Subject) -> some View {
        HStack(spacing: 18) {
            GlassIcon(symbol: "person.crop.circle", tint: .cyan)
            VStack(alignment: .leading, spacing: 6) {
                Text(subject.code)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text([
                    subject.age.map { "\($0) 岁" },
                    subject.dominantHand == .unspecified ? nil : subject.dominantHand.rawValue,
                    subject.researchGroup.rawValue
                ].compactMap { $0 }.joined(separator: " · "))
                .foregroundStyle(.white.opacity(0.62))
            }
            Spacer()
            Text("\(subject.sessions.count) 次测试")
                .foregroundStyle(.white.opacity(0.60))
            Image(systemName: "chevron.right")
                .foregroundStyle(.white.opacity(0.42))
        }
        .padding(20)
        .parchmentGlass(cornerRadius: 24, tint: .white.opacity(0.05), interactive: true)
    }

    private func delete(_ subject: Subject) async {
        do {
            for session in subject.sessions {
                try await services.captureStore.removeSession(session.id)
            }
            modelContext.delete(subject)
            try modelContext.save()
            subjectPendingDeletion = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SubjectEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let subject: Subject?

    @State private var code: String
    @State private var ageText: String
    @State private var sex: SubjectSex
    @State private var dominantHand: DominantHand
    @State private var researchGroup: ResearchGroup
    @State private var notes: String
    @State private var validationMessage: String?

    init(subject: Subject?) {
        self.subject = subject
        _code = State(initialValue: subject?.code ?? "")
        _ageText = State(initialValue: subject?.age.map(String.init) ?? "")
        _sex = State(initialValue: subject?.sex ?? .unspecified)
        _dominantHand = State(initialValue: subject?.dominantHand ?? .unspecified)
        _researchGroup = State(initialValue: subject?.researchGroup ?? .unknown)
        _notes = State(initialValue: subject?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("研究编号") {
                    TextField("例如 S001", text: $code)
                        .textInputAutocapitalization(.characters)
                    TextField("年龄（可选）", text: $ageText)
                        .keyboardType(.numberPad)
                }

                Section("分组信息") {
                    Picker("性别", selection: $sex) {
                        ForEach(SubjectSex.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("惯用手", selection: $dominantHand) {
                        ForEach(DominantHand.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("分组", selection: $researchGroup) {
                        ForEach(ResearchGroup.allCases) { Text($0.rawValue).tag($0) }
                    }
                }

                Section("备注") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(subject == nil ? "新增受试者" : "编辑受试者")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedCode.isEmpty else {
            validationMessage = "受试者编号不能为空。"
            return
        }
        let age = Int(ageText)
        if !ageText.isEmpty, age == nil || !(1...120).contains(age!) {
            validationMessage = "年龄应为 1–120 的整数。"
            return
        }

        do {
            let existing = try modelContext.fetch(FetchDescriptor<Subject>())
            if existing.contains(where: { $0.code.caseInsensitiveCompare(normalizedCode) == .orderedSame && $0.id != subject?.id }) {
                validationMessage = "受试者编号已存在。"
                return
            }

            let target = subject ?? Subject(code: normalizedCode)
            if subject == nil { modelContext.insert(target) }
            target.code = normalizedCode
            target.age = age
            target.sex = sex
            target.dominantHand = dominantHand
            target.researchGroup = researchGroup
            target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            target.updatedAt = .now
            try modelContext.save()
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

struct SubjectDetailView: View {
    let subject: Subject
    @State private var showEditor = false

    var body: some View {
        ZStack {
            AppleGlassBackdrop().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        ScreenTitle(title: subject.code, subtitle: subject.researchGroup.rawValue)
                        Spacer()
                        Button("编辑", systemImage: "pencil") { showEditor = true }
                            .buttonStyle(.glass)
                    }
                    GlassCard {
                        LabeledContent("年龄", value: subject.age.map { "\($0) 岁" } ?? "未填写")
                        LabeledContent("性别", value: subject.sex.rawValue)
                        LabeledContent("惯用手", value: subject.dominantHand.rawValue)
                        LabeledContent("备注", value: subject.notes.isEmpty ? "无" : subject.notes)
                    }
                    .foregroundStyle(.white)

                    SectionTitle("历史测试")
                    if subject.sessions.isEmpty {
                        EmptyStateView(symbol: "doc.text", title: "暂无测试", message: "可从“采集”标签开始新测试。")
                    } else {
                        ForEach(subject.sessions.sorted { $0.createdAt > $1.createdAt }) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                SessionRow(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .appScreenPadding()
            }
        }
        .navigationTitle(subject.code)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditor) {
            SubjectEditorView(subject: subject)
        }
    }
}
