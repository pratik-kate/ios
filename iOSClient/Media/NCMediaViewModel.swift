//
//  NCMediaViewModel.swift
//  Nextcloud
//
//  Created by Milen on 05.09.23.
//  Copyright © 2023 Marino Faggiana. All rights reserved.
//

import NextcloudKit
import Combine

@MainActor class NCMediaViewModel: ObservableObject {
    @Published var metadatas: [tableMetadata] = []

    private var account: String = ""
    private var lastContentOffsetY: CGFloat = 0
    private var mediaPath = ""
    private var livePhoto: Bool = false
    private var predicateDefault: NSPredicate?
    private var predicate: NSPredicate?
    private let appDelegate = UIApplication.shared.delegate as? AppDelegate
    @Published internal var filterClassTypeImage = false
    @Published internal var filterClassTypeVideo = false

    private var cancellables: Set<AnyCancellable> = []

    internal var needsLoadingMoreItems = true

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(deleteFile(_:)), name: NSNotification.Name(rawValue: NCGlobal.shared.notificationCenterDeleteFile), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(moveFile(_:)), name: NSNotification.Name(rawValue: NCGlobal.shared.notificationCenterMoveFile), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(copyFile(_:)), name: NSNotification.Name(rawValue: NCGlobal.shared.notificationCenterCopyFile), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(renameFile(_:)), name: NSNotification.Name(rawValue: NCGlobal.shared.notificationCenterRenameFile), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(uploadedFile(_:)), name: NSNotification.Name(rawValue: NCGlobal.shared.notificationCenterUploadedFile), object: nil)

        searchNewMedia()

        $filterClassTypeImage.sink { _ in self.loadData() }.store(in: &cancellables)
        $filterClassTypeVideo.sink{ _ in self.loadData() }.store(in: &cancellables)
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: NCGlobal.shared.notificationCenterDeleteFile), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: NCGlobal.shared.notificationCenterMoveFile), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: NCGlobal.shared.notificationCenterCopyFile), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: NCGlobal.shared.notificationCenterRenameFile), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: NCGlobal.shared.notificationCenterUploadedFile), object: nil)
    }

    func loadData() {
        guard let appDelegate, !appDelegate.account.isEmpty else { return }

        if account != appDelegate.account {
            self.metadatas = []
            account = appDelegate.account
        }

        self.queryDB(isForced: true)
    }

    private func queryDB(isForced: Bool = false) {
        guard let appDelegate else { return }

        livePhoto = CCUtility.getLivePhoto()

        if let activeAccount = NCManageDatabase.shared.getActiveAccount() {
            self.mediaPath = activeAccount.mediaPath
        }

        let startServerUrl = NCUtilityFileSystem.shared.getHomeServer(urlBase: appDelegate.urlBase, userId: appDelegate.userId) + mediaPath

        predicateDefault = NSPredicate(format: "account == %@ AND serverUrl BEGINSWITH %@ AND (classFile == %@ OR classFile == %@) AND NOT (session CONTAINS[c] 'upload')", appDelegate.account, startServerUrl, NKCommon.TypeClassFile.image.rawValue, NKCommon.TypeClassFile.video.rawValue)

        if filterClassTypeImage {
            predicate = NSPredicate(format: "account == %@ AND serverUrl BEGINSWITH %@ AND classFile == %@ AND NOT (session CONTAINS[c] 'upload')", appDelegate.account, startServerUrl, NKCommon.TypeClassFile.video.rawValue)
        } else if filterClassTypeVideo {
            predicate = NSPredicate(format: "account == %@ AND serverUrl BEGINSWITH %@ AND classFile == %@ AND NOT (session CONTAINS[c] 'upload')", appDelegate.account, startServerUrl, NKCommon.TypeClassFile.image.rawValue)
        } else {
            predicate = predicateDefault
        }

        guard let predicate = predicate else { return }

        DispatchQueue.main.async {
            self.metadatas = NCManageDatabase.shared.getMetadatasMedia(predicate: predicate, livePhoto: self.livePhoto)

            switch CCUtility.getMediaSortDate() {
            case "date":
                self.metadatas = self.metadatas.sorted(by: {($0.date as Date) > ($1.date as Date)})
            case "creationDate":
                self.metadatas = self.metadatas.sorted(by: {($0.creationDate as Date) > ($1.creationDate as Date)})
            case "uploadDate":
                self.metadatas = self.metadatas.sorted(by: {($0.uploadDate as Date) > ($1.uploadDate as Date)})
            default:
                break
            }
        }
    }

    func loadMoreItems() {
        searchOldMedia()
        needsLoadingMoreItems = false
    }

    func onPullToRefresh() {
        searchNewMedia()
    }

    func onCellTapped(metadata: tableMetadata) {
        appDelegate?.activeServerUrl = metadata.serverUrl
    }
}

