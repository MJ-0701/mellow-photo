import Foundation
import MellowExport
import MellowLibrary
import MellowRendering
import MellowShared

struct ExportFailure: Equatable {
    let displayName: String
    let error: MellowError?
    let message: String
}

struct ExportReport: Equatable {
    var saved = 0
    var failures: [ExportFailure] = []
    var cancelled = false
}

/// 렌더 → 임시 파일 → 대상 공개 → 임시 파일 정리. 취소는 Task 취소로 받는다.
struct ExportPhotos: Sendable {
    let pipeline: PhotoPipeline
    let copies: WorkingCopyStore
    let exporter: Exporter
    /// 렌더한 사진을 공개 전에 잠시 쓰는 폴더. 테스트는 자기 폴더를 넘겨 다른 실행과 섞이지 않게 한다.
    let temporaryDirectory: URL

    init(
        pipeline: PhotoPipeline, copies: WorkingCopyStore, exporter: Exporter,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.pipeline = pipeline
        self.copies = copies
        self.exporter = exporter
        self.temporaryDirectory = temporaryDirectory
    }

    func run(
        entries: [PhotoEntry], options: ExportOptions, destination: any ExportDestination,
        onProgress: @MainActor @Sendable (Double) -> Void
    ) async -> ExportReport {
        var report = ExportReport()
        for (index, entry) in entries.enumerated() {
            if Task.isCancelled {
                report.cancelled = true
                break
            }
            let temporary = temporaryDirectory.appendingPathComponent(
                "mellow-export-\(UUID().uuidString).\(options.format.fileExtension)")
            defer { try? FileManager.default.removeItem(at: temporary) }
            do {
                let image = try await pipeline.renderOriginal(
                    entry.id, at: copies.url(for: entry.filename), recipe: entry.document.recipe,
                    maxDimension: options.maxDimension)
                try exporter.write(image, to: temporary, format: options.format, quality: options.quality)
                try Task.checkCancellation()
                try await destination.publish(
                    fileURL: temporary, suggestedName: entry.displayName + FileNamingPolicy.suffix)
                report.saved += 1
            } catch is CancellationError {
                report.cancelled = true
                break
            } catch {
                report.failures.append(
                    ExportFailure(
                        displayName: entry.displayName, error: error as? MellowError,
                        message: UserMessage.text(for: error)))
            }
            await onProgress(Double(index + 1) / Double(entries.count))
        }
        return report
    }
}
