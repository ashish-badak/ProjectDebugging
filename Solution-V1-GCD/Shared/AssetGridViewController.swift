import UIKit
import Photos
import PhotosUI

private extension UICollectionView {
    func indexPathsForElements(in rect: CGRect) -> [IndexPath] {
        let allLayoutAttributes = collectionViewLayout.layoutAttributesForElements(in: rect)!
        return allLayoutAttributes.map { $0.indexPath }
    }
}

typealias AssetGridViewControllerHandler = ([UIImage]) -> Void
let AssetGridViewMaximumPreloadSize = 1...200

class AssetDataSource : NSObject {

    let imageManager = PHCachingImageManager()
    var fetchResult: PHFetchResult<PHAsset>!
    var assetCollection: PHAssetCollection!
    
    /// - NOTE: Ideally we should adopt delegate pattern with protocols to avoid adding concrete type
    ///         As this statement is forming parent - child relationship between `AssetGridViewController` and `AssetDataSource`;
    ///         We should mark these as weak.
    weak var controller: AssetGridViewController!

    init(fetchResult: PHFetchResult<PHAsset>? = nil, controller: AssetGridViewController, assetCollection: PHAssetCollection? = nil) {
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
        let addedAssets = addedRects
            .flatMap { rect in controller.collectionView!.indexPathsForElements(in: rect) }
            .map { indexPath in asset(at: indexPath.item) }
        let removedAssets = removedRects
            .flatMap { rect in controller.collectionView!.indexPathsForElements(in: rect) }
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
        DispatchQueue.main.sync {
            // Hang on to the new fetch result.
            fetchResult = changes.fetchResultAfterChanges
            // If we have incremental changes, animate them in the collection view.
            guard let collectionView = self.controller.collectionView else { fatalError() }
            if changes.hasIncrementalChanges {
                // Handle removals, insertions, and moves in a batch update.
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
            controller.resetCachedAssets()
        }
    }
}



class AssetGridViewController: UICollectionViewController {

    var availableWidth: CGFloat = 0
    var preload: CADisplayLink?
    var completionHandler: AssetGridViewControllerHandler?
    lazy var dataSource: AssetDataSource! = {
        AssetDataSource(controller: self)
    }()

    @IBOutlet var addButtonItem: UIBarButtonItem!
    @IBOutlet weak var collectionViewFlowLayout: UICollectionViewFlowLayout!

    fileprivate var thumbnailSize: CGSize!
    fileprivate var previousPreheatRect = CGRect.zero
    
    // MARK: UIViewController / Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        PHPhotoLibrary.shared().unregisterChangeObserver(dataSource)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        resetCachedAssets()
        dataSource = nil
        preload?.invalidate()
        preload = nil
    }

    deinit {
        print("Successfully deinit")
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let width = view.bounds.inset(by: view.safeAreaInsets).width
        // Adjust the item size if the available width has changed.
        if availableWidth != width {
            availableWidth = width
            let columnCount = (availableWidth / 80).rounded(.towardZero)
            let itemLength = (availableWidth - columnCount - 1) / columnCount
            collectionViewFlowLayout.itemSize = CGSize(width: itemLength, height: itemLength)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Reaching this point without a segue means that this AssetGridViewController
        // became visible at app launch. As such, match the behavior of the segue from
        // the default "All Photos" view.
        if dataSource == nil {
            let allPhotosOptions = PHFetchOptions()
            allPhotosOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let fetchResult = PHAsset.fetchAssets(with: allPhotosOptions)
            dataSource = .init(fetchResult: fetchResult, controller: self)
        }

        PHPhotoLibrary.shared().register(dataSource)

        // Verify that all the user saw all the pictures

        /// - NOTE: `completionHandler` is unused so it can be removed if this is was production ready application.
        ///         Keeping it here to demonstrate change made to fix the issue
        completionHandler = { [weak self] images in
            /// - NOTE: Capturing self as `weak` to avoid reference count increase and cyclic reference
            if self?.dataSource.fetchResult.count == images.count {
                print("Successfully seen all assets")
            }
        }

        // Determine the size of the thumbnails to request from the PHCachingImageManager.
        let scale = UIScreen.main.scale
        let cellSize = collectionViewFlowLayout.itemSize
        thumbnailSize = CGSize(width: cellSize.width * scale, height: cellSize.height * scale)
        
        // Add a button to the navigation bar if the asset collection supports adding content.
        if dataSource.assetCollection == nil || dataSource.assetCollection.canPerform(.addContent) {
            navigationItem.rightBarButtonItem = addButtonItem
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }
    
    fileprivate func preloadIfNeeded() {
        updateCachedAssets()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        preloadIfNeeded()

        preload = CADisplayLink(target: self, selector: #selector(iterateThroughVisibleRect))
        preload?.add(to: .current, forMode: RunLoop.Mode.default)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let destination = segue.destination as? AssetViewController else { fatalError("Unexpected view controller for segue") }
        guard let collectionViewCell = sender as? UICollectionViewCell else { fatalError("Unexpected sender for segue") }
        
        let indexPath = collectionView.indexPath(for: collectionViewCell)!
        destination.asset = dataSource.asset(at: indexPath.item)
        destination.assetCollection = dataSource.assetCollection
    }
    
    // MARK: UICollectionView
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return dataSource.count
    }
    /// - Tag: PopulateCell
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let asset = dataSource.asset(at: indexPath.item)
        // Dequeue a GridViewCell.
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "GridViewCell", for: indexPath) as? GridViewCell
            else { fatalError("Unexpected cell in collection view") }
        
        // Add a badge to the cell if the PHAsset represents a Live Photo.
        if asset.mediaSubtypes.contains(.photoLive) {
            cell.livePhotoBadgeImage = PHLivePhotoView.livePhotoBadgeImage(options: .overContent)
        }
        
        // Request an image for the asset from the PHCachingImageManager.
        cell.representedAssetIdentifier = asset.localIdentifier
        dataSource.requestImage(at: indexPath.item, targetSize: thumbnailSize, contentMode: .aspectFill) { image, _ in
            // UIKit may have recycled this cell by the handler's activation time.
            // Set the cell's thumbnail image only if it's still showing the same asset.
            if cell.representedAssetIdentifier == asset.localIdentifier {
                cell.configure(image: image)
            }
        }
        return cell
    }
    
