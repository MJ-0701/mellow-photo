import Foundation
import MellowEditing
import MellowLibrary
import MellowRendering
import MellowShared

enum QuickRetouchAction: String, CaseIterable, Identifiable {
    case automatic, portrait, background, brighten, night
    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: return UserMessage.quickAutomatic
        case .portrait: return UserMessage.quickPortrait
        case .background: return UserMessage.quickBackground
        case .brighten: return UserMessage.quickBrighten
        case .night: return UserMessage.quickNight
        }
    }

    var detail: String {
        switch self {
        case .automatic: return UserMessage.quickAutomaticDetail
        case .portrait: return UserMessage.quickPortraitDetail
        case .background: return UserMessage.quickBackgroundDetail
        case .brighten: return UserMessage.quickBrightenDetail
        case .night: return UserMessage.quickNightDetail
        }
    }
}

extension AppModel {
    struct QuickRetouchProgress: Equatable {
        var total: Int
        var processed = 0
        var changed = 0
        var unchanged = 0
        var failed = 0
        var skipped = 0
        var cancelled = false
    }

    func quickUnavailableReason(_ action: QuickRetouchAction) -> String? {
        switch action {
        case .portrait:
            if selectedInfo?.faceAnalysisFailure != nil { return UserMessage.quickFaceUnavailable }
            return faces.isEmpty ? UserMessage.quickNoFace : nil
        case .background:
            switch backgroundAvailability {
            case .ready: return nil
            case .noPerson: return UserMessage.quickNoPerson
            case .unavailable: return UserMessage.quickPersonUnavailable
            }
        case .night:
            return lookCatalog.look(id: Policy.quickNightLookID) == nil ? UserMessage.quickNightUnavailable : nil
        case .automatic, .brighten:
            return nil
        }
    }

    func applyQuickAction(_ action: QuickRetouchAction) async {
        guard isReady, !isBusy, !isWorkStopped, quickUnavailableReason(action) == nil else { return }
        if action == .automatic || action == .brighten {
            await runPhotoAuto(action, allPhotos: false)
            return
        }
        if action == .portrait {
            beginOneTouchPrimaryAction(for: .all)
            return
        }
        endSliderEditIfActive()
        var changed = false
        mutateSelected { document in
            let before = document.recipe
            switch action {
            case .portrait:
                break
            case .background:
                _ = document.set(.backgroundBlur(Policy.quickBackgroundBlur))
            case .night:
                _ = document.applyLook(
                    LookSelection(id: Policy.quickNightLookID, intensity: Policy.quickNightIntensity))
            case .automatic, .brighten:
                break
            }
            changed = before != document.recipe
            return nil
        }
        statusMessage = changed ? UserMessage.quickApplied(action.title) : UserMessage.quickNoChange
    }

    func autoEnhanceAll() async {
        await runPhotoAuto(.automatic, allPhotos: true)
    }

    /// 사진 ID·문서 snapshot·요청 token을 함께 확인해 늦은 결과를 적용하지 않는다.
    func runPhotoAuto(_ action: QuickRetouchAction, allPhotos: Bool) async {
        guard isReady, !isBusy, !isWorkStopped, let selectedID = session.selectedPhotoID else { return }
        endSliderEditIfActive()
        let targets = allPhotos ? session.photos : session.photos.filter { $0.id == selectedID }
        guard !targets.isEmpty else { return }
        let runID = UUID()
        var report = QuickRetouchProgress(total: targets.count)
        var failures: [String] = []
        quickRetouchRunID = runID
        quickRetouchCancellationRequested = false
        quickRetouchProgress = report
        defer {
            if quickRetouchRunID == runID {
                report.cancelled = quickRetouchCancellationRequested || Task.isCancelled
                quickRetouchRunID = nil
                quickRetouchProgress = report
                statusMessage =
                    !report.cancelled && !allPhotos && report.changed == 1
                    ? UserMessage.quickApplied(action.title) : UserMessage.quickSummary(report)
                if action == .automatic && !report.cancelled && !allPhotos && report.changed == 1 {
                    statusMessage = UserMessage.autoEnhanced
                }
                if !report.cancelled && action == .brighten && report.unchanged == 1 {
                    statusMessage = UserMessage.quickBrightenUnchanged
                }
                if !failures.isEmpty {
                    present(message: failures.prefix(Policy.listedIssueLimit).joined(separator: "\n"))
                }
                if isReady && !isWorkStopped { scheduleRender() }
            }
        }
        for (index, entry) in targets.enumerated() {
            guard quickRetouchRunID == runID, !quickRetouchCancellationRequested else { return }
            if Task.isCancelled {
                cancelQuickRetouch()
                return
            }
            statusMessage = UserMessage.quickProcessing(index + 1, total: targets.count)
            guard session.index(of: entry.id) != nil else {
                report.skipped += 1
                report.processed += 1
                quickRetouchProgress = report
                continue
            }
            do {
                let result = try await pipeline.autoEnhanceOriginal(entry.id, at: copies.url(for: entry.filename))
                if session.index(of: entry.id) != nil {
                    remember(entry.id, result.photo, bindsLegacyPeople: false)
                }
                guard quickRetouchRunID == runID, !quickRetouchCancellationRequested else { return }
                if Task.isCancelled || session.selectedPhotoID != selectedID {
                    cancelQuickRetouch()
                    return
                }
                guard let targetIndex = session.index(of: entry.id),
                    session.photos[targetIndex].document == entry.document
                else {
                    report.skipped += 1
                    report.processed += 1
                    quickRetouchProgress = report
                    continue
                }
                guard let suggestion = result.suggestion else {
                    throw result.failure ?? MellowError.renderFailed
                }
                var changed = false
                session.endContinuousChange(entry.id)
                session.edit(entry.id) { document in
                    if action == .brighten {
                        let before = document.recipe
                        _ = document.set(
                            .exposure(max(document.recipe.color.exposure, max(0, suggestion.color.exposure))))
                        changed = before != document.recipe
                    } else {
                        let strength =
                            Policy.autoIncludesOneTouch && !result.photo.faces.isEmpty
                            ? EditingPolicy.oneTouchDefaultStrength : nil
                        changed = document.applyAuto(suggestion, oneTouchStrength: strength)
                    }
                    return nil
                }
                if changed { report.changed += 1 } else { report.unchanged += 1 }
                if let error = session.lastPersistenceError { present(error) }
            } catch {
                guard quickRetouchRunID == runID, !quickRetouchCancellationRequested else { return }
                if Task.isCancelled {
                    cancelQuickRetouch()
                    return
                }
                report.failed += 1
                failures.append(UserMessage.photoLine(ordinal: index + 1, UserMessage.text(for: error)))
            }
            report.processed += 1
            quickRetouchProgress = report
        }
    }

    func cancelQuickRetouch() {
        guard quickRetouchRunID != nil else { return }
        quickRetouchCancellationRequested = true
        if var report = quickRetouchProgress {
            report.cancelled = true
            quickRetouchProgress = report
            statusMessage = UserMessage.quickCancelling
        }
    }
}
