# PiP 小窗比例與背景更新修復說明

> 日期：2026-08-29
> 涉及檔案：`PictureInPictureManager.swift`、`ParsecMetalRenderer.swift`、`ParsecGLKRenderer.swift`

---

## 一、PiP 小窗比例錯誤（4:3 而非 16:9）

### 問題
PiP 小窗的比例由餵給 `AVSampleBufferDisplayLayer` 的 CVPixelBuffer **尺寸**決定，
但 capture buffer 是在 setup 時用**裝置螢幕的 drawable 尺寸**建立的：

| 後端 | 建立尺寸 |
|---|---|
| OpenGL | `glkView.drawableWidth/Height`（iPad 常為 4:3） |
| Metal | `mtkView.drawableSize`（同上） |

所以小窗會變成螢幕比例（如 iPad 4:3），16:9 的影片內容反而被 letterbox 塞在裡面。

### 修法：擷取面對齊實際視訊尺寸
- `CaptureSurfaceProvider` 新增 `captureSize`，並讓 renderer 在知道視訊實際尺寸時
  呼叫 `PictureInPictureManager.updateVideoSize(width:height:)`，必要時以該尺寸
  **重建** pixel buffer / texture / FBO。
- **Metal**：`ParsecMetalRenderer.handleFrame` 每幀取得 `frame.width/height` 後同步尺寸。
- **OpenGL**：`ParsecGLKRenderer.drawIn` 透過 `getStatusEx` 的 `decoder.width/height`
  同步尺寸。
- `startPiP()` 啟動前先以目前視訊尺寸重建擷取面，小窗第一次出現就是正確比例。
- `GLCaptureSurfaceProvider.setup()` 順帶修正：綁定/建立 FBO 時確保在正確的 GL
  context 上，並在結束時還原原本綁定的 FBO，避免 resize 發生在 draw 中途污染
  render loop。

---

## 二、退到背景 PiP 畫面凍結

### 問題
capture buffer 的內容是由 **display link 驅動的 render loop** 填的
（`MTKView.draw(in:)` / `GLKView drawIn`）。App 背景化後 **display link 被系統停止**，
buffer 不再有新內容；既有的 GCD frame pump 只是重複把**同一個沒更新的舊 buffer**
塞給 layer，所以小窗凍結在最後一幀。

### 修法：背景時由 pump 自行拉幀＋繪製
- `PictureInPictureManager` 新增 `captureSourceRenderer` closure，由 renderer 註冊。
- `renderFrame()` 偵測 `applicationState != .active` 時，先呼叫該 closure 把最新幀
  畫進擷取面，再 enqueue 給 `AVSampleBufferDisplayLayer`。
- **Metal**：`renderPipFrameInBackground()` 用 `renderMetalFrame(timeout: 1)` 拉最新
  幀，透過共用的 `makePipEncoder`（前景主 pass 與背景 pump 共用）畫進 capture texture。
- **OpenGL**：`renderPipFrameInBackground()` 設好 GL context → 綁 capture FBO →
  `renderGLFrame(timeout: 0)` → 垂直翻轉 blit。
- `teardown` / renderer `cleanUp` / `deinit` 都會清掉 `captureSourceRenderer`。

---

## 三、音訊不中斷用戶正在播的內容

PiP 的 AVAudioSession 加上 `.mixWithOthers`，啟用 PiP 時不會打斷
用戶正在聽的音樂或看的影片：

```swift
setCategory(.playback, mode: .default, options: [.mixWithOthers])
```

---

## 待驗證清單（需 Xcode 實機）

- [ ] iPad 上連接 16:9 主機 → 選單按 Picture in Picture → 小窗是 16:9 長方形
- [ ] PiP 播放中退回桌面 → 小窗持續更新（Metal / OpenGL 雙後端）
- [ ] PiP 播放中先開音樂 App 播放 → 再啟動 PiP → 音樂不被中斷