    // MARK: UIScrollView

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateCachedAssets()
    }
    
    // MARK: Asset Caching
    
    fileprivate func resetCachedAssets() {
        dataSource.resetCache()
        previousPreheatRect = .zero
    }
    
    /// - Tag: UpdateAssets
    fileprivate func updateCachedAssets() {
        // Update only if the view is visible.
        guard isViewLoaded && view.window != nil else { return }
        
        // The window you prepare ahead of time is twice the height of the visible rect.
        let visibleRect = CGRect(origin: collectionView!.contentOffset, size: collectionView!.bounds.size)
        let preheatRect = visibleRect.insetBy(dx: 0, dy: -0.5 * visibleRect.height)

        // Update only if the visible area is significantly different from the last preheated area.
        let delta = abs(preheatRect.midY - previousPreheatRect.midY)
        guard delta > view.bounds.height / 3 else { return }
        
        // Compute the assets to start and stop caching.
        let (addedRects, removedRects) = differencesBetweenRects(previousPreheatRect, preheatRect)
        dataSource.updateCache(addedRects: addedRects, removedRects: removedRects, targetSize: thumbnailSize, contentMode: .aspectFill)
        // Store the computed rectangle for future comparison.
        previousPreheatRect = preheatRect
    }

    @objc fileprivate func iterateThroughVisibleRect() {
        for x in AssetGridViewMaximumPreloadSize {
            for y in AssetGridViewMaximumPreloadSize {
                self.preloadCache(contentOffset: .init(x: x, y: y))
            }
        }
    }
    
    fileprivate func differencesBetweenRects(_ old: CGRect, _ new: CGRect) -> (added: [CGRect], removed: [CGRect]) {
        if old.intersects(new) {
            var added = [CGRect]()
            if new.maxY > old.maxY {
                added += [CGRect(x: new.origin.x, y: old.maxY,
                                 width: new.width, height: new.maxY - old.maxY)]
            }
            if old.minY > new.minY {
                added += [CGRect(x: new.origin.x, y: new.minY,
                                 width: new.width, height: old.minY - new.minY)]
            }
            var removed = [CGRect]()
            if new.maxY < old.maxY {
                removed += [CGRect(x: new.origin.x, y: new.maxY,
                                   width: new.width, height: old.maxY - new.maxY)]
            }
            if old.minY < new.minY {
                removed += [CGRect(x: new.origin.x, y: old.minY,
                                   width: new.width, height: new.minY - old.minY)]
            }
            return (added, removed)
        } else {
            return ([new], [old])
        }
    }

    func generateImage() -> UIImage {

        let BATCH_SIZE = 100
        var colors = [UIColor]()
        let size = (arc4random_uniform(2) == 0) ? CGSize(width: 400, height: 300) : CGSize(width: 300, height: 400)

        let width: Int = Int(size.width)
        let height: Int = Int(size.height)

        let group = DispatchGroup()
        (0..<width).forEach { _ in
            for y in stride(from: 0, to: height, by: BATCH_SIZE) {
                group.enter()
                DispatchQueue.global().async {
                    let upperBound = y+BATCH_SIZE
                    (y..<upperBound).forEach { _ in
                        let newColor = UIColor(hue: CGFloat(arc4random_uniform(100)) / 100, saturation: 1, brightness: 1, alpha: 1)
                        colors.append(newColor)
                    }
                }
            }
            group.leave()
        }

        group.wait()

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            (0..<width).forEach { x in
                (0..<height).forEach { y in
                    let index = width * y + x
                    let newColor = colors[index]
                    newColor.setFill()
                    let newBounds = CGRect(x: x, y: y, width: 1, height: 1)
                    context.fill(newBounds)
                }
            }
        }
        return image
    }
    
    // MARK: UI Actions
    /// - Tag: AddAsset
    @IBAction func addAsset(_ sender: AnyObject?) {
        // Create a dummy image of a random solid color and random orientation.
        // Add the asset to the photo library.
        let image = generateImage()
        PHPhotoLibrary.shared().performChanges({
            let creationRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
            if let assetCollection = self.dataSource.assetCollection {
                let addAssetRequest = PHAssetCollectionChangeRequest(for: assetCollection)
                addAssetRequest?.addAssets([creationRequest.placeholderForCreatedAsset!] as NSArray)
            }
        }, completionHandler: {success, error in
            if !success { print("Error creating the asset: \(String(describing: error))") }
        })
    }


    @objc func preloadCache(contentOffset: CGPoint) {
        let nextVisibleRect = CGRect(origin: contentOffset, size: CGSize(width: 200, height: 200))
        let currentVisibleRect = CGRect(origin: self.collectionView.contentOffset, size: self.collectionView.contentSize)

        if currentVisibleRect.intersects(nextVisibleRect) {
            DispatchQueue.main.async {
                self.updateCachedAssets()
            }
        }
    }
}
