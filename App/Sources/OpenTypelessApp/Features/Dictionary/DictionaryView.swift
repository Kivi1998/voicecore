import OpenTypelessDomain
import SwiftUI

/// 词典视图模型（DICT-001/002）。
@MainActor
final class DictionaryViewModel: ObservableObject {
    @Published var searchText = ""
    @Published private(set) var terms: [DictionaryTerm] = []
    @Published var newTerm = ""
    @Published var inputMessage: String?
    @Published var isAddSheetPresented = false
    @Published var termPendingDeletion: DictionaryTerm?

    private let repository: any DictionaryRepository

    init(repository: any DictionaryRepository) {
        self.repository = repository
    }

    func reload() async {
        do {
            terms = try await repository.list(
                searchText: searchText.isEmpty ? nil : searchText
            )
        } catch {
            inputMessage = "词典读取失败。"
        }
    }

    /// 添加（仅单条；空白、重复、超长有原位提示）。
    func addTerm() async {
        let trimmed = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            inputMessage = "请输入词语。"
            return
        }
        guard trimmed.count <= 64 else {
            inputMessage = "词语过长（最多 64 个字符）。"
            return
        }
        do {
            _ = try await repository.add(term: trimmed)
            newTerm = ""
            inputMessage = nil
            isAddSheetPresented = false
            await reload()
        } catch let error as DictationError {
            inputMessage = error.userMessage
        } catch {
            inputMessage = "词语已存在。"
        }
    }

    func delete(_ term: DictionaryTerm) async {
        do {
            try await repository.delete(id: term.id)
            termPendingDeletion = nil
            await reload()
        } catch {
            inputMessage = "删除失败，请重试。"
        }
    }
}

/// 词典页面（DICT-002）：列表、搜索、添加弹窗、删除确认。
struct DictionaryView: View {
    @StateObject private var viewModel: DictionaryViewModel
    @FocusState private var addFieldFocused: Bool

    init(composition: AppComposition) {
        _viewModel = StateObject(wrappedValue: DictionaryViewModel(
            repository: composition.dictionary
        ))
    }

    var body: some View {
        List(viewModel.terms) { term in
            HStack {
                Text(term.term)
                Spacer()
                Text(term.createdAt, format: .dateTime.year().month().day())
                    .font(DesignTokens.Font.caption)
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    viewModel.termPendingDeletion = term
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("删除词语 \(term.term)")
            }
        }
        .navigationTitle(L10n.Page.dictionary)
        .searchable(text: $viewModel.searchText, prompt: "搜索词语")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.isAddSheetPresented = true
                } label: {
                    Label("添加词语", systemImage: "plus")
                }
                .accessibilityLabel("添加词语")
            }
        }
        .overlay {
            if viewModel.terms.isEmpty {
                EmptyStateView(
                    symbol: "character.book.closed",
                    title: "词典为空",
                    message: "添加专有名词，语音识别与改写会优先按词典纠正。"
                )
            }
        }
        .task(id: viewModel.searchText) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await viewModel.reload()
        }
        .sheet(isPresented: $viewModel.isAddSheetPresented) {
            addSheet
        }
        .alert("删除词语？", isPresented: deletionBinding, presenting: viewModel.termPendingDeletion) { term in
            Button(L10n.Common.delete, role: .destructive) {
                Task { await viewModel.delete(term) }
            }
            Button(L10n.Common.cancel, role: .cancel) {
                viewModel.termPendingDeletion = nil
            }
        } message: { term in
            Text("将从词典中删除「\(term.term)」。")
        }
    }

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text("添加词语")
                .font(DesignTokens.Font.headline)
            TextField("例如：通义千问", text: $viewModel.newTerm)
                .textFieldStyle(.roundedBorder)
                .focused($addFieldFocused)
                .onSubmit {
                    Task { await viewModel.addTerm() }
                }
            if let message = viewModel.inputMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(DesignTokens.Font.callout)
                    .foregroundStyle(DesignTokens.Color.failure)
            }
            HStack {
                Spacer()
                Button(L10n.Common.cancel, role: .cancel) {
                    viewModel.isAddSheetPresented = false
                    viewModel.inputMessage = nil
                }
                Button(L10n.Common.add) {
                    Task { await viewModel.addTerm() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignTokens.Spacing.xxl)
        .frame(width: 360)
        .onAppear { addFieldFocused = true }
    }

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { viewModel.termPendingDeletion != nil },
            set: {
                if !$0 {
                    viewModel.termPendingDeletion = nil
                }
            }
        )
    }
}