// MARK: Notifications

extension NCMediaViewModel {
    @objc func deleteFile(_ notification: NSNotification) {
        guard let userInfo = notification.userInfo as NSDictionary?,
              let error = userInfo["error"] as? NKError else { return }
        let onlyLocalCache: Bool = userInfo["onlyLocalCache"] as? Bool ?? false

        self.queryDB(isForced: true)

        if error == .success, let indexPath = userInfo["indexPath"] as? [IndexPath], !indexPath.isEmpty, !onlyLocalCache {
            //            collectionView?.performBatchUpdates({
            //                collectionView?.deleteItems(at: indexPath)
            //            }, completion: { _ in
            //                self.collectionView?.reloadData()
            //            })
        } else {
            if error != .success {
                NCContentPresenter.shared.showError(error: error)
            }
            //            self.collectionView?.reloadData()
        }

        //        if let hud = userInfo["hud"] as? JGProgressHUD {
        //            hud.dismiss()
        //        }
    }

    @objc func moveFile(_ notification: NSNotification) {
        guard let userInfo = notification.userInfo as NSDictionary? else { return }

        //        if let hud = userInfo["hud"] as? JGProgressHUD {
        //            hud.dismiss()
        //        }
    }

    @objc func copyFile(_ notification: NSNotification) {
        moveFile(notification)
    }

    @objc func renameFile(_ notification: NSNotification) {
        guard let userInfo = notification.userInfo as NSDictionary?,
              let account = userInfo["account"] as? String,
              account == appDelegate?.account
        else { return }

        self.loadData()
    }

    @objc func uploadedFile(_ notification: NSNotification) {
        guard let userInfo = notification.userInfo as NSDictionary?,
              let error = userInfo["error"] as? NKError,
              error == .success,
              let account = userInfo["account"] as? String,
              account == appDelegate?.account
        else { return }

        self.loadData()
    }
}

// MARK: - Search media

extension NCMediaViewModel {
    private func searchOldMedia(value: Int = -30, limit: Int = 300) {

//        if oldInProgress { return } else { oldInProgress = true }
//        DispatchQueue.main.async {
//            self.collectionView.reloadData()
//            var bottom: CGFloat = 0
//            if let mainTabBar = self.tabBarController?.tabBar as? NCMainTabBar {
//                bottom = -mainTabBar.getHight()
//            }
//            NCActivityIndicator.shared.start(backgroundView: self.view, bottom: bottom - 5, style: .medium)
//        }

        var lessDate = Date()
        if predicateDefault != nil {
            if let metadata = NCManageDatabase.shared.getMetadata(predicate: predicateDefault!, sorted: "date", ascending: true) {
                lessDate = metadata.date as Date
            }
        }

        var greaterDate: Date
        if value == -999 {
            greaterDate = Date.distantPast
        } else {
            greaterDate = Calendar.current.date(byAdding: .day, value: value, to: lessDate)!
        }

        let options = NKRequestOptions(timeout: 300, queue: NextcloudKit.shared.nkCommonInstance.backgroundQueue)

        NextcloudKit.shared.searchMedia(path: mediaPath, lessDate: lessDate, greaterDate: greaterDate, elementDate: "d:getlastmodified/", limit: limit, showHiddenFiles: CCUtility.getShowHiddenFiles(), options: options) { account, files, _, error in
//
////            self.oldInProgress = false
//            DispatchQueue.main.async {
//                NCActivityIndicator.shared.stop()
//                self.loadData()
////                self.collectionView.reloadData()
//            }

            if error == .success && account == self.appDelegate?.account {
                if !files.isEmpty {
                    NCManageDatabase.shared.convertFilesToMetadatas(files, useMetadataFolder: false) { _, _, metadatas in
                        let predicateDate = NSPredicate(format: "date > %@ AND date < %@", greaterDate as NSDate, lessDate as NSDate)
                        let predicateResult = NSCompoundPredicate(andPredicateWithSubpredicates: [predicateDate, self.predicateDefault!])
                        let metadatasResult = NCManageDatabase.shared.getMetadatas(predicate: predicateResult)
                        let metadatasChanged = NCManageDatabase.shared.updateMetadatas(metadatas, metadatasResult: metadatasResult, addCompareLivePhoto: false)
                        if metadatasChanged.metadatasUpdate.isEmpty {
                            self.researchOldMedia(value: value, limit: limit, withElseReloadDataSource: true)
                        } else {
                            self.loadData()
                        }
                    }
                } else {
                    self.researchOldMedia(value: value, limit: limit, withElseReloadDataSource: false)
                }
            } else if error != .success {
                NextcloudKit.shared.nkCommonInstance.writeLog("[INFO] Media search old media error code \(error.errorCode) " + error.errorDescription)
            }
        }
    }

