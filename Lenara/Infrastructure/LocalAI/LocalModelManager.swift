import Foundation
import Combine
import CryptoKit

struct LocalModel: Identifiable, Sendable {
    let id: String
    let name: String
    let detail: String
    let repository: String
    let revision: String
    let filename: String
    let bytes: Int64
    let sha256: String
    let license: String

    var downloadURL: URL {
        URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(filename)")!
    }
    var sizeLabel: String { "\(Int((Double(bytes) / 1_000_000).rounded())) MB" }

    static let recommendedID = "smollm2-17-q2"
    static var recommended: LocalModel { catalog.first { $0.id == recommendedID }! }

    static let catalog: [LocalModel] = [
        LocalModel(
            id: "qwen25-05-q5", name: "Qwen2.5 0.5B", detail: "Instruct · Q5_K_M", repository: "bartowski/Qwen2.5-0.5B-Instruct-GGUF",
            revision: "41ba88dbac95fed2528c92514c131d73eb5a174b", filename: "Qwen2.5-0.5B-Instruct-Q5_K_M.gguf",
            bytes: 420_086_336, sha256: "a0a413dcbb4676f21d4c951b98a393324694edb1a20a4f9547d1de8d2919ff3b", license: "Apache-2.0"
        ),
        LocalModel(
            id: "smollm2-17-q2", name: "SmolLM2 1.7B", detail: "Instruct · Q2_K · calidad reducida", repository: "bartowski/SmolLM2-1.7B-Instruct-GGUF",
            revision: "5a10ab203991b27e900d37dc027ffa339a5dca43", filename: "SmolLM2-1.7B-Instruct-Q2_K.gguf",
            bytes: 674_583_520, sha256: "542b86d51bcb65f455f0311e25426d230b1ba24f35c5a71d1b1ecfe2dcd400c4", license: "Apache-2.0"
        ),
        LocalModel(
            id: "tinyllama-11-q4", name: "TinyLlama 1.1B", detail: "Chat · Q4_K_M", repository: "TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF",
            revision: "52e7645ba7c309695bec7ac98f4f005b139cf465", filename: "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
            bytes: 668_788_096, sha256: "9fecc3b3cd76bba89d504f29b616eedf7da85b96540e490ca5824d3f7d2776a0", license: "Apache-2.0"
        )
    ]
}

@MainActor
final class LocalModelManager: ObservableObject {
    static let shared = LocalModelManager()
    @Published private(set) var downloadedIDs: Set<String> = []
    @Published private(set) var downloadingID: String?
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var modelsBytes: Int64 = 0
    @Published var selectedID: String {
        didSet { UserDefaults.standard.set(selectedID, forKey: "lenara.localModel.selected") }
    }

