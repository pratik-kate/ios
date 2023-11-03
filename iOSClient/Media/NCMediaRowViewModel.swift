//
//  NCMediaRowViewModel.swift
//  Nextcloud
//
//  Created by Milen on 05.09.23.
//  Copyright © 2023 Marino Faggiana. All rights reserved.
//

import Foundation
import NextcloudKit
import Queuer

struct RowData {
    var scaledThumbnails: [ScaledThumbnail] = []
    var shrinkRatio: CGFloat = 0
}

struct ScaledThumbnail: Hashable {
    let image: UIImage
    var isPlaceholderImage = false
    var scaledSize: CGSize = .zero
    let metadata: tableMetadata

    func hash(into hasher: inout Hasher) {
        hasher.combine(metadata.ocId)
    }
}

@MainActor class NCMediaRowViewModel: ObservableObject {
    @Published private(set) var rowData = RowData()

    private var metadatas: [tableMetadata] = []

    private let cache = NCImageCache.shared

//    private let appDelegate = UIApplication.shared.delegate as? AppDelegate
    //    private let queuer = (UIApplication.shared.delegate as? AppDelegate)?.downloadThumbnailQueue
    private var queuer: Queuer?

    //    internal lazy var cache = manager.cache
    //    internal lazy var thumbnailsQueue = manager.queuer

    var operations: [ConcurrentOperation] = []

    func configure(metadatas: [tableMetadata], queuer: Queuer) {
        self.metadatas = metadatas
        self.queuer = queuer
    }

    func downloadThumbnails(rowWidth: CGFloat, spacing: CGFloat) {
        var thumbnails: [ScaledThumbnail] = []

        metadatas.forEach { metadata in
            let thumbnailPath = NCUtilityFileSystem().getDirectoryProviderStorageIconOcId(metadata.ocId, etag: metadata.etag)
            if let cachedImage = cache.getMediaImage(ocId: metadata.ocId) {
                let thumbnail: ScaledThumbnail

                if case let .actual(image) = cachedImage {
                    thumbnail = ScaledThumbnail(image: image, metadata: metadata)
                } else {
                    let image = UIImage(systemName: metadata.isVideo ? "video.fill" : "photo.fill")!.withRenderingMode(.alwaysTemplate)
                    thumbnail = ScaledThumbnail(image: image, isPlaceholderImage: true, metadata: metadata)
                }

                DispatchQueue.main.async {
                    thumbnails.append(thumbnail)
                    self.calculateShrinkRatio(metadatas: self.metadatas, rowData: &self.rowData, thumbnails: &thumbnails, rowWidth: rowWidth, spacing: spacing)
                }
            } else if FileManager.default.fileExists(atPath: thumbnailPath) {
                // Load thumbnail from file
                if let image = UIImage(contentsOfFile: thumbnailPath) {
                    let thumbnail = ScaledThumbnail(image: image, metadata: metadata)
                    cache.setMediaImage(ocId: metadata.ocId, image: .actual(image))
                    //                    cache.setValue(thumbnail, forKey: metadata.ocId)

                    DispatchQueue.main.async {
                        thumbnails.append(thumbnail)
                        self.calculateShrinkRatio(metadatas: self.metadatas, rowData: &self.rowData, thumbnails: &thumbnails, rowWidth: rowWidth, spacing: spacing)
                    }
                }
            } else {
                let fileNamePath = NCUtilityFileSystem().getFileNamePath(metadata.fileName, serverUrl: metadata.serverUrl, urlBase: metadata.urlBase, userId: metadata.userId)
                let fileNamePreviewLocalPath = NCUtilityFileSystem().getDirectoryProviderStoragePreviewOcId(metadata.ocId, etag: metadata.etag)
                let fileNameIconLocalPath = NCUtilityFileSystem().getDirectoryProviderStorageIconOcId(metadata.ocId, etag: metadata.etag)

                var etagResource: String?
                if FileManager.default.fileExists(atPath: fileNameIconLocalPath) && FileManager.default.fileExists(atPath: fileNamePreviewLocalPath) {
                    etagResource = metadata.etagResource
                }
                let options = NKRequestOptions(queue: NextcloudKit.shared.nkCommonInstance.backgroundQueue)

                //                let concurrentOperation = ConcurrentOperation { operation in
                //                    operation.execute()
                //
                //                    NextcloudKit.shared.downloadPreview(
                //                        fileNamePathOrFileId: fileNamePath,
                //                        fileNamePreviewLocalPath: fileNamePreviewLocalPath,
                //                        widthPreview: Int(UIScreen.main.bounds.width) / 2,
                //                        heightPreview: Int(UIScreen.main.bounds.height) / 2,
                //                        fileNameIconLocalPath: fileNameIconLocalPath,
                //                        sizeIcon: NCGlobal.shared.sizeIcon,
                //                        etag: etagResource,
                //                        options: options) { _, _, imageIcon, _, etag, error in
                //                            NCManageDatabase.shared.setMetadataEtagResource(ocId: metadata.ocId, etagResource: etag)
                //
                //                            let thumbnail: ScaledThumbnail
                //
                //                            if error == .success, let image = imageIcon {
                //                                thumbnail = ScaledThumbnail(image: image, metadata: metadata)
                //                                self.cache.setMediaImage(ocId: metadata.ocId, image: image)
                //                            } else {
                //                                thumbnail = ScaledThumbnail(image: UIImage(systemName: metadata.isVideo ? "video.fill" : "photo.fill")!.withRenderingMode(.alwaysTemplate), isPlaceholderImage: true, metadata: metadata)
                //                            }
                //
                ////                            self.cache.setValue(thumbnail, forKey: metadata.ocId)
                //
                //                            operation.finish()
                //
                //                            DispatchQueue.main.async {
                //                                thumbnails.append(thumbnail)
                //                                self.calculateShrinkRatio(thumbnails: &thumbnails, rowWidth: rowWidth, spacing: spacing)
                //                            }
                //
                //                        }
                //                }

                if let queuer, queuer.operations.filter({ ($0 as? NCMediaDownloadThumbnaill)?.metadata.ocId == metadata.ocId }).isEmpty {
                    let concurrentOperation = NCMediaDownloadThumbnaill(metadata: metadata, cache: cache, rowWidth: rowWidth, spacing: spacing, maxWidth: UIScreen.main.bounds.width, maxHeight: UIScreen.main.bounds.height) { thumbnail in
                        DispatchQueue.main.async {
                            thumbnails.append(thumbnail)
                            self.calculateShrinkRatio(metadatas: self.metadatas, rowData: &self.rowData, thumbnails: &thumbnails, rowWidth: rowWidth, spacing: spacing)
                        }
                    }

                    operations.append(concurrentOperation)
                    queuer.addOperation(concurrentOperation)
                    print(queuer.operationCount)
                }

                //                let concurrentOperation = NCMediaDownloadThumbnaill(metadata: metadata, cache: cache, thumbnails: &thumbnails, rowWidth: rowWidth, spacing: spacing, maxWidth: UIScreen.main.bounds.width, maxHeight: UIScreen.main.bounds.height)

                //                operations.append(concurrentOperation)
                //                appDelegate?.downloadThumbnailQueue.addOperation(concurrentOperation)
                //                print(appDelegate!.downloadThumbnailQueue.operationCount)

                //                concurrentOperation.start()
            }
        }
    }

