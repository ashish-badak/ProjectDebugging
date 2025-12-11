import UIKit
import Photos
import PhotosUI
import CoreGraphics


typealias AssetGridViewControllerHandler = ([UIImage]) -> Void
let AssetGridViewMaximumPreloadSize = 1...200


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

    @IBOutlet weak var addButtonItem: UIBarButtonItem!
    @IBOutlet weak var collectionViewFlowLayout: UICollectionViewFlowLayout!

    fileprivate var thumbnailSize: CGSize!
    fileprivate var previousPreheatRect = CGRect.zero
    
    // MARK: UIViewController / Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if dataSource.fetchResult == nil {
            /// We are passing fetchResult from `MasterViewController`; so preserving and adopting original check here
            let allPhotosOptions = PHFetchOptions()
            allPhotosOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let fetchResult = PHAsset.fetchAssets(with: allPhotosOptions)
            
            dataSource.fetchResult = fetchResult
        }
        
        /// - NOTE:
        ///     - Since we are creating data source only once now; passing properties just like we configure delegate objects in deelgate pattern
        ///     - Ideally we would adopt delegate pattern along with protocols instead of having controller instance directly added to data source
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
            if self?.dataSource.count == images.count {
                print("Successfully seen all assets")
            }
        }

        // Determine the size of the thumbnails to request from the PHCachingImageManager.
        let scale = UIScreen.main.scale
        let cellSize = collectionViewFlowLayout.itemSize
        thumbnailSize = CGSize(width: cellSize.width * scale, height: cellSize.height * scale)
        
        // Add a button to the navigation bar if the asset collection supports adding content.
        /// - NOTE: Earlier `add button` was added even when`dataSource.assetCollection == nil`
        ///         So adding default falback as `true`
        if dataSource.assetCollection?.canPerform(.addContent) ?? true {
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
        // Dequeue a GridViewCell.
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "GridViewCell", for: indexPath) as? GridViewCell
            else { fatalError("Unexpected cell in collection view") }
        
        guard let asset = dataSource.asset(at: indexPath.item) else {
            return cell
        }

        
        /// - NOTE: Ideally we should create a view modal outside of collection view data source methods.
        ///         Ideally when data is fetched. We can map it to presentable format and store collection of it.
        ///         So that we dont need to recreate the state and configurations again and again here.
        
        // Request an image for the asset from the PHCachingImageManager.
        cell.representedAssetIdentifier = asset.localIdentifier
        dataSource.requestImage(for: asset, targetSize: thumbnailSize, contentMode: .aspectFill) { image, _ in
            // UIKit may have recycled this cell by the handler's activation time.
            // Set the cell's thumbnail image only if it's still showing the same asset.
            if cell.representedAssetIdentifier == asset.localIdentifier {
                cell.configure(image: image, isLiveImage: asset.mediaSubtypes.contains(.photoLive))
            }
        }
        return cell
    }
    
    // MARK: UIScrollView

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateCachedAssets()
    }
    
    // MARK: Asset Caching
    
    func resetCachedAssets() {
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
