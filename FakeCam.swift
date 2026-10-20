import Foundation
import ObjectiveC
import AVFoundation
import Photos
import UIKit

// ╔══════════════════════════════════════════════════╗
// ║  FakeCam — AhmadDev © 2026                      ║
// ║  Camera Interception for Minichat               ║
// ╚══════════════════════════════════════════════════╝

// MARK: - AhmadDev Color Theme
@objc class AhmadDevTheme: NSObject {
    @objc static let bg = UIColor(red: 28/255, green: 43/255, blue: 59/255, alpha: 1.0)
    @objc static let green = UIColor(red: 46/255, green: 204/255, blue: 112/255, alpha: 1.0)
    @objc static let greenA80 = UIColor(red: 46/255, green: 204/255, blue: 112/255, alpha: 0.8)
    @objc static let greenA25 = UIColor(red: 46/255, green: 204/255, blue: 112/255, alpha: 0.25)
    @objc static let greenA12 = UIColor(red: 46/255, green: 204/255, blue: 112/255, alpha: 0.12)
    @objc static let whiteA70 = UIColor(white: 1.0, alpha: 0.7)
    @objc static let whiteA40 = UIColor(white: 1.0, alpha: 0.4)
    @objc static let whiteA20 = UIColor(white: 1.0, alpha: 0.2)
    @objc static let whiteA08 = UIColor(white: 1.0, alpha: 0.08)
}

// MARK: - AhmadDev FakeCam State
@objc class AhmadDevFakeCamState: NSObject {
    @objc static let shared = AhmadDevFakeCamState()
    
    @objc var isIntercepting: Bool = false
    @objc var isActive: Bool = false       // is currently broadcasting fake
    @objc var mediaType: String = "none"   // "none", "image", "video"
    @objc var sourceImage: UIImage?
    @objc var sourceVideoURL: URL?
    @objc var statusText: String = "في الانتظار..."
    @objc var statusColor: UIColor = AhmadDevTheme.whiteA20
    
    @objc func setStatusActive(_ type: String) {
        mediaType = type
        isActive = true
        statusText = "البث يعمل — \(type == "image" ? "صورة" : "فيديو")"
        statusColor = AhmadDevTheme.greenA80
        AhmadDevPanel.shared.updateStatus()
    }
    
    @objc func setStatusWaiting() {
        isActive = false
        statusText = "في الانتظار..."
        statusColor = AhmadDevTheme.whiteA20
        AhmadDevPanel.shared.updateStatus()
    }
    
    @objc func setStatusError(_ text: String) {
        isActive = false
        statusText = text
        statusColor = UIColor(red: 231/255, green: 76/255, blue: 60/255, alpha: 0.8)
        AhmadDevPanel.shared.updateStatus()
    }
}

// MARK: - AhmadDev Frame Generator
@objc class AhmadDevFrameGenerator: NSObject {
    @objc static let shared = AhmadDevFrameGenerator()
    
    private var displayLink: CADisplayLink?
    private var videoReader: AVAssetReader?
    private var videoOutput: AVAssetReaderTrackOutput?
    private var videoAsset: AVAsset?
    private var isVideo: Bool = false
    private var targetWidth: Int = 640
    private var targetHeight: Int = 480
    private var targetFPS: Int = 30
    private var callback: ((CMSampleBuffer) -> Void)?
    private var lastFrameTime: CFTimeInterval = 0
    private var frameInterval: CFTimeInterval = 1.0 / 30.0
    
    @objc func startGenerating(
        width: Int, height: Int, fps: Int,
        callback: @escaping (CMSampleBuffer) -> Void
    ) -> Bool {
        self.targetWidth = width
        self.targetHeight = height
        self.targetFPS = fps
        self.frameInterval = 1.0 / Double(fps)
        self.callback = callback
        
        if let videoURL = AhmadDevFakeCamState.shared.sourceVideoURL {
            return startVideo(url: videoURL)
        } else if let image = AhmadDevFakeCamState.shared.sourceImage {
            return startImage(image)
        }
        return false
    }
    
