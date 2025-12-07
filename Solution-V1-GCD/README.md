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


> [!WARNING]
> Work In Progress. This document will be extended further explaining more fixes and enhancement made.
