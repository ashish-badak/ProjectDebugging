import UIKit
import Photos
import PhotosUI
import CoreGraphics

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
        DispatchQueue.main.sync {
            // Hang on to the new fetch result.
            fetchResult = changes.fetchResultAfterChanges
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
            controller?.resetCachedAssets()
        }
    }
}



class AssetGridViewController: UICollectionViewController {

    var availableWidth: CGFloat = 0
    var completionHandler: AssetGridViewControllerHandler?
    
    /// - NOTE:
    ///     - Earlier we we were creating `dataSource` in `viewWillAppear`; which is invoked everytime view controller appears or (re-appears) on screen
    ///     - As we were resetting the data source object everytime; we were not able to perform batched updates when:
    ///         1. Asset was deleted from `AssetViewController`
    ///         2. Asset was edited - no immediate update on `AssetGridViewController`
    ///     - It was ulitmately causing crash inside `AssetDataSource.photoLibraryDidChange(:)` since new data source object meant mismatch in fetch request changes
    ///     - This resulted us giving back empty `changes.removedIndexes` and other updates were also missing.
    ///
    ///     - Ideally `dataSource` can be injected as a dependency into the controller in production level code with proper dependency injection system in place
    ///     - And more code restructuring can be done as per needed to make overall code more modular and unit testable.
    lazy var dataSource: AssetDataSource = AssetDataSource()

    @IBOutlet var addButtonItem: UIBarButtonItem!
    @IBOutlet weak var collectionViewFlowLayout: UICollectionViewFlowLayout!

    fileprivate var thumbnailSize: CGSize!
    fileprivate var previousPreheatRect = CGRect.zero
    
    // MARK: UIViewController / Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let allPhotosOptions = PHFetchOptions()
        allPhotosOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let fetchResult = PHAsset.fetchAssets(with: allPhotosOptions)
        
        /// - NOTE:
        ///     - Since we are creating data source only once now; passing properties just like we configure delegate objects in deelgate pattern
        ///     - Ideally we would adopt delegate pattern along with protocols instead of having controller instance directly added to data source
        dataSource.fetchResult = fetchResult
        dataSource.controller = self
        
        /// - NOTE: Since we are creating data source only once we register it only once as well
        PHPhotoLibrary.shared().register(dataSource)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        resetCachedAssets()
    }

    deinit {
        /// - NOTE: Since we are creating data source only once we deregister it only once as well
        PHPhotoLibrary.shared().unregisterChangeObserver(dataSource)
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

        /// - NOTE: This code was making `iterateThroughVisibleRect` to be executed every frame which is not needed
        ///         This results in blocking main thread and increasing CPU load.
        ///         Which in turn caused severe UI hangs
        ///         We detected this with time profiler and resolved it.
        ///
        /// - Culprit code:
        ///         `preload = CADisplayLink(target: self, selector: #selector(iterateThroughVisibleRect))`
        ///         `preload?.add(to: .current, forMode: RunLoop.Mode.default)`
        ///
        ///         `iterateThroughVisibleRect` was also doing heavy computing work which was not necessary
        ///
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

    func generateImage(completion: @escaping (UIImage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let (width, height): (Int, Int) = arc4random_uniform(2) == 0 ? (400, 300): (300, 400)
            let colorCount = 100
            var colors: [UInt32] = Array(repeating: 0, count: colorCount)
            
            DispatchQueue.concurrentPerform(iterations: colorCount) { iteration in
                colors[iteration] = UIColor(
                    hue: CGFloat(iteration) / CGFloat(colorCount),
                    saturation: 1,
                    brightness: 1,
                    alpha: 1
                ).argb32
            }
            
            /// - Reference:
            /// Creating a Bitmap Graphics Context: https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/drawingwithquartz2d/dq_context/dq_context.html#//apple_ref/doc/uid/TP30001066-CH203-CJBHBFFE
            ///
            /// Bitmap Images:  https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/drawingwithquartz2d/dq_images/dq_images.html
            ///
            let pixelsCount = width * height
            let bitmapData = UnsafeMutablePointer<UInt32>.allocate(capacity: pixelsCount)
            defer { bitmapData.deallocate() }
            
            for i in 0..<pixelsCount {
                bitmapData[i] = colors[Int(arc4random_uniform(UInt32(colorCount)))]
            }
                        
            let context = CGContext(
                data: bitmapData,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            )
            
            if let cgImage = context?.makeImage() {
                completion(UIImage(cgImage: cgImage))
            } else {
                completion(nil)
            }
        }
    }
    
    // MARK: UI Actions
    /// - Tag: AddAsset
    @IBAction func addAsset(_ sender: AnyObject?) {
        // Create a dummy image of a random solid color and random orientation.
        // Add the asset to the photo library.
        generateImage { [weak self] image in
            guard let image else { return }
            
            PHPhotoLibrary.shared().performChanges({
                let creationRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
                if let assetCollection = self?.dataSource.assetCollection {
                    let addAssetRequest = PHAssetCollectionChangeRequest(for: assetCollection)
                    addAssetRequest?.addAssets([creationRequest.placeholderForCreatedAsset!] as NSArray)
                }
            }, completionHandler: {success, error in
                if !success { print("Error creating the asset: \(String(describing: error))") }
            })
        }
    }
}

extension UIColor {
    /// Little Endian compliant "ARGB" color representation
    /// - References:
    ///     1. Color Spaces: https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/drawingwithquartz2d/dq_color/dq_color.html
    ///
    var argb32: UInt32 {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)

        let r8 = UInt32(r * 255)
        let g8 = UInt32(g * 255)
        let b8 = UInt32(b * 255)
        let a8 = UInt32(a * 255)

        return (b8 << 24) | (g8 << 16) | (r8 << 8) | a8
    }
}
