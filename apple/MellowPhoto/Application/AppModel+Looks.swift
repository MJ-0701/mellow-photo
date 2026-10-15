import CoreGraphics
import MellowRendering
import MellowShared

extension AppModel {
    /// 선택 사진의 룩 썸네일을 한 번만 만든다. 늦게 온 결과는 사진 id 키로 들어가므로 다른 사진에 붙지 않는다.
    func loadLookThumbnails() {
        guard let entry = session.selected, isReady, !lookCatalog.all.isEmpty else { return }
        let id = entry.id
        guard lookThumbnails[id] == nil, !lookThumbnailRequests.contains(id) else { return }
        lookThumbnailRequests.insert(id)
        let pipeline = self.pipeline
        let url = copies.url(for: entry.filename)
        Task { [weak self] in
            do {
                try await pipeline.reprepareIfEvicted(id, at: url)
                let thumbnails = try await pipeline.lookThumbnails(id)
                self?.finishLookThumbnails(id, thumbnails)
            } catch {
                self?.lookThumbnailRequests.remove(id)
                self?.present(error)
            }
        }
    }

    /// 기다리는 동안 사진을 뺐으면 결과를 버린다.
    private func finishLookThumbnails(_ id: PhotoID, _ thumbnails: [String: CGImage]) {
        guard lookThumbnailRequests.remove(id) != nil, session.index(of: id) != nil else { return }
        lookThumbnails[id] = thumbnails
    }

    /// 원본 분석으로 제안을 받아 체크포인트 한 번으로 적용한다.
    func autoEnhance() async {
        guard let entry = session.selected, isReady, !isBusy else { return }
        do {
            try await pipeline.reprepareIfEvicted(entry.id, at: copies.url(for: entry.filename))
            let suggestion = try await pipeline.autoEnhanceSuggestion(entry.id, hasFaces: !faces.isEmpty)
            guard session.selectedPhotoID == entry.id else { return }
            if applyAutoSuggestion(suggestion) {
                statusMessage = UserMessage.autoEnhanced
            }
        } catch {
            present(error)
        }
    }
}