    private func startImage(_ image: UIImage) -> Bool {
        isVideo = false
        guard let resized = ahmaddev_resizeImage(image, width: CGFloat(targetWidth), height: CGFloat(targetHeight)),
              let pixelBuffer = ahmaddev_imageToPixelBuffer(resized) else {
            return false
        }
        
        let interval = 1.0 / Double(targetFPS)
        DisplayLinkManager.shared.start(interval: interval) { [weak self] _ in
            guard let self = self else { return }
            if let buf = self.ahmaddev_createSampleBuffer(from: pixelBuffer) {
                self.callback?(buf)
            }
        }
        return true
    }
    
    private func startVideo(url: URL) -> Bool {
        isVideo = true
        videoAsset = AVAsset(url: url)
        guard let track = videoAsset?.tracks(withMediaType: .video).first else { return false }
        
        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: targetWidth,
            kCVPixelBufferHeightKey as String: targetHeight
        ]
        
        do {
            videoReader = try AVAssetReader(asset: videoAsset!)
            videoOutput = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
            videoOutput?.supportsRandomAccess = true
            if let output = videoOutput {
                videoReader?.add(output)
            }
            videoReader?.startReading()
        } catch {
            return false
        }
        
        let interval = 1.0 / Double(targetFPS)
        DisplayLinkManager.shared.start(interval: interval) { [weak self] _ in
            guard let self = self else { return }
            self.ahmaddev_readNextVideoFrame()
        }
        return true
    }
    
    private func ahmaddev_readNextVideoFrame() {
        guard let output = videoOutput,
              let sampleBuffer = output.copyNextSampleBuffer() else {
            // Loop video
            if let asset = videoAsset {
                videoReader?.cancelReading()
                if let track = asset.tracks(withMediaType: .video).first {
                    let settings: [String: Any] = [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                        kCVPixelBufferWidthKey as String: targetWidth,
                        kCVPixelBufferHeightKey as String: targetHeight
                    ]
                    videoOutput = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
                    videoOutput?.supportsRandomAccess = true
                    if let reader = try? AVAssetReader(asset: asset) {
                        if let output = videoOutput { reader.add(output) }
                        reader.startReading()
                        videoReader = reader
                    }
                }
            }
            return
        }
        callback?(sampleBuffer)
    }
    
    @objc func stopGenerating() {
        DisplayLinkManager.shared.stop()
        videoReader?.cancelReading()
        videoReader = nil
        videoOutput = nil
        videoAsset = nil
    }
    
    // Convert UIImage to CVPixelBuffer
    private func ahmaddev_imageToPixelBuffer(_ image: UIImage) -> CVPixelBuffer? {
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                          kCVPixelFormatType_32BGRA,
                                          attrs as CFDictionary, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()
        
        return buffer
    }
    
    // Create CMSampleBuffer from CVPixelBuffer
    private func ahmaddev_createSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var formatDescription: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard status == noErr, let desc = formatDescription else { return nil }
        
        var timing = CMSampleTimingInfo(
            duration: CMTimeMake(value: 1, timescale: Int32(targetFPS)),
            presentationTimeStamp: CMTimeMake(value: Int64(Date().timeIntervalSince1970 * Double(targetFPS)),
                                               timescale: Int32(targetFPS)),
            decodeTimeStamp: .invalid
        )
        
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: desc,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }
    
    // Resize image to target dimensions
    private func ahmaddev_resizeImage(_ image: UIImage, width: CGFloat, height: CGFloat) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}

// MARK: - AhmadDev DisplayLink Manager
@objc class DisplayLinkManager: NSObject {
    @objc static let shared = DisplayLinkManager()
    private var timer: DispatchSourceTimer?
    
    @objc func start(interval: TimeInterval, callback: @escaping (CFTimeInterval) -> Void) {
        stop()
        let queue = DispatchQueue(label: "com.ahmaddev.fakecam.frames", qos: .userInteractive)
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now(), repeating: interval)
        timer?.setEventHandler { [weak self] in
            guard self?.timer != nil else { return }
            callback(CACurrentMediaTime())
        }
        timer?.resume()
    }
    
    @objc func stop() {
        timer?.cancel()
        timer = nil
    }
}

// MARK: - AhmadDev Panel (Floating UI)
@objc class AhmadDevPanel: NSObject {
    @objc static let shared = AhmadDevPanel()
    
