import Foundation
import MellowExport
import MellowLibrary

extension AppModel {
    /// 선택한 대상으로 현재 사진 또는 전체를 저장한다. 백그라운드 진입 시 cancelExport()를 부른다.
    func export(all: Bool, to destination: any ExportDestination) {
        guard !isBusy, isReady, let current = session.selected else { return }
        let entries = all ? session.photos : [current]
        let options = exportOptions
        let useCase = ExportPhotos(pipeline: pipeline, copies: copies, exporter: exporter)
        isExporting = true
        exportProgress = 0
        exportTask = Task { [weak self] in
            let total = entries.count
            let report = await useCase.run(entries: entries, options: options, destination: destination) { progress in
                self?.exportProgress = progress
                // (k/n)*n가 k보다 아주 조금 작을 수 있어 반올림한다.
                let done = Int((progress * Double(total)).rounded())
                self?.statusMessage = UserMessage.exporting(done, of: total)
            }
            guard let self else { return }
            isExporting = false
            statusMessage = UserMessage.exported(saved: report.saved, cancelled: report.cancelled)
            if !report.failures.isEmpty {
                let lines = report.failures.prefix(Policy.listedIssueLimit).map { "\($0.displayName): \($0.message)" }
                let summary = UserMessage.exportFailures(count: report.failures.count)
                present(message: ([summary] + lines).joined(separator: "\n"))
            }
        }
    }

    func cancelExport() {
        exportTask?.cancel()
    }
}
