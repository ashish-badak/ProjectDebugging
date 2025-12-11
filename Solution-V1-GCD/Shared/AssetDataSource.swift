//
//  AssetDataSource.swift
//  Browse iOS
//
//  Created by Ashish Badak on 11/12/25.
//  Copyright © 2025 Apple. All rights reserved.
//

import UIKit
import Photos

private extension UICollectionView {
    func indexPathsForElements(in rect: CGRect) -> [IndexPath] {
        let allLayoutAttributes = collectionViewLayout.layoutAttributesForElements(in: rect)!
        return allLayoutAttributes.map { $0.indexPath }
    }
}

class AssetDataSource : NSObject {

    let imageManager = PHCachingImageManager()
    var fetchResult: PHFetchResult<PHAsset>!
    var assetCollection: PHAssetCollection!
    
    /// - NOTE: Ideally we should adopt delegate pattern with protocols to avoid adding concrete type
    ///         As this statement is forming parent - child relationship between `AssetGridViewController` and `AssetDataSource`;
    ///         We should mark these as weak.
    ///
    ///         Similarly, we can avoid force unwraps across the given project to avoid accidental crashes. More graceful handling can be implemented with:
    ///         1. `guard` statements
    ///         2. `if let` statements
    ///         3. Fallbacks with default values wherever applicable
    ///         4. Error reporting / logging
    ///         5. Or crash if there is no recoverable state possible (worst and last option to avail)
    weak var controller: AssetGridViewController?

    init(
        fetchResult: PHFetchResult<PHAsset>? = nil,
        controller: AssetGridViewController? = nil,
        assetCollection: PHAssetCollection? = nil
    ) {
        self.fetchResult = fetchResult
        self.controller = controller
        self.assetCollection = assetCollection
    }

    var count: Int {
        get {
            fetchResult.count
        }
    }

    func asset(at index: Int) -> PHAsset {
        return fetchResult.object(at: index)
    }

    func requestImage(at: Int, targetSize: CGSize, contentMode: PHImageContentMode, resultHandler: @escaping (UIImage?, [AnyHashable:Any]?) -> Void) {
        imageManager.requestImage(for: asset(at: at), targetSize: targetSize, contentMode: contentMode, options: nil, resultHandler: resultHandler)
    }

    func resetCache() {
        imageManager.stopCachingImagesForAllAssets()
    }

    func updateCache(addedRects: [CGRect], removedRects: [CGRect], targetSize: CGSize, contentMode: PHImageContentMode) {
        /// - NOTE: Since we have made contoller weak and optional (earlier we force unwrapped it); we need a guard statment to safely unwrap it
        guard let collectionView = controller?.collectionView else { return }
        let addedAssets = addedRects
            .flatMap { rect in collectionView.indexPathsForElements(in: rect) }
            .map { indexPath in asset(at: indexPath.item) }
        let removedAssets = removedRects
            .flatMap { rect in collectionView.indexPathsForElements(in: rect) }
            .map { indexPath in asset(at: indexPath.item) }

        // Update the assets the PHCachingImageManager is caching.
        imageManager.startCachingImages(for: addedAssets,
                                        targetSize: targetSize, contentMode: contentMode, options: nil)
        imageManager.stopCachingImages(for: removedAssets,
                                       targetSize: targetSize, contentMode: contentMode, options: nil)
    }
}

// MARK: PHPhotoLibraryChangeObserver
extension AssetDataSource: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {

        guard let changes = changeInstance.changeDetails(for: fetchResult)
        else { return }

        // Change notifications may originate from a background queue.
        // As such, re-dispatch execution to the main queue before acting
        // on the change, so you can update the UI.
        DispatchQueue.main.async {
            // Hang on to the new fetch result.
            self.fetchResult = changes.fetchResultAfterChanges
            // If we have incremental changes, animate them in the collection view.
            guard let collectionView = self.controller?.collectionView else { fatalError() }
            if changes.hasIncrementalChanges {
                // Handle removals, insertions, and moves in a batch update.
                
                /// - NOTE: Earlier `collectionView.performBatchUpdates` was not working to reflect updates happened externally;
                ///         As we were resetting `dataSource` object inside controller on view appearance / dissappearance.
                ///         It is fixed by creating `dataSource` only once once controller loads.
                collectionView.performBatchUpdates({
                    if let removed = changes.removedIndexes, !removed.isEmpty {
                        collectionView.deleteItems(at: removed.map({ IndexPath(item: $0, section: 0) }))
                    }
                    if let inserted = changes.insertedIndexes, !inserted.isEmpty {
                        collectionView.insertItems(at: inserted.map({ IndexPath(item: $0, section: 0) }))
                    }
                    changes.enumerateMoves { fromIndex, toIndex in
                        collectionView.moveItem(at: IndexPath(item: fromIndex, section: 0),
                                                to: IndexPath(item: toIndex, section: 0))
                    }
                })
                // We are reloading items after the batch update since `PHFetchResultChangeDetails.changedIndexes` refers to
                // items in the *after* state and not the *before* state as expected by `performBatchUpdates(_:completion:)`.
                if let changed = changes.changedIndexes, !changed.isEmpty {
                    collectionView.reloadItems(at: changed.map({ IndexPath(item: $0, section: 0) }))
                }
            } else {
                // Reload the collection view if incremental changes are not available.
                collectionView.reloadData()
            }
            self.controller?.resetCachedAssets()
        }
    }
}