    class NCMediaDownloadThumbnaill: ConcurrentOperation {
        let metadata: tableMetadata
        let cache: NCImageCache
        let rowWidth: CGFloat
        let spacing: CGFloat
        let maxWidth: CGFloat
        let maxHeight: CGFloat

        let onThumbnailDownloaded: (ScaledThumbnail) -> Void

        init(metadata: tableMetadata, cache: NCImageCache, rowWidth: CGFloat, spacing: CGFloat, maxWidth: CGFloat, maxHeight: CGFloat, onThumbnailDownloaded: @escaping (ScaledThumbnail) -> Void) {
            self.metadata = metadata
            self.cache = cache
            self.rowWidth = rowWidth
            self.spacing = spacing
            self.maxWidth = maxWidth
            self.maxHeight = maxHeight
            self.onThumbnailDownloaded = onThumbnailDownloaded
        }

        //        var cell: NCCellProtocol?
        //        var collectionView: UICollectionView?
        //        var fileNamePath: String
        //        var fileNamePreviewLocalPath: String
        //        var fileNameIconLocalPath: String
        //        let utilityFileSystem = NCUtilityFileSystem()

        //        init(metadata: tableMetadata, cell: NCCellProtocol?, collectionView: UICollectionView?) {
        //            self.metadata = tableMetadata.init(value: metadata)
        ////            self.cell = cell
        ////            self.collectionView = collectionView
        ////            self.fileNamePath = utilityFileSystem.getFileNamePath(metadata.fileName, serverUrl: metadata.serverUrl, urlBase: metadata.urlBase, userId: metadata.userId)
        ////            self.fileNamePreviewLocalPath = utilityFileSystem.getDirectoryProviderStoragePreviewOcId(metadata.ocId, etag: metadata.etag)
        ////            self.fileNameIconLocalPath = utilityFileSystem.getDirectoryProviderStorageIconOcId(metadata.ocId, etag: metadata.etag)
        //        }

