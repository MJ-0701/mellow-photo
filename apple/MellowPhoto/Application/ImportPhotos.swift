import Foundation
import MellowEditing
import MellowLibrary
import MellowRendering
import MellowShared

struct ImportedPhoto {
    let id: PhotoID
    let prepared: PreparedPhoto
}

struct ImportFailure: Equatable {
    enum Stage: Equatable {
        case stage
        case copy
        case prepare
        case save
    }

    let ordinal: Int
    let stage: Stage
    let message: String
}

struct ImportReport {
    var added: [ImportedPhoto] = []
    var failures: [ImportFailure] = []
    var warnings: [String] = []
    var skippedForCapacity = 0
}

/// 사본 저장 → 분석 → 세션 추가. 어디서 실패하든 사본을 지운다.
@MainActor
struct ImportPhotos {
    let session: ProjectSession
    let pipeline: PhotoPipeline
    let copies: WorkingCopyStore

    func run(staged: [Result<StagedPhoto, Error>], onProgress: @MainActor (Int, Int) -> Void) async -> ImportReport {
        var report = ImportReport()
        for (offset, item) in staged.enumerated() {
            let ordinal = offset + 1
            onProgress(ordinal, staged.count)
            guard session.remainingCapacity > 0 else {
                report.skippedForCapacity += 1
                if case .success(let photo) = item {
                    try? FileManager.default.removeItem(at: photo.url)
                }
                continue
            }
            switch item {
            case .failure(let error):
                report.failures.append(
                    ImportFailure(ordinal: ordinal, stage: .stage, message: UserMessage.text(for: error)))
            case .success(let photo):
                await importOne(photo, ordinal: ordinal, into: &report)
            }
        }
        return report
    }

    private func importOne(_ photo: StagedPhoto, ordinal: Int, into report: inout ImportReport) async {
        let id = PhotoID()
        let filename: String
        do {
            filename = try copies.adopt(temporaryFile: photo.url, as: id)
        } catch {
            try? FileManager.default.removeItem(at: photo.url)
            report.failures.append(ImportFailure(ordinal: ordinal, stage: .copy, message: UserMessage.text(for: error)))
            return
        }
        let prepared: PreparedPhoto
        do {
            prepared = try await pipeline.prepare(id, at: copies.url(for: filename))
        } catch {
            await discard(id, filename: filename)
            report.failures.append(
                ImportFailure(ordinal: ordinal, stage: .prepare, message: UserMessage.text(for: error)))
            return
        }
        let displayName = photo.displayName ?? UserMessage.defaultPhotoName(number: session.photos.count + 1)
        do {
            try session.add(PhotoEntry(id: id, filename: filename, displayName: displayName))
        } catch {
            await discard(id, filename: filename)
            report.failures.append(ImportFailure(ordinal: ordinal, stage: .save, message: UserMessage.text(for: error)))
            return
        }
        if let failure = prepared.faceAnalysisFailure {
            report.warnings.append(UserMessage.photoLine(ordinal: ordinal, UserMessage.text(for: failure)))
        }
        report.added.append(ImportedPhoto(id: id, prepared: prepared))
    }

    private func discard(_ id: PhotoID, filename: String) async {
        await pipeline.evict(id)
        try? copies.remove(filename: filename)
    }
}