    private var downloadTask: _Concurrency.Task<Void, Never>?
    private var urlSession: URLSession?
    private var downloadDelegate: ModelDownloadDelegate?
    private let root: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = base.appendingPathComponent("Lenara/Models", isDirectory: true)
        let recommendedURL = root.appendingPathComponent(LocalModel.recommended.filename)
        selectedID = FileManager.default.fileExists(atPath: recommendedURL.path) ? LocalModel.recommendedID : ""
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableRoot = root
        try? mutableRoot.setResourceValues(values)
        refresh()
    }

    func fileURL(for id: String) -> URL? {
        guard downloadedIDs.contains(id), let model = LocalModel.catalog.first(where: { $0.id == id }) else { return nil }
        return root.appendingPathComponent(model.filename)
    }

    func download(_ model: LocalModel) {
        guard downloadingID == nil, !downloadedIDs.contains(model.id) else { return }
        downloadingID = model.id
        downloadProgress = 0
        errorMessage = nil
        downloadTask = _Concurrency.Task {
            var partialDownload: URL?
            defer {
                if let partialDownload { try? FileManager.default.removeItem(at: partialDownload) }
                downloadingID = nil
                downloadTask = nil
                urlSession?.invalidateAndCancel()
                urlSession = nil
                downloadDelegate = nil
                downloadProgress = 0
            }
            do {
                let fileSystem = try FileManager.default.attributesOfFileSystem(forPath: root.path)
                let freeBytes = (fileSystem[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
                guard freeBytes >= model.bytes + 150_000_000 else { throw ModelError.insufficientSpace }
                let temporaryURL = try await downloadFile(from: model.downloadURL)
                partialDownload = temporaryURL
                try _Concurrency.Task.checkCancellation()
                let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
                guard (attributes[.size] as? NSNumber)?.int64Value == model.bytes else { throw ModelError.invalidFile }
                let handle = try FileHandle(forReadingFrom: temporaryURL)
                defer { try? handle.close() }
                guard try handle.read(upToCount: 4) == Data("GGUF".utf8) else { throw ModelError.invalidFile }
                try handle.seek(toOffset: 0)
                var digest = SHA256()
                while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { digest.update(data: chunk) }
                let actualHash = digest.finalize().map { String(format: "%02x", $0) }.joined()
                guard actualHash == model.sha256 else { throw ModelError.invalidFile }
                let destination = root.appendingPathComponent(model.filename)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                partialDownload = nil
                downloadedIDs.insert(model.id)
                selectedID = model.id
                refreshBytes()
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                errorMessage = error is ModelError && (error as? ModelError) == .insufficientSpace
                    ? "No hay espacio libre suficiente para descargar \(model.name)."
                    : "No se pudo descargar \(model.name). Comprueba la conexión y vuelve a intentarlo."
            }
        }
    }

    func cancelDownload() { downloadTask?.cancel() }

    private func downloadFile(from url: URL) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let delegate = ModelDownloadDelegate(root: root) { [weak self] progress in
                    _Concurrency.Task { @MainActor in self?.downloadProgress = progress }
                } completion: { result in
                    continuation.resume(with: result)
                }
                let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
                urlSession = session
                downloadDelegate = delegate
                session.downloadTask(with: url).resume()
            }
        } onCancel: {
            _Concurrency.Task { @MainActor [weak self] in self?.urlSession?.invalidateAndCancel() }
        }
    }

    func delete(_ model: LocalModel) {
        guard downloadingID != model.id else { cancelDownload(); return }
        if let url = fileURL(for: model.id) { try? FileManager.default.removeItem(at: url) }
        downloadedIDs.remove(model.id)
        if selectedID == model.id { selectedID = "" }
        refreshBytes()
    }

    func deleteAllModels() async {
        cancelDownload()
        if let downloadTask { await downloadTask.value }
        for model in LocalModel.catalog {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(model.filename))
        }
        downloadedIDs = []
        selectedID = ""
        refreshBytes()
    }

    func refresh() {
        downloadedIDs = Set(LocalModel.catalog.compactMap { model in
            guard let values = try? root.appendingPathComponent(model.filename).resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = values.fileSize, Int64(fileSize) == model.bytes else { return nil }
            return model.id
        })
        selectedID = downloadedIDs.contains(LocalModel.recommendedID) ? LocalModel.recommendedID : ""
        refreshBytes()
    }

    private func refreshBytes() {
        modelsBytes = LocalModel.catalog.filter { downloadedIDs.contains($0.id) }.reduce(0) { $0 + $1.bytes }
    }

    enum ModelError: Error, Equatable { case badResponse, invalidFile, insufficientSpace }
}

private final class ModelDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let root: URL
    private let onProgress: (Double) -> Void
    private let completion: (Result<URL, Error>) -> Void
    private var finished = false
    private var lastReportedPercent = -1

    init(root: URL, onProgress: @escaping (Double) -> Void, completion: @escaping (Result<URL, Error>) -> Void) {
        self.root = root
        self.onProgress = onProgress
        self.completion = completion
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let percent = Int(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100)
        guard percent != lastReportedPercent else { return }
        lastReportedPercent = percent
        onProgress(min(1, Double(percent) / 100))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            finish(.failure(URLError(.badServerResponse))); return
        }
        do {
            let destination = root.appendingPathComponent("download-\(UUID().uuidString).tmp")
            try FileManager.default.moveItem(at: location, to: destination)
            onProgress(1)
            finish(.success(destination))
        } catch { finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !finished else { return }
        finished = true
        completion(result)
    }
}
