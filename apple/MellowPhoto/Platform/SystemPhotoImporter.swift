import CoreTransferable
import Foundation
import MellowShared
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// PhotosPicker 항목을 임시 파일로 받는 Transferable.
private struct ImportedPhotoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let url = try SystemPhotoImporter.stagingURL(extension: received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: url)
            return ImportedPhotoFile(url: url)
        }
    }
}

struct SystemPhotoImporter: PhotoImporter {
    static let stagingFolder = FileManager.default.temporaryDirectory.appendingPathComponent(
        "MellowImports", isDirectory: true)
    /// 받은 파일에 확장자가 없을 때 붙이는 확장자.
    static let fallbackExtension = "image"

    static func stagingURL(extension fileExtension: String) throws -> URL {
        try FileManager.default.createDirectory(at: stagingFolder, withIntermediateDirectories: true)
        let resolvedExtension = fileExtension.isEmpty ? fallbackExtension : fileExtension
        return stagingFolder.appendingPathComponent(UUID().uuidString).appendingPathExtension(resolvedExtension)
    }

    func stage(_ items: [PhotosPickerItem]) async -> [Result<StagedPhoto, Error>] {
        var results: [Result<StagedPhoto, Error>] = []
        for item in items {
            do {
                guard let file = try await item.loadTransferable(type: ImportedPhotoFile.self) else {
                    throw MellowError.cannotOpenPhoto(filename: UserMessage.photoLibraryItemName)
                }
                results.append(.success(StagedPhoto(url: file.url, displayName: nil)))
            } catch {
                results.append(.failure(error))
            }
        }
        return results
    }

    /// fileImporter·드롭으로 받은 파일. 보안 범위 접근 안에서 복사만 한다.
    func stage(fileURLs: [URL]) async -> [Result<StagedPhoto, Error>] {
        fileURLs.map { url in
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw MellowError.cannotOpenPhoto(filename: url.lastPathComponent)
                }
                let staged = try Self.stagingURL(extension: url.pathExtension)
                try FileManager.default.copyItem(at: url, to: staged)
                return .success(StagedPhoto(url: staged, displayName: url.deletingPathExtension().lastPathComponent))
            } catch {
                return .failure(error)
            }
        }
    }
}