    private var panelWindow: UIWindow?
    private var fabButton: UIButton?
    private var panelView: UIView?
    private var isPanelVisible = false
    private var previewImageView: UIImageView?
    private var statusDot: UIView?
    private var statusLabel: UILabel?
    private var toggleSwitch: UIView?
    private var toggleKnob: UIView?
    private var isToggleOn = false
    private var swapButton: UIButton?
    private var typeBadgeLabel: UILabel?
    
    @objc func show() {
        DispatchQueue.main.async { [weak self] in
            self?.ahmaddev_createFab()
        }
    }
    
    private func ahmaddev_createFab() {
        guard fabButton == nil else { return }
        
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        
        panelWindow = UIWindow(windowScene: scene)
        panelWindow?.windowLevel = .alert + 301
        panelWindow?.backgroundColor = .clear
        panelWindow?.frame = scene.screen.bounds
        
        // FAB Button
        fabButton = UIButton(type: .custom)
        fabButton?.frame = CGRect(x: 16, y: 60, width: 48, height: 48)
        fabButton?.backgroundColor = AhmadDevTheme.bg
        fabButton?.layer.cornerRadius = 24
        fabButton?.layer.borderWidth = 2
        fabButton?.layer.borderColor = AhmadDevTheme.green.withAlphaComponent(0.6).cgColor
        fabButton?.setTitle("●", for: .normal)
        fabButton?.setTitleColor(AhmadDevTheme.whiteA20, for: .normal)
        fabButton?.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        fabButton?.addTarget(self, action: #selector(ahmaddev_togglePanel), for: .touchUpInside)
        fabButton?.autoresizingMask = [.flexibleRightMargin, .flexibleBottomMargin]
        
        panelWindow?.addSubview(fabButton!)
        panelWindow?.isHidden = false
        panelWindow?.rootViewController = UIViewController()
        
        ahmaddev_updateFabDot()
    }
    
    @objc private func ahmaddev_togglePanel() {
        if isPanelVisible {
            ahmaddev_hidePanel()
        } else {
            ahmaddev_showPanel()
        }
    }
    
    private func ahmaddev_showPanel() {
        guard panelView == nil else { return }
        isPanelVisible = true
        
        let panelW: CGFloat = 300
        let panelH: CGFloat = 280
        let panelX: CGFloat = 16
        let panelY: CGFloat = 116
        
        let panel = UIView(frame: CGRect(x: panelX, y: panelY, width: panelW, height: panelH))
        panel.backgroundColor = AhmadDevTheme.bg
        panel.layer.cornerRadius = 20
        panel.layer.borderWidth = 2
        panel.layer.borderColor = AhmadDevTheme.green.withAlphaComponent(0.6).cgColor
        panel.autoresizingMask = [.flexibleRightMargin, .flexibleBottomMargin]
        
        // --- Top Bar ---
        let topBar = UIView(frame: CGRect(x: 0, y: 0, width: panelW, height: 38))
        
        // Logo
        let logoStack = UIStackView()
        logoStack.axis = .vertical
        logoStack.spacing = 2
        logoStack.frame = CGRect(x: 14, y: 8, width: 80, height: 22)
        
        let l1 = UIView(frame: CGRect(x: 0, y: 0, width: 11, height: 3.5))
        l1.backgroundColor = AhmadDevTheme.green; l1.layer.cornerRadius = 2
        l1.transform = CGAffineTransform(rotationAngle: -0.35)
        logoStack.addSubview(l1)
        
        let l2 = UIView(frame: CGRect(x: 0, y: 7, width: 14, height: 3.5))
        l2.backgroundColor = .white; l2.layer.cornerRadius = 2
        logoStack.addSubview(l2)
        
        let l3 = UIView(frame: CGRect(x: 0, y: 14, width: 11, height: 3.5))
        l3.backgroundColor = AhmadDevTheme.green; l3.layer.cornerRadius = 2
        l3.transform = CGAffineTransform(rotationAngle: 0.35)
        logoStack.addSubview(l3)
        
        let logoText = UILabel(frame: CGRect(x: 22, y: 0, width: 20, height: 22))
        logoText.text = "AD"
        logoText.font = UIFont.boldSystemFont(ofSize: 11)
        logoText.textColor = .white
        logoStack.addSubview(logoText)
        topBar.addSubview(logoStack)
        
        let title = UILabel(frame: CGRect(x: 90, y: 8, width: 150, height: 22))
        title.text = "FakeCam"
        title.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        title.textColor = AhmadDevTheme.whiteA70
        topBar.addSubview(title)
        
        let minimizeBtn = UIButton(type: .system)
        minimizeBtn.frame = CGRect(x: panelW - 36, y: 8, width: 22, height: 22)
        minimizeBtn.backgroundColor = AhmadDevTheme.whiteA08
        minimizeBtn.layer.cornerRadius = 11
        minimizeBtn.setTitle("−", for: .normal)
        minimizeBtn.setTitleColor(AhmadDevTheme.whiteA40, for: .normal)
        minimizeBtn.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        minimizeBtn.addTarget(self, action: #selector(ahmaddev_hidePanel), for: .touchUpInside)
        topBar.addSubview(minimizeBtn)
        
        panel.addSubview(topBar)
        
        // --- Separator ---
        let sep1 = UIView(frame: CGRect(x: 14, y: 38, width: panelW - 28, height: 1))
        sep1.backgroundColor = AhmadDevTheme.green.withAlphaComponent(0.15)
        panel.addSubview(sep1)
        
        // --- Preview Section ---
        let previewSection = UIView(frame: CGRect(x: 14, y: 46, width: panelW - 28, height: 64))
        
        let previewBox = UIView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        previewBox.backgroundColor = UIColor(white: 0, alpha: 0.3)
        previewBox.layer.cornerRadius = 12
        previewBox.layer.borderColor = AhmadDevTheme.green.withAlphaComponent(0.15).cgColor
        previewBox.layer.borderWidth = 1
        previewBox.clipsToBounds = true
        
        previewImageView = UIImageView(frame: previewBox.bounds)
        previewImageView?.contentMode = .scaleAspectFill
        previewImageView?.clipsToBounds = true
        previewBox.addSubview(previewImageView!)
        
        typeBadgeLabel = UILabel(frame: CGRect(x: 3, y: 45, width: 45, height: 16))
        typeBadgeLabel?.font = UIFont.boldSystemFont(ofSize: 8)
        typeBadgeLabel?.textColor = .white
        typeBadgeLabel?.backgroundColor = AhmadDevTheme.green.withAlphaComponent(0.9)
        typeBadgeLabel?.textAlignment = .center
        typeBadgeLabel?.layer.cornerRadius = 4
        typeBadgeLabel?.clipsToBounds = true
        typeBadgeLabel?.isHidden = true
        previewBox.addSubview(typeBadgeLabel!)
        
        // Placeholder
        let placeholder = UILabel(frame: previewBox.bounds)
        placeholder.text = "🖼️"
        placeholder.font = UIFont.systemFont(ofSize: 24)
        placeholder.textAlignment = .center
        placeholder.tag = 999
        previewBox.addSubview(placeholder)
        
        previewSection.addSubview(previewBox)
        
        // Import Button
        let importBtn = UIButton(type: .system)
        importBtn.frame = CGRect(x: 74, y: 0, width: panelW - 116, height: 64)
        importBtn.backgroundColor = AhmadDevTheme.greenA12
        importBtn.layer.cornerRadius = 12
        importBtn.layer.borderWidth = 1.5
        importBtn.layer.borderColor = AhmadDevTheme.green.withAlphaComponent(0.4).cgColor
        importBtn.layer.borderStyle = .init(rawValue: 0)
        importBtn.setDashedBorder(color: AhmadDevTheme.green.withAlphaComponent(0.4))
        importBtn.setTitle("+\nاستيراد من الاستوديو", for: .normal)
        importBtn.setTitleColor(AhmadDevTheme.greenA80, for: .normal)
        importBtn.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        importBtn.titleLabel?.textAlignment = .center
        importBtn.titleLabel?.numberOfLines = 2
        importBtn.addTarget(self, action: #selector(ahmaddev_importMedia), for: .touchUpInside)
        previewSection.addSubview(importBtn)
        
        panel.addSubview(previewSection)
        
        // --- Toggle ---
        let toggleRow = UIView(frame: CGRect(x: 14, y: 118, width: panelW - 28, height: 30))
        
        let toggleLabel = UILabel(frame: CGRect(x: 0, y: 4, width: 150, height: 22))
        toggleLabel.text = "اعتراض الكاميرا"
        toggleLabel.font = UIFont.systemFont(ofSize: 13)
        toggleLabel.textColor = AhmadDevTheme.whiteA70
        toggleRow.addSubview(toggleLabel)
        
        toggleSwitch = UIView(frame: CGRect(x: panelW - 72, y: 3, width: 44, height: 24))
        toggleSwitch?.backgroundColor = AhmadDevTheme.whiteA08
        toggleSwitch?.layer.cornerRadius = 12
        toggleSwitch?.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(ahmaddev_toggleIntercept)))
        toggleRow.addSubview(toggleSwitch!)
        
        toggleKnob = UIView(frame: CGRect(x: 2, y: 2, width: 20, height: 20))
        toggleKnob?.backgroundColor = .white
        toggleKnob?.layer.cornerRadius = 10
        toggleSwitch?.addSubview(toggleKnob!)
        
        panel.addSubview(toggleRow)
        
        // --- Swap Button ---
        swapButton = UIButton(type: .system)
        swapButton?.frame = CGRect(x: 14, y: 156, width: panelW - 28, height: 36)
        swapButton?.backgroundColor = AhmadDevTheme.greenA12
        swapButton?.layer.cornerRadius = 10
        swapButton?.layer.borderWidth = 1
        swapButton?.layer.borderColor = AhmadDevTheme.green.withAlphaComponent(0.3).cgColor
        swapButton?.setTitle("📷 كاميرا حقيقية", for: .normal)
        swapButton?.setTitleColor(AhmadDevTheme.greenA80, for: .normal)
        swapButton?.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        swapButton?.addTarget(self, action: #selector(ahmaddev_swapSource), for: .touchUpInside)
        panel.addSubview(swapButton!)
        
        // --- Separator ---
        let sep2 = UIView(frame: CGRect(x: 14, y: 200, width: panelW - 28, height: 1))
        sep2.backgroundColor = AhmadDevTheme.green.withAlphaComponent(0.15)
        panel.addSubview(sep2)
        
        // --- Status ---
        let statusSection = UIView(frame: CGRect(x: 14, y: 208, width: panelW - 28, height: 24))
        
        statusDot = UIView(frame: CGRect(x: 0, y: 8, width: 8, height: 8))
        statusDot?.backgroundColor = AhmadDevTheme.whiteA20
        statusDot?.layer.cornerRadius = 4
        statusSection.addSubview(statusDot!)
        
        statusLabel = UILabel(frame: CGRect(x: 14, y: 4, width: panelW - 56, height: 16))
        statusLabel?.text = "في الانتظار..."
        statusLabel?.font = UIFont.systemFont(ofSize: 11)
        statusLabel?.textColor = AhmadDevTheme.whiteA40
        statusSection.addSubview(statusLabel!)
        
        panel.addSubview(statusSection)
        
        // --- Footer ---
        let footer = UILabel(frame: CGRect(x: 0, y: panelH - 16, width: panelW, height: 12))
        footer.text = "AhmadDev © 2026"
        footer.font = UIFont.systemFont(ofSize: 8)
        footer.textColor = AhmadDevTheme.whiteA20
        footer.textAlignment = .center
        panel.addSubview(footer)
        
        panelWindow?.addSubview(panel)
        panelView = panel
        
        // Update preview if media already loaded
        ahmaddev_updatePreview()
    }
    
    @objc private func ahmaddev_hidePanel() {
        isPanelVisible = false
        panelView?.removeFromSuperview()
        panelView = nil
    }
    
    @objc private func ahmaddev_toggleIntercept() {
        isToggleOn = !isToggleOn
        AhmadDevFakeCamState.shared.isIntercepting = isToggleOn
        
        UIView.animate(withDuration: 0.3) { [weak self] in
            guard let self = self else { return }
            self.toggleSwitch?.backgroundColor = self.isToggleOn ? AhmadDevTheme.greenA80 : AhmadDevTheme.whiteA08
            self.toggleKnob?.frame.origin.x = self.isToggleOn ? 22 : 2
        }
        
        if isToggleOn {
            if AhmadDevFakeCamState.shared.sourceImage == nil && AhmadDevFakeCamState.shared.sourceVideoURL == nil {
                ahmaddev_importMedia()
            }
        }
        
        ahmaddev_updateFabDot()
    }
    
    @objc private func ahmaddev_swapSource() {
        if AhmadDevFakeCamState.shared.isActive {
            AhmadDevFrameGenerator.shared.stopGenerating()
            AhmadDevFakeCamState.shared.setStatusWaiting()
            swapButton?.setTitle("📷 كاميرا حقيقية", for: .normal)
            swapButton?.backgroundColor = AhmadDevTheme.greenA12
            swapButton?.layer.borderColor = AhmadDevTheme.green.withAlphaComponent(0.3).cgColor
        }
    }
    
    @objc private func ahmaddev_importMedia() {
        DispatchQueue.main.async {
            guard let vc = self.panelWindow?.rootViewController else { return }
            let picker = UIImagePickerController()
            picker.sourceType = .photoLibrary
            picker.mediaTypes = ["public.image", "public.movie"]
            picker.delegate = self
            vc.present(picker, animated: true)
        }
    }
    
    @objc func updateStatus() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.statusLabel?.text = AhmadDevFakeCamState.shared.statusText
            self.statusLabel?.textColor = AhmadDevFakeCamState.shared.statusColor
            self.statusDot?.backgroundColor = AhmadDevFakeCamState.shared.isActive ? AhmadDevTheme.green : AhmadDevTheme.whiteA20
            
            if AhmadDevFakeCamState.shared.isActive {
                self.swapButton?.setTitle("🖼️ بث وهمي", for: .normal)
                self.swapButton?.backgroundColor = AhmadDevTheme.greenA25
                self.swapButton?.layer.borderColor = AhmadDevTheme.green.withAlphaComponent(0.5).cgColor
            }
            
            self.ahmaddev_updateFabDot()
        }
    }
    