    private func researchOldMedia(value: Int, limit: Int, withElseReloadDataSource: Bool) {

        if value == -30 {
            searchOldMedia(value: -90)
        } else if value == -90 {
            searchOldMedia(value: -180)
        } else if value == -180 {
            searchOldMedia(value: -999)
        } else if value == -999 && limit > 0 {
            searchOldMedia(value: -999, limit: 0)
        } else {
            if withElseReloadDataSource {
                loadData()
            }
        }
    }

//    @objc func searchNewMediaTimer() {
//        self.searchNewMedia()
//    }
//
    @objc func searchNewMedia() {

//        if newInProgress { return } else {
//            newInProgress = true
//            mediaCommandView?.activityIndicator.startAnimating()
//        }

        var limit: Int = 1000
        guard var lessDate = Calendar.current.date(byAdding: .second, value: 1, to: Date()) else { return }
        guard var greaterDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else { return }

//        if let visibleCells = self.collectionView?.indexPathsForVisibleItems.sorted(by: { $0.row < $1.row }).compactMap({ self.collectionView?.cellForItem(at: $0) }) {
//            if let cell = visibleCells.first as? NCGridMediaCell {
//                if cell.date != nil {
//                    if cell.date != self.metadatas.first?.date as Date? {
//                        lessDate = Calendar.current.date(byAdding: .second, value: 1, to: cell.date!)!
//                        limit = 0
//                    }
//                }
//            }
//            if let cell = visibleCells.last as? NCGridMediaCell {
//                if cell.date != nil {
//                    greaterDate = Calendar.current.date(byAdding: .second, value: -1, to: cell.date!)!
//                }
//            }
//        }

//        reloadDataThenPerform {

            let options = NKRequestOptions(timeout: 300, queue: NextcloudKit.shared.nkCommonInstance.backgroundQueue)

            NextcloudKit.shared.searchMedia(path: self.mediaPath, lessDate: lessDate, greaterDate: greaterDate, elementDate: "d:getlastmodified/", limit: limit, showHiddenFiles: CCUtility.getShowHiddenFiles(), options: options) { account, files, data, error in

//                self.newInProgress = false
//                DispatchQueue.main.async {
//                    self.mediaCommandView?.activityIndicator.stopAnimating()
//                }

                if error == .success && account == self.appDelegate?.account && files.count > 0 {
                    NCManageDatabase.shared.convertFilesToMetadatas(files, useMetadataFolder: false) { _, _, metadatas in
                        let predicate = NSPredicate(format: "date > %@ AND date < %@", greaterDate as NSDate, lessDate as NSDate)
                        let predicateResult = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, self.predicate!])
                        let metadatasResult = NCManageDatabase.shared.getMetadatas(predicate: predicateResult)
                        let updateMetadatas = NCManageDatabase.shared.updateMetadatas(metadatas, metadatasResult: metadatasResult, addCompareLivePhoto: false)
                        if updateMetadatas.metadatasUpdate.count > 0 || updateMetadatas.metadatasDelete.count > 0 {
                            self.loadData()
                        }
                    }
                } else if error == .success && files.count == 0 && self.metadatas.count == 0 {
                    self.searchOldMedia()
                } else if error != .success {
                    NextcloudKit.shared.nkCommonInstance.writeLog("[ERROR] Media search new media error code \(error.errorCode) " + error.errorDescription)
                }
            }
//        }
    }
}
