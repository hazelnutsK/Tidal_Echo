import SwiftUI
import UniformTypeIdentifiers

/// 书架。她把 epub 放进来，点开就是阅读页；小克能看见的，只有她已经读过的部分。
struct BookshelfView: View {
    @ObservedObject var model: AppModel
    @State private var books: [Book] = []
    @State private var isLoading = true
    @State private var isImporting = false
    @State private var showingFilePicker = false
    @State private var openedBook: Book?
    @State private var pendingDeletion: Book?
    @State private var noticeText: String?
    @State private var errorText: String?

    private var palette: EchoPalette { model.theme.palette }

    var body: some View {
        ScrollView {
            if isLoading && books.isEmpty {
                ProgressView().padding(.top, 60)
            } else if books.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                    ForEach(books) { book in
                        Button { openedBook = book } label: {
                            BookCard(book: book, model: model, palette: palette)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { pendingDeletion = book } label: {
                                Label("从书架撤掉", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("书房")
                    .font(.custom("Songti SC", size: 17).weight(.semibold))
                    .foregroundStyle(palette.text)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if isImporting {
                    ProgressView()
                } else {
                    Button { showingFilePicker = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .tint(palette.accent)
        .task { await loadShelf() }
        .refreshable { await loadShelf() }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: BookshelfView.importableTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { Task { await importBook(at: url) } }
            case .failure(let error):
                errorText = error.localizedDescription
            }
        }
        .fullScreenCover(item: $openedBook) { book in
            BookReaderView(model: model, book: book)
        }
        .onChange(of: openedBook == nil) { closed in
            // 读完回来，进度和划线数要跟着变
            if closed { Task { await loadShelf() } }
        }
        .confirmationDialog(
            pendingDeletion.map { "把《\($0.title)》从书架上撤掉？" } ?? "",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("撤掉", role: .destructive) {
                guard let book = pendingDeletion else { return }
                pendingDeletion = nil
                Task { await delete(book) }
            }
            Button("算了", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("划线和批注也会一起没了。")
        }
        .overlay(alignment: .bottom) {
            if let noticeText {
                BookBanner(text: noticeText, tone: .neutral)
            } else if let errorText {
                BookBanner(text: errorText, tone: .error)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "books.vertical")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(palette.accent.opacity(0.7))
            Text("书架还是空的")
                .font(.custom("Songti SC", size: 17).weight(.semibold))
            Text("右上角 ＋ 放一本 epub 进来，\n我们就从同一页开始读。")
                .font(.custom("Songti SC", size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.secondaryText)
        }
        .padding(.top, 80)
        .frame(maxWidth: .infinity)
    }

    @MainActor
    private func loadShelf() async {
        isLoading = true
        defer { isLoading = false }
        do {
            books = try await model.bookShelf()
            errorText = nil
        } catch {
            errorText = "书架没加载出来：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func importBook(at url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            errorText = "这个文件读不出来：\(error.localizedDescription)"
            return
        }
        isImporting = true
        defer { isImporting = false }
        do {
            let result = try await model.importBook(data: data, name: name)
            await loadShelf()
            showNotice(result.hint ?? "《\(result.title)》拆成了 \(result.chapters) 章")
        } catch {
            errorText = "没导进去：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func delete(_ book: Book) async {
        do {
            try await model.removeBook(id: book.id)
            await loadShelf()
        } catch {
            errorText = "没撤掉：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func showNotice(_ text: String) {
        noticeText = text
        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if noticeText == text { noticeText = nil }
        }
    }

    private static var importableTypes: [UTType] {
        var types: [UTType] = [.plainText]
        if let epub = UTType("org.idpf.epub-container") { types.insert(epub, at: 0) }
        types.append(.data)
        return types
    }
}

private struct BookCard: View {
    let book: Book
    @ObservedObject var model: AppModel
    let palette: EchoPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottom) {
                if !book.cover.isEmpty, let request = model.authenticatedRequest(path: book.cover) {
                    BookRemoteImage(request: request)
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [palette.accent.opacity(0.28), palette.accent.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Text(book.title)
                            .font(.custom("Songti SC", size: 15).weight(.semibold))
                            .foregroundStyle(palette.text)
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                            .padding(12)
                    }
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Color.black.opacity(0.18)
                        palette.accent
                            .frame(width: geometry.size.width * CGFloat(min(100, max(0, book.percent)) / 100))
                    }
                }
                .frame(height: 3)
            }
            .frame(height: 168)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(book.title)
                .font(.custom("Songti SC", size: 15).weight(.semibold))
                .foregroundStyle(palette.text)
                .lineLimit(1)
            Text("\(Int(book.percent.rounded()))% · \(book.annotations) 处划线")
                .font(.custom("Songti SC", size: 12))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
        }
    }
}

struct BookRemoteImage: View {
    let request: URLRequest
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.08)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if failed {
                Image(systemName: "book.closed").foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .task(id: request.url) {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      let loaded = UIImage(data: data) else {
                    failed = true
                    return
                }
                image = loaded
            } catch {
                failed = true
            }
        }
    }
}

struct BookBanner: View {
    enum Tone { case neutral, error }

    let text: String
    var tone: Tone = .neutral

    var body: some View {
        Text(text)
            .font(.custom("Songti SC", size: 14))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                (tone == .error ? Color.red.opacity(0.9) : Color.black.opacity(0.78)),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
            .transition(.opacity)
    }
}