    private func ahmaddev_updateFabDot() {
        let isActive = AhmadDevFakeCamState.shared.isActive
        fabButton?.setTitleColor(isActive ? AhmadDevTheme.green : AhmadDevTheme.whiteA20, for: .normal)
    }
    
    private func ahmaddev_updatePreview() {
        if let image = AhmadDevFakeCamState.shared.sourceImage {
            previewImageView?.image = image
            typeBadgeLabel?.isHidden = false
            typeBadgeLabel?.text = "🖼️ صورة"
            // Remove placeholder
            panelView?.viewWithTag(999)?.removeFromSuperview()
        }
    }
}

// MARK: - UIImagePickerControllerDelegate
extension AhmadDevPanel: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)
        
        if let url = info[.mediaURL] as? URL {
            AhmadDevFakeCamState.shared.sourceVideoURL = url
            AhmadDevFakeCamState.shared.mediaType = "video"
            // Generate thumbnail
            let asset = AVAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                AhmadDevFakeCamState.shared.sourceImage = UIImage(cgImage: cgImage)
            }
        } else if let image = info[.originalImage] as? UIImage {
            AhmadDevFakeCamState.shared.sourceImage = image
            AhmadDevFakeCamState.shared.sourceVideoURL = nil
            AhmadDevFakeCamState.shared.mediaType = "image"
        }
        
        ahmaddev_updatePreview()
        typeBadgeLabel?.text = AhmadDevFakeCamState.shared.mediaType == "video" ? "🎬 فيديو" : "🖼️ صورة"
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

