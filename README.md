# RemoteImage

A lightweight, customizable SwiftUI image loading framework for downloading and displaying remote images with full control over placeholders, progress, failures, and cancellation.

![Swift](https://img.shields.io/badge/swift-5.9-orange)
![Platform](https://img.shields.io/badge/platform-iOS-blue)

---

## 🚀 Features

- 📦 Swift Package Manager support  
- 🧩 Fully customizable placeholders and error views  
- 📉 Progress tracking with live updates  
- ❌ Graceful handling of cancellation and failures  
- 🧼 Automatic cancellation on view disappearance (optional)  
- 🧵 Clean SwiftUI-style API

---

## 📦 Installation

Add the following URL to your **Swift Package Manager** dependencies:

https://github.com/AbrorbekSh/RemoteImage.git

1. Open your project in Xcode.
2. Go to **File > Add Packages**.
3. Paste the URL above.
4. Choose the version and add the package to your project.

---

## 🛠 Usage

```swift

RemoteImage("https://example.com/image.jpg")
    .placeholder {
        ProgressView()
    }
    .onProgress { progress in
        print("Download progress: \(progress)")
    }
    .failure { error in
        VStack {
            Image(systemName: "exclamationmark.triangle")
            Text("Failed to load image")
        }
    }
    .cancelOnDisappear(true)
    .resizable()
    .aspectRatio(contentMode: .fill)
    .frame(width: 100, height: 100)
    .clipped()

```

---

## 🔧 Parameters

| Modifier                    | Description                                                                 |
|-----------------------------|-----------------------------------------------------------------------------|
| `.placeholder {}`           | View to display while the image is loading                                 |
| `.failure {}`               | View to display if image loading fails                                     |
| `.onProgress {}`            | Closure providing live progress updates (range: 0.0 to 1.0)                 |
| `.cancelOnDisappear(true)`  | Automatically cancels loading when the view disappears                     |
| `.cancelLoading(trigger:)`  | Cancels loading manually via a bound trigger (`Binding<Bool>`)             |
| `.resizable()`              | Makes the image resizable like SwiftUI's `Image.resizable()`               |

---

## 📱 Demo App

Explore the demo project to see `RemoteImage` in action:  
👉 [RemoteImageDemo](https://github.com/AbrorbekSh/RemoteImageDemo)

---

## ✅ Requirements

- iOS 15.0+
- Swift 5.5+
- Xcode 13+
