# Debugging Solution

I have tried to approach and solve single fix per commit to showcase step by step approach. For details commit history can be checked.

> [!NOTE]
> I have tried to address issues from `AssetGridViewController` mostly and Then played around `AssetViewController`.
> Focusing on performance, crashes, memory footprints, and critical functionalities

Here, I am listing some issues with original code and fixes made.


## 1. Crash on app launch
### Issue:
1. The pointer referenced a hard-coded memory address (0x42), which does not contain a valid PHFetchResult.
2. Dereferencing such a pointer results in undefined behavior.
3. Swift memory safety gets bypassed entirely with this.
4. Also, the pointer served no valid purpose as it was unused.
#### Fix:
1. This was fixed by deleteting unwanted and wrong pointer usage code
2. [Check Commit](https://github.com/ashish-badak/ProjectDebugging/commit/47edaa3394f81bc9cdff9acae056534c8b4f4436)

## 2. Stack overflow crash
### Issue:
1. Inside `AssetGridViewController` two functions were calling each others in cycles causing stack overflow.
2. This resulted in infinite loop and crashing the application
#### Fix:
1. This was fixed by removing call to `preloadIfNeeded()` from `updateCachedAssets()`.
2. [Check Commit](https://github.com/ashish-badak/ProjectDebugging/commit/7ec88777507a06cce1e863e75e812afc8fea48d9)

## 3. Memory Leak
### Issue:
1. `AssetGridViewController` strongly accessed `AssetDataSource`.
2. `AssetGridViewController` also holds a closure called `completionHandler` which held strong reference to `AssetDataSource`.
3. `AssetDataSource` also held the strong reference to `AssetGridViewController`.
4. This resulted in strong reference cycle and objects in act were never released.
### Fix:
1. We made controller reference inside data source as `weak`.
2. Also captured controller as `weak` reference inside `completionHandler` to access data source.
3. This resolved reference cycle.
4. [Check Commit](https://github.com/ashish-badak/ProjectDebugging/commit/b7d8d17e2714d3d2fdfa01e9c4ea0dabb61de52f)

## 4 & 5. Data Race and Deadlock
### Issue:
1. Inside `AssetGridViewController.generateImage()` 400*300 (120,000) colors were generated asyncronously.
2. Each loop which was executed concurrently on background queue was trying to access colors array causing thread-unsafe mutation (data race)
3. This results in crash due to data race.
4. Also code was manually batching and dispatching work on global background queue.
5. Dispatch group used to wait on results was also had mismatched `enter()` and `leave()` calls; which caused deadlock.
### Fix:
1. As code was only slecting hue values in the range of 0..<100; we do not need to create 120,000 colors; instead generate only 100 colors.
2. So declared array of colors prefilled with `.clear` as default color. This allows us to update to individual array elements without worrying about thread safety in this context.
3. Used `DispatchQueue.concurrentPerform{}` to execute color generation concurrently without manually managing batching and dispatching of the work.
4. As this concurrent perform is sync operation on calling thread moved entire image generation function to background queue.
5. So updated this function to call completion handler instead of directly returning the result.
6. [Check Commit](https://github.com/ashish-badak/ProjectDebugging/commit/f1fbd6486a895de9143f7737b4eafbfe65889d31)


## 6. Scroll Performance (Updated in point 16)
### Issue:
1. Inside `AssetGridViewController.viewDidAppear()`, original code was trynig to invoke `CADisplayLink`.
2. This acts as a timer and invoked per frame; resulting in a call to `iterateThroughVisibleRect()` per frame.
3. `iterateThroughVisibleRect()` function was doing heavy computation to preload cache inside of a loop.
4. This entire code was unnecessary as we dont need to preload cache every frame.
5. All of this was happening on main thread.
6. Starvation - This caused high CPU load and resulted poor scroll performance (or would have affected any other work if it was there)
### Fix:
1. Removed `CADisplayLink` entirely, freeing up main thread from unnecessary heavy computation per frame.
2. Resulted in CPU load reduction and smooth scrolling.
3. [Check Commit](https://github.com/ashish-badak/ProjectDebugging/commit/05555118839c1b4cab470bdf7fc849b0708c46ee)

## 7. Color generation optimisation
### Issue:
1. Inside `AssetGridViewController.generateImage()` 400*300 (120,000) colors were generated asyncronously.
2. But the color hue was ranging from 0..<100. So ideally only 100 unique colors were generated.
3. This was taking roughly ~60ms.  
### Fix:
1. So decided to generate only 100 unique colors.
2. [Check Commit](https://github.com/ashish-badak/ProjectDebugging/commit/946497e8592595f7a19a088ad78528be158af5be)

## 8. Image generation optimisation
### Issue:
1. While generating image with `UIGraphicsImageRenderer`; code was trying to create a rect for each pixel and fill it with color.
2. This resulted in 120,000 calls to update context state and taking more than ~300ms for image generation.  
### Fix:
1. Decided to use bitmap image generation.
2. Created memory buffer for image size.
3. Then filled it with `UInt32` color representaion on direct memory buffer.
4. Then used this bitmap buffer data to create CGContext in one go.
5. Then mapped it to CGImage and then UIImage as needed.
6. Achieving image generation in ~30ms.
7. [Check Commit](https://github.com/ashish-badak/ProjectDebugging/commit/3445618e4c9feb1815ed6910e84c24b15ac3b379)
### References:
1. [Creating a Bitmap Graphics Context](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/drawingwithquartz2d/dq_context/dq_context.html#//apple_ref/doc/uid/TP30001066-CH203-CJBHBFFE)
2. [Bitmap Images](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/drawingwithquartz2d/dq_images/dq_images.html)

## 9. Navigation toolbar appearance
### Issue:
1. On `AssetViewController`, navigation toolbar was shown with asset actions.
2. When coming back from this screen to grid view of assets, this toolbar was not hidden which was shown on frid view as well.  
### Fix:
1. Added a statment to hide navigation toolbar inside `AssetViewController.viewWillDisappear()`.
2. [Check Commit](https://github.com/ashish-badak/ProjectDebugging/commit/63c86815f468e4406ce3a658bd14cdd18e13c3cd)

## 10. Allowing album creation to be cancelled (Optional Enhancement)
### Issue:
1. On `MasterViewController` screen, when user taps on add album, there wsaa no way to cancel album creation.
2. User either had to create album or kill the app.
### Fix:
1. Added an option to cancel album creation with new cancel alert action.
2. [Check Commit](https://github.com/ashish-badak/ProjectDebugging/commit/e3a503a37c0e166c6e3b7b9c144b960b0f025069)

## 11. Favorite State Update for Asset
### Issue:
1. `AssetViewController` has a option to mark asset as favorite. It was not updating the state when tapped.
2. As completion closure was for asset update request was executing first and then asset was updated; call to update state from completion closure took no effect.
### Fix:
1. `AssetViewController` receive observation callback when asset is changed.
2. Added a call to update favorite button title to reflect favorite button state properly.
3. [Check Commit](https://github.com/ashish-badak/ProjectDebugging/commit/12f3ce4bcd23a5c7c46999b71f2e3e4d6d883c7b)

## 12 and 13. Crash on asset deletion and Filter sync on grid view
### Issue:
1. Inside `AssetViewController`, there is option to delete asset; when it is used to delete asset app was crashing.
2. This crash was happening when `AssetGridViewController`'s collection view was performing batched updates inside `AssetDataSource.photoLibraryDidChange()`
3. Root cause was reinstantiation of data source inside view appearance and making it nil on view disappearance of `AssetGridViewController`
4. As it was giving new `FetchRequest` instance to collection view updates.
5. Also, whenever we add filter to images from `AssetViewController`; grid view was not syncing to reflect those updates.
### Fix:
1. Decided to instantiate data source only once and configured it in `AssetGridViewController.viewDidLoad()`; just like a delegate is configured.
2. This also solved asset filter updates sync issue; and now grid view reflects updates directly.
3. Also made some adjustments to make this change work.
4. [Check Commit](https://github.com/ashish-badak/ProjectDebugging/commit/1d197f4ef35aa15925af5cd8439083c075f85c77)

## 14. Crash on external asset deletion 
### Issue:
1. When asset was deleted from externally from original source and our app was showing that asset; it resulted in crash.
### Fix:
1. `AssetViewController` receive observation callback when asset is changed.
2. Added a check if received changed asset is nil or not.
3. If it not nil means it is deleted so added a statement to pop back that screen to grid view.
4. [Check Commit](https://github.com/ashish-badak/ProjectDebugging/commit/292ee1bc133f004e6e9c7ebb3435ba3f255bc7c6)


## 15. Crash on video play
### Issue:
1. When asset was a video and tried to play; it resulted in crash.
2. This was happening as `DispatchQueue.main.sync` was used in the code which was called on main queue.
3. This resulted on thread waiting deadlock and crashed.
### Fix:
1. Updated that call to be as `DispatchQueue.main.async`.
2. Also updated all other similar calls to async counterparts of the same.
3. [Check Commit](https://github.com/ashish-badak/ProjectDebugging/commit/a27c575d7e048ab0ff8930d0b3938027d2ccee1f)


## 15. Video was not playing second time
### Issue:
1. Video was not playing again on play button tap once it was already played.
2. This was happening as we were using same player and it was not resetted back to start of the video before playing again.
### Fix:
1. Added a call to seek the video to start when video is being tried to play again.
2. [Check Commit](https://github.com/ashish-badak/ProjectDebugging/commit/ab1a26da3662c7bae49f3398a8258ce0c9e5bf24)
> [!Note]
> Just added a play functionality. In actual scenarios, more graceful handling can be added for the real player with seek, pause, etc.

## 16. Scroll Performance
### Issue:
1. `GridViewCell` was configuring shadow inside configure(image:) function
2. This function is called every time `collectionView`'s `cellForRow` method is invoked.
3. This was causing scroll perfornce degradation. Confirmed this with Instruments and could see hangs while scrolling fast.
### Fix:
1. Moved shadow creation to `awakeFromNib()` - generating only once.
2. Also rasterised it so it increases performance.
3. Also made some adjustments to make shadow look more subtle.
4. [Check Commit](https://github.com/ashish-badak/ProjectDebugging/commit/a782c23f527a846e77e6a31746722d170c505646)

## 17. Live photo badge
### Issue:
1. Inside `collectionView`'s `cellForRow` method, new live image was assigned whenever live asset was loaded.
### Fix:
1. Declared a static variable with live phot badge inside `GridViewCell`.
2. Now, instead of making `liveBadgeImageView` nil and assigning it again; just toggling visibility.
4. [Check Commit](https://github.com/ashish-badak/ProjectDebugging/commit/483cc7c63b2081c80fe8374754f61457dbe39aeb)

## 18. Unused variable cleanup
1. Cleaned unused variable from cell view
2. [Check Commit](https://github.com/ashish-badak/ProjectDebugging/commit/1755947baef5da779f3391a412ebdf96314f9404)

## Other observations, and considerations:
1. Observed force-unwrappings across projects which can be addressed more gracefully with:
- `guard` / `if-let` statements
- Fallback / default values
- Error handling / Logging as required
- Crash only if program is in absolutely in unrecoverable state
2. Follow better coding patterns to add dependency injections, modularity, unit testability. Considering this was assignment around debugging did not address the coding structure.
3. Did not check `MasterViewController` for issues. Focused on grid and details view for this debugging assignment.
4. Ideally cell view models can be created whenever data is ready and passed into cell configuration as per requirement; this will help us to make heavy computations only once. This differs as per requirement though.