        override func start() {
            guard !isCancelled else { return self.finish() }

            let fileNamePath = NCUtilityFileSystem().getFileNamePath(metadata.fileName, serverUrl: metadata.serverUrl, urlBase: metadata.urlBase, userId: metadata.userId)
            let fileNamePreviewLocalPath = NCUtilityFileSystem().getDirectoryProviderStoragePreviewOcId(metadata.ocId, etag: metadata.etag)
            let fileNameIconLocalPath = NCUtilityFileSystem().getDirectoryProviderStorageIconOcId(metadata.ocId, etag: metadata.etag)

            var etagResource: String?
            if FileManager.default.fileExists(atPath: fileNameIconLocalPath) && FileManager.default.fileExists(atPath: fileNamePreviewLocalPath) {
                etagResource = metadata.etagResource
            }
            let options = NKRequestOptions(queue: NextcloudKit.shared.nkCommonInstance.backgroundQueue)

            //            let concurrentOperation = ConcurrentOperation { operation in
            NextcloudKit.shared.downloadPreview(
                fileNamePathOrFileId: fileNamePath,
                fileNamePreviewLocalPath: fileNamePreviewLocalPath,
                widthPreview: Int(self.maxWidth) / 2,
                heightPreview: Int(self.maxHeight) / 2,
                fileNameIconLocalPath: fileNameIconLocalPath,
                sizeIcon: NCGlobal.shared.sizeIcon,
                etag: etagResource,
                options: options) { _, _, imageIcon, _, etag, error in
                    NCManageDatabase.shared.setMetadataEtagResource(ocId: self.metadata.ocId, etagResource: etag)

                    let thumbnail: ScaledThumbnail

                    if error == .success, let image = imageIcon {
                        thumbnail = ScaledThumbnail(image: image, metadata: self.metadata)
                        self.cache.setMediaImage(ocId: self.metadata.ocId, image: .actual(image))
                    } else {
                        let image = UIImage(systemName: self.metadata.isVideo ? "video.fill" : "photo.fill")!.withRenderingMode(.alwaysTemplate)
                        thumbnail = ScaledThumbnail(image: image, isPlaceholderImage: true, metadata: self.metadata)
                        self.cache.setMediaImage(ocId: self.metadata.ocId, image: .placeholder)
                    }

                    self.onThumbnailDownloaded(thumbnail)

                    //                            self.cache.setValue(thumbnail, forKey: metadata.ocId)

                    //                        DispatchQueue.main.async {
                    //                            self.thumbnails.append(thumbnail)
                    //                            NCMediaRowViewModel.calculateShrinkRatio(metadatas: self.metadatas, rowData: &self.rowData, thumbnails: &self.thumbnails, rowWidth: self.rowWidth, spacing: self.spacing)
                    //                        }

                    self.finish()
                    //                    }
                }


        }


    }

    private func calculateShrinkRatio(metadatas: [tableMetadata], rowData: inout RowData, thumbnails: inout [ScaledThumbnail], rowWidth: CGFloat, spacing: CGFloat) {
        if thumbnails.count == metadatas.count {
            thumbnails.enumerated().forEach { index, thumbnail in
                thumbnails[index].scaledSize = getScaledThumbnailSize(of: thumbnail, thumbnailsInRow: thumbnails)
            }

            let shrinkRatio = getShrinkRatio(thumbnailsInRow: thumbnails, fullWidth: rowWidth, spacing: spacing)

            rowData.scaledThumbnails = thumbnails
            rowData.shrinkRatio = shrinkRatio
        }
    }

    private func getScaledThumbnailSize(of thumbnail: ScaledThumbnail, thumbnailsInRow thumbnails: [ScaledThumbnail]) -> CGSize {
        let maxHeight = thumbnails.compactMap { CGFloat($0.image.size.height) }.max() ?? 0

        let height = thumbnail.image.size.height
        let width = thumbnail.image.size.width

        let scaleFactor = maxHeight / height
        let newHeight = height * scaleFactor
        let newWidth = width * scaleFactor

        return .init(width: newWidth, height: newHeight)
    }

    private func getShrinkRatio(thumbnailsInRow thumbnails: [ScaledThumbnail], fullWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        var newSummedWidth: CGFloat = 0

        for thumbnail in thumbnails {
            newSummedWidth += CGFloat(thumbnail.scaledSize.width)
        }

        let spacingWidth = spacing * CGFloat(thumbnails.count - 1)
        let shrinkRatio: CGFloat = (fullWidth - spacingWidth) / newSummedWidth

        return shrinkRatio
    }

    func cancelDownloadingThumbnails() {
        //        operations.forEach {( $0.cancel() )}
        //        operations.removeAll()
    }

    //    private func getScaledThumbnailSize(of thumbnail: ScaledThumbnail, thumbnailsInRow thumbnails: [ScaledThumbnail]) -> CGSize {
    //        let maxHeight = thumbnails.compactMap { CGFloat($0.image.size.height) }.max() ?? 0
    //
    //        let height = thumbnail.image.size.height
    //        let width = thumbnail.image.size.width
    //
    //        let scaleFactor = maxHeight / height
    //        let newHeight = height * scaleFactor
    //        let newWidth = width * scaleFactor
    //
    //        return .init(width: newWidth, height: newHeight)
    //    }
    //
    //    private func getShrinkRatio(thumbnailsInRow thumbnails: [ScaledThumbnail], fullWidth: CGFloat, spacing: CGFloat) -> CGFloat {
    //        var newSummedWidth: CGFloat = 0
    //
    //        for thumbnail in thumbnails {
    //            newSummedWidth += CGFloat(thumbnail.scaledSize.width)
    //        }
    //
    //        let spacingWidth = spacing * CGFloat(thumbnails.count - 1)
    //        let shrinkRatio: CGFloat = (fullWidth - spacingWidth) / newSummedWidth
    //
    //        return shrinkRatio
    //    }
}