// MARK: - UIButton Dashed Border Extension
extension UIButton {
    func setDashedBorder(color: UIColor) {
        let shape = CAShapeLayer()
        shape.strokeColor = color.cgColor
        shape.fillColor = nil
        shape.lineDashPattern = [6, 4]
        shape.lineWidth = 1.5
        shape.frame = bounds
        shape.path = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
        layer.addSublayer(shape)
    }
}

// MARK: - AhmadDev Hook Manager
@objc class AhmadDevHookManager: NSObject {
    @objc static let shared = AhmadDevHookManager()
    
    private var orig_startCapture: IMP?
    private var orig_stopCapture: IMP?
    private var orig_switchCamera: IMP?
    private var orig_startWatchingFace: IMP?
    private var orig_stopLocalStream: IMP?
    
    @objc func installHooks() {
        // Wait for WebRTC framework to load
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.ahmaddev_installAllHooks()
        }
    }
    
    private func ahmaddev_installAllHooks() {
        let rtccClass: AnyClass? = NSClassFromString("RTCCameraVideoCapturer")
        guard rtccClass != nil else {
            AhmadDevFakeCamState.shared.setStatusError("WebRTC غير محمّل")
            // Retry
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.ahmaddev_installAllHooks()
            }
            return
        }
        
        // Hook 1: startCaptureWithDevice:format:fps:
        let startSel = NSSelectorFromString("startCaptureWithDevice:format:fps:")
        let startMethod = class_getInstanceMethod(rtccClass!, startSel)
        if let method = startMethod {
            orig_startCapture = method_getImplementation(method)
            let block: @convention(block) (AnyObject, AnyObject, AnyObject, Int, UnsafeRawPointer?) -> Void = { [weak self] obj, device, format, fps, handler in
                self?.ahmaddev_handleStartCapture(target: obj, device: device, format: format, fps: fps, handler: handler, origIMP: self?.orig_startCapture)
            }
            let imp = imp_implementationWithBlock(block)
            method_setImplementation(method, imp)
        }
        
        // Hook 2: stopCapture
        let stopSel = NSSelectorFromString("stopCapture")
        let stopMethod = class_getInstanceMethod(rtccClass!, stopSel)
        if let method = stopMethod {
            orig_stopCapture = method_getImplementation(method)
            let block: @convention(block) (AnyObject) -> Void = { [weak self] obj in
                self?.ahmaddev_handleStopCapture(target: obj, origIMP: self?.orig_stopCapture)
            }
            let imp = imp_implementationWithBlock(block)
            method_setImplementation(method, imp)
        }
        
        // Hook 3: switchCamera (Minichat binary)
        if let vcClass = NSClassFromString("_TtC8Minichat19VideoChatInteractor") {
            let switchSel = NSSelectorFromString("switchCamera")
            let switchMethod = class_getInstanceMethod(vcClass, switchSel)
            if let method = switchMethod {
                orig_switchCamera = method_getImplementation(method)
                let block: @convention(block) (AnyObject) -> Void = { [weak self] obj in
                    if AhmadDevFakeCamState.shared.isActive {
                        return // Block switch while fake cam active
                    }
                    if let orig = self?.orig_switchCamera {
                        typealias Fn = @convention(c) (AnyObject, Selector) -> Void
                        unsafeBitCast(orig, to: Fn.self)(obj, switchSel)
                    }
                }
                let imp = imp_implementationWithBlock(block)
                method_setImplementation(method, imp)
            }
        }
        
        // Hook 4: startWatchingFace — disable face detection
        if let vcClass = NSClassFromString("_TtC8Minichat19VideoChatInteractor") {
            let faceSel = NSSelectorFromString("startWatchingFace")
            let faceMethod = class_getInstanceMethod(vcClass, faceSel)
            if let method = faceMethod {
                orig_startWatchingFace = method_getImplementation(method)
                let block: @convention(block) (AnyObject) -> Void = { _ in
                    return // No-op: disable face detection
                }
                let imp = imp_implementationWithBlock(block)
                method_setImplementation(method, imp)
            }
        }
        
        // Hook 5: stopLocalStream — cleanup
        if let vcClass = NSClassFromString("_TtC8Minichat19VideoChatInteractor") {
            let stopSel = NSSelectorFromString("stopLocalStream")
            let stopMethod = class_getInstanceMethod(vcClass, stopSel)
            if let method = stopMethod {
                orig_stopLocalStream = method_getImplementation(method)
                let block: @convention(block) (AnyObject) -> Void = { [weak self] obj in
                    AhmadDevFrameGenerator.shared.stopGenerating()
                    AhmadDevFakeCamState.shared.setStatusWaiting()
                    if let orig = self?.orig_stopLocalStream {
                        typealias Fn = @convention(c) (AnyObject, Selector) -> Void
                        unsafeBitCast(orig, to: Fn.self)(obj, stopSel)
                    }
                }
                let imp = imp_implementationWithBlock(block)
                method_setImplementation(method, imp)
            }
        }
        
        AhmadDevFakeCamState.shared.setStatusWaiting()
    }
    
    private func ahmaddev_handleStartCapture(
        target: AnyObject, device: AnyObject, format: AnyObject, fps: Int,
        handler: UnsafeRawPointer?, origIMP: IMP?
    ) {
        if !AhmadDevFakeCamState.shared.isIntercepting {
            // Call original
            if let orig = origIMP {
                typealias Fn = @convention(c) (AnyObject, Selector, AnyObject, AnyObject, Int, UnsafeRawPointer?) -> Void
                let sel = NSSelectorFromString("startCaptureWithDevice:format:fps:")
                unsafeBitCast(orig, to: Fn.self)(target, sel, device, format, fps, handler)
            }
            return
        }
        
        // Fake capture — determine resolution from format
        var width = 640, height = 480
        if let fmt = format as? AVCaptureDevice.Format {
            let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
            width = Int(dims.width)
            height = Int(dims.height)
        }
        
        let success = AhmadDevFrameGenerator.shared.startGenerating(
            width: width, height: height, fps: fps
        ) { sampleBuffer in
            // Feed frames to the capture delegate
            DispatchQueue.main.async {
                if let capturer = target as? NSObject {
                    let sel = NSSelectorFromString("captureOutput:didOutputSampleBuffer:fromConnection:")
                    if capturer.responds(to: sel) {
                        // Use the delegate pattern
                        let delegateSel = NSSelectorFromString("delegate")
                        if capturer.responds(to: delegateSel),
                           let delegate = capturer.perform(delegateSel)?.takeUnretainedValue() {
                            let captureSessionSel = NSSelectorFromString("captureSession")
                            if capturer.responds(to: captureSessionSel),
                               let session = capturer.perform(captureSessionSel)?.takeUnretainedValue() {
                                typealias Fn = @convention(c) (AnyObject, Selector, AnyObject, AnyObject, AnyObject?) -> Void
                                let imp = class_getMethodImplementation(object_getClass(delegate), sel)
                                unsafeBitCast(imp, to: Fn.self)(delegate, sel, session, sampleBuffer as AnyObject, nil)
                            }
                        }
                    }
                }
            }
        }
        
        if success {
            AhmadDevFakeCamState.shared.setStatusActive(AhmadDevFakeCamState.shared.mediaType)
        } else {
            AhmadDevFakeCamState.shared.setStatusError("فشل بدء البث — الرجوع للكاميرا")
            // Fallback to real camera
            if let orig = origIMP {
                typealias Fn = @convention(c) (AnyObject, Selector, AnyObject, AnyObject, Int, UnsafeRawPointer?) -> Void
                let sel = NSSelectorFromString("startCaptureWithDevice:format:fps:")
                unsafeBitCast(orig, to: Fn.self)(target, sel, device, format, fps, handler)
            }
        }
    }
    
    private func ahmaddev_handleStopCapture(target: AnyObject, origIMP: IMP?) {
        AhmadDevFrameGenerator.shared.stopGenerating()
        AhmadDevFakeCamState.shared.setStatusWaiting()
        
        if let orig = origIMP {
            typealias Fn = @convention(c) (AnyObject, Selector) -> Void
            let sel = NSSelectorFromString("stopCapture")
            unsafeBitCast(orig, to: Fn.self)(target, sel)
        }
    }
}

// MARK: - Entry Point
@_cdecl("FakeCamEntry")
public func FakeCamEntry() {
    // AhmadDev FakeCam Initialization
    AhmadDevHookManager.shared.installHooks()
    AhmadDevPanel.shared.show()
}

// Auto-load via constructor
struct FakeCamLoader {
    init() {
        // Small delay to ensure app is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            FakeCamEntry()
        }
    }
}

@_cdecl("__FakeCamInit")
public func __FakeCamInit() {
    FakeCamLoader()
}
