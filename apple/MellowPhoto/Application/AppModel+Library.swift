import Foundation
import MellowLibrary
import MellowShared
import PhotosUI
import SwiftUI

extension AppModel {
    func importFromPicker(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        await runImport(await importer.stage(items))
    }

    func importFromFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        await runImport(await importer.stage(fileURLs: urls))
    }

    private func runImport(_ staged: [Result<StagedPhoto, Error>]) async {
        guard !isBusy else { return }
        isImporting = true
        defer { isImporting = false }
        let hadSelection = session.selectedPhotoID != nil
        let useCase = ImportPhotos(session: session, pipeline: pipeline, copies: copies)
        let report = await useCase.run(staged: staged) { [weak self] index, total in
            self?.statusMessage = UserMessage.importing(index, of: total)
        }
        for imported in report.added {
            remember(imported.id, imported.prepared)
        }
        statusMessage = UserMessage.photosStatus(count: session.photos.count)
        if !hadSelection, let id = session.selectedPhotoID {
            select(id)
        }
        var lines: [String] = []
        if !report.failures.isEmpty {
            lines.append(UserMessage.importFailures(count: report.failures.count))
            lines += report.failures.prefix(Policy.listedIssueLimit).map {
                UserMessage.photoLine(ordinal: $0.ordinal, $0.message)
            }
        }
        if report.skippedForCapacity > 0 {
            lines.append(UserMessage.skippedForCapacity(report.skippedForCapacity))
        }
        if lines.isEmpty {
            lines += report.warnings.prefix(Policy.listedIssueLimit)
        }
        if !lines.isEmpty {
            present(message: lines.joined(separator: "\n"))
        }
    }

    var canRemoveSelected: Bool { !isBusy && session.selected != nil }

    /// 앱의 작업 사본만 지운다. 사진 앱·사용자 파일 원본은 건드리지 않는다.
    func removeSelectedPhoto() {
        guard canRemoveSelected, let entry = session.selected else { return }
        do {
            try session.remove(entry.id)
        } catch {
            present(message: UserMessage.removeFailed(UserMessage.text(for: error)))
            return
        }
        cancelSelectionWork()
        thumbnails[entry.id] = nil
        photoInfo[entry.id] = nil
        preview = nil
        original = nil
        isReady = false
        selectionFailure = nil
        let pipeline = self.pipeline
        Task { await pipeline.evict(entry.id) }
        do {
            try copies.remove(filename: entry.filename)
        } catch {
            present(message: UserMessage.workingCopyCleanupFailed(error.localizedDescription))
        }
        if let next = session.selectedPhotoID {
            select(next)
        } else {
            statusMessage = UserMessage.welcomeStatus
        }
    }
}
