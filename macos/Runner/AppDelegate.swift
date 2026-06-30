import Cocoa
import FlutterMacOS
import Network
import ScreenCaptureKit
import VideoToolbox
import CoreMedia

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

// MARK: - Private CoreGraphics / SkyLight objc_msgSend Signatures
private typealias ModeInitFunc = @convention(c) (AnyObject, Selector, Double, Double, Double) -> AnyObject
private typealias SettingsInitFunc = @convention(c) (AnyObject, Selector) -> AnyObject
private typealias DisplayInitFunc = @convention(c) (AnyObject, Selector, AnyObject) -> AnyObject
private typealias DisplayInitWithDescriptorFunc = @convention(c) (AnyObject, Selector, AnyObject, AnyObject) -> AnyObject
private typealias DisplayIDFunc = @convention(c) (AnyObject, Selector) -> CGDirectDisplayID

// MARK: - VirtualDisplayManager Helper Class
@available(macOS 12.3, *)
class VirtualDisplayManager {
    static let shared = VirtualDisplayManager()
    
    private var activeDisplay: AnyObject?
    private var activeDisplayId: CGDirectDisplayID = 0
    
    var isCreated: Bool {
        return activeDisplay != nil
    }
    
    var displayID: CGDirectDisplayID {
        return activeDisplayId
    }
    
    func createVirtualDisplay(width: Int, height: Int) -> Bool {
        guard activeDisplay == nil else { return true }
        
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        guard handle != nil else {
            print("Failed to load SkyLight.framework")
            return false
        }
        
        guard let modeClass = NSClassFromString("CGVirtualDisplayMode"),
              let settingsClass = NSClassFromString("CGVirtualDisplaySettings"),
              let displayClass = NSClassFromString("CGVirtualDisplay") else {
            print("Required CGVirtualDisplay classes not found in SkyLight")
            return false
        }
        
        // Resolve objc_msgSend dynamically to avoid reserved-symbol conflicts
        let libobjc = dlopen("/usr/lib/libobjc.A.dylib", RTLD_LAZY)
        guard let msgSendPtr = dlsym(libobjc, "objc_msgSend") else {
            print("Failed to resolve objc_msgSend symbol")
            return false
        }
        
        let objc_msgSend_modeInit = unsafeBitCast(msgSendPtr, to: ModeInitFunc.self)
        let objc_msgSend_settingsInit = unsafeBitCast(msgSendPtr, to: SettingsInitFunc.self)
        let objc_msgSend_displayInit = unsafeBitCast(msgSendPtr, to: DisplayInitFunc.self)
        let objc_msgSend_displayID = unsafeBitCast(msgSendPtr, to: DisplayIDFunc.self)
        
        let allocSel = Selector(("alloc"))
        let initSel = Selector(("init"))
        
        // 1. Instantiate Mode
        let modeAlloc = (modeClass as AnyObject).perform(allocSel).takeUnretainedValue() as AnyObject
        let modeInitSel = Selector(("initWithWidth:height:refreshRate:"))
        let mode = objc_msgSend_modeInit(modeAlloc, modeInitSel, Double(width), Double(height), 60.0)
        
        // 2. Instantiate Settings
        let settingsAlloc = (settingsClass as AnyObject).perform(allocSel).takeUnretainedValue() as AnyObject
        let settings = objc_msgSend_settingsInit(settingsAlloc, initSel)
        
        _ = settings.perform(Selector(("setModes:")), with: [mode])
        _ = settings.perform(Selector(("setHiDPI:")), with: 1)
        
        // 3. Instantiate Virtual Display (Supports modern macOS 14+ descriptor-based constructor)
        let displayAlloc = (displayClass as AnyObject).perform(allocSel).takeUnretainedValue() as AnyObject
        var display: AnyObject? = nil
        let initDescriptorSel = Selector(("initWithDescriptor:"))
        
        if let displayNSClass = displayClass as? NSObject.Type,
           displayNSClass.instancesRespond(to: initDescriptorSel) {
            if let descriptorClass = NSClassFromString("CGVirtualDisplayDescriptor") {
                let descriptorAlloc = (descriptorClass as AnyObject).perform(allocSel).takeUnretainedValue() as AnyObject
                let descriptor = descriptorAlloc.perform(initSel).takeUnretainedValue() as AnyObject
                
                descriptor.setValue("ScreenMirror-Extended", forKey: "name")
                descriptor.setValue(width, forKey: "maxPixelsWide")
                descriptor.setValue(height, forKey: "maxPixelsHigh")
                descriptor.setValue(12345, forKey: "vendorID")
                descriptor.setValue(67890, forKey: "productID")
                descriptor.setValue(1, forKey: "serialNum")
                descriptor.setValue(DispatchQueue.main, forKey: "queue")
                
                display = objc_msgSend_displayInit(displayAlloc, initDescriptorSel, descriptor)
                
                if let finalDisplay = display {
                    _ = finalDisplay.perform(Selector(("applySettings:")), with: settings)
                }
            }
        }
        
        if display == nil {
            let displayInitSel = Selector(("initWithSettings:"))
            display = objc_msgSend_displayInit(displayAlloc, displayInitSel, settings)
        }
        
        guard let finalDisplay = display else {
            print("Failed to initialize CGVirtualDisplay instance")
            return false
        }
        
        self.activeDisplay = finalDisplay
        
        let idSel = Selector(("displayID"))
        self.activeDisplayId = objc_msgSend_displayID(finalDisplay, idSel)
        
        return true
    }
    
    func destroyVirtualDisplay() {
        guard let display = activeDisplay else { return }
        
        let termSel = Selector(("termination"))
        if display.responds(to: termSel) {
            _ = display.perform(termSel)
        }
        
        self.activeDisplay = nil
        self.activeDisplayId = 0
    }
}

// MARK: - UsbStreamer Native Class
@available(macOS 12.3, *)
class UsbStreamer: NSObject, SCStreamDelegate, SCStreamOutput {
    static let shared = UsbStreamer()
    
    private var connection: NWConnection?
    private var listener: NWListener?
    private var isStreaming = false
    private var heartbeatTimer: Timer?
    private var frameNumber: Int32 = 0
    
    // Phase 2 Streaming Capturers
    private var scStream: SCStream?
    private var compressionSession: VTCompressionSession?
    
    private var targetFps = 60
    private var targetBitrate = 10 * 1000 * 1000
    private var targetWidth = 1920
    private var targetHeight = 1080
    private var selectedDisplayId = ""
    private var extendDisplay = false
    
    var methodChannel: FlutterMethodChannel?
    
    func startMirroring(
        resolution: String,
        fps: Int,
        bitrate: Int,
        connectionMode: String,
        displayId: String,
        customWidth: Int,
        customHeight: Int,
        extendDisplay: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        stopMirroring()
        
        isStreaming = true
        frameNumber = 0
        self.targetFps = fps
        self.targetBitrate = bitrate
        self.selectedDisplayId = displayId
        self.extendDisplay = extendDisplay
        
        // Calculate resolution bounds
        var width = 1920
        var height = 1080
        if resolution == "r720p" {
            width = 1280
            height = 720
        } else if resolution == "custom" {
            width = customWidth
            height = customHeight
        } else if resolution == "native" {
            let screens = NSScreen.screens
            if let activeScreen = screens.first(where: {
                if let screenNum = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                    return screenNum.stringValue == displayId
                }
                return false
            }) {
                width = Int(activeScreen.frame.width)
                height = Int(activeScreen.frame.height)
            }
        }
        
        self.targetWidth = width
        self.targetHeight = height
        
        let port = NWEndpoint.Port(integerLiteral: 8080)
        
        if connectionMode == "adbReverse" {
            // adbReverse: macOS is Server (listens on port 8080)
            logNative("Starting server listener on port 8080 (ADB Reverse mode)...")
            startListener(port: port) { [weak self] success in
                if success {
                    self?.logNative("Server socket listening. Run connection listener on Android.")
                }
                completion(success)
            }
        } else {
            // adbForward: macOS is Client (connects to localhost:8080)
            logNative("Connecting to localhost:8080 in client mode (ADB Forward mode)...")
            connect(to: "127.0.0.1", port: port) { [weak self] success in
                if success {
                    self?.startMirroringCapture()
                    completion(true)
                } else {
                    self?.logNative("Connection to local receiver failed", level: "ERROR")
                    self?.notifyStatus("error", error: "Connection failed")
                    completion(false)
                }
            }
        }
    }
    
    func stopMirroring() {
        isStreaming = false
        
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        
        // Stop ScreenCaptureKit
        if let stream = scStream {
            stream.stopCapture { _ in }
            scStream = nil
        }
        
        // Destroy Virtual Extended display if active
        if extendDisplay {
            VirtualDisplayManager.shared.destroyVirtualDisplay()
        }
        
        // Release VideoToolbox session
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
        
        connection?.cancel()
        connection = nil
        
        listener?.cancel()
        listener = nil
        
        notifyStatus("disconnected")
        logNative("Streaming host stopped.")
    }
    
    private func connect(to host: String, port: NWEndpoint.Port, completion: @escaping (Bool) -> Void) {
        let hostEndpoint = NWEndpoint.Host(host)
        let connection = NWConnection(host: hostEndpoint, port: port, using: .tcp)
        self.connection = connection
        
        var called = false
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.logNative("Socket connected successfully to \(host):\(port)")
                if !called {
                    called = true
                    completion(true)
                }
            case .failed(let error):
                self?.logNative("Socket connection failed: \(error.localizedDescription)", level: "ERROR")
                self?.handleDisconnect()
                if !called {
                    called = true
                    completion(false)
                }
            case .cancelled:
                self?.logNative("Socket connection cancelled.")
                self?.handleDisconnect()
            default:
                break
            }
        }
        
        connection.start(queue: .main)
    }
    
    private func startListener(port: NWEndpoint.Port, completion: @escaping (Bool) -> Void) {
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: port)
            self.listener = listener
            
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.logNative("Server listening on port \(port)")
                    self?.notifyStatus("listening")
                    completion(true)
                case .failed(let error):
                    self?.logNative("Server failed to start: \(error.localizedDescription)", level: "ERROR")
                    self?.notifyStatus("error", error: error.localizedDescription)
                    completion(false)
                default:
                    break
                }
            }
            
            listener.newConnectionHandler = { [weak self] newConnection in
                guard let self = self else { return }
                self.logNative("Server accepted client connection: \(newConnection.endpoint)")
                self.connection = newConnection
                
                newConnection.stateUpdateHandler = { [weak self] state in
                    guard let self = self else { return }
                    switch state {
                    case .ready:
                        self.logNative("Accepted client ready.")
                        self.startMirroringCapture()
                    case .failed(let error):
                        self.logNative("Client connection failed: \(error.localizedDescription)", level: "ERROR")
                        self.handleDisconnect()
                    case .cancelled:
                        self.logNative("Client connection cancelled.")
                        self.handleDisconnect()
                    default:
                        break
                    }
                }
                newConnection.start(queue: .main)
            }
            
            listener.start(queue: .main)
        } catch {
            logNative("Failed to create NWListener: \(error.localizedDescription)", level: "ERROR")
            completion(false)
        }
    }
    
    // MARK: - ScreenCaptureKit & VideoToolbox Pipeline
    
    private func startMirroringCapture() {
        Task {
            var displayToCapture: SCDisplay? = nil
            
            // 1. Create a virtual extended monitor if requested
            if self.extendDisplay {
                self.logNative("Creating virtual extended monitor with size \(self.targetWidth)x\(self.targetHeight)...")
                let success = VirtualDisplayManager.shared.createVirtualDisplay(width: self.targetWidth, height: self.targetHeight)
                if success {
                    let virtualId = VirtualDisplayManager.shared.displayID
                    self.logNative("Created virtual extended display. ID: \(virtualId)")
                    displayToCapture = await getSCDisplay(displayId: String(virtualId))
                } else {
                    self.logNative("Virtual display creation failed. Falling back to primary display.", level: "WARNING")
                }
            }
            
            if displayToCapture == nil {
                displayToCapture = await getSCDisplay(displayId: self.selectedDisplayId)
            }
            
            guard let display = displayToCapture else {
                self.logNative("Failed to locate target display ID: \(self.selectedDisplayId)", level: "ERROR")
                self.notifyStatus("error", error: "Target display not found")
                return
            }
            
            self.initCompressionSession(width: self.targetWidth, height: self.targetHeight, fps: self.targetFps, bitrate: self.targetBitrate)
            
            do {
                let config = SCStreamConfiguration()
                config.width = self.targetWidth
                config.height = self.targetHeight
                config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(self.targetFps))
                config.queueDepth = 5
                config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange // NV12 format
                config.showsCursor = true
                
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.example.screenmirror.capture"))
                try await stream.startCapture()
                
                self.scStream = stream
                self.startHeartbeat()
                
                self.notifyStatus("streaming")
                self.logNative("Screen capture active. Mirroring display size \(self.targetWidth)x\(self.targetHeight)")
            } catch {
                self.logNative("ScreenCaptureKit failed to start: \(error.localizedDescription)", level: "ERROR")
                self.notifyStatus("error", error: error.localizedDescription)
            }
        }
    }
    
    private func getSCDisplay(displayId: String) async -> SCDisplay? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            if let display = content.displays.first(where: { String($0.displayID) == displayId }) {
                return display
            }
            return content.displays.first
        } catch {
            return nil
        }
    }
    
    private func initCompressionSession(width: Int, height: Int, fps: Int, bitrate: Int) {
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: { refCon, frameRefCon, status, infoFlags, sampleBuffer in
                guard status == noErr, let sampleBuffer = sampleBuffer else { return }
                let streamer = Unmanaged<UsbStreamer>.fromOpaque(refCon!).takeUnretainedValue()
                streamer.handleEncodedFrame(sampleBuffer: sampleBuffer)
            },
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &compressionSession
        )
        
        guard status == noErr, let session = compressionSession else {
            logNative("Failed to create VTCompressionSession: \(status)", level: "ERROR")
            return
        }
        
        VTSessionSetProperties(session, propertyDictionary: [
            kVTCompressionPropertyKey_RealTime: kCFBooleanTrue as Any,
            kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_Baseline_AutoLevel as Any, // No B-frames for zero latency
            kVTCompressionPropertyKey_AllowFrameReordering: kCFBooleanFalse as Any,
            kVTCompressionPropertyKey_ExpectedFrameRate: fps as CFNumber,
            kVTCompressionPropertyKey_AverageBitRate: bitrate as CFNumber,
            kVTCompressionPropertyKey_MaxKeyFrameInterval: 60 as CFNumber // keyframe every 60 frames (1s)
        ] as CFDictionary)
        
        VTCompressionSessionPrepareToEncodeFrames(session)
        logNative("VideoToolbox H.264 compressor initialized.")
    }
    
    private func encodePixelBuffer(_ pixelBuffer: CVPixelBuffer, presentationTimestamp: CMTime) {
        guard let session = compressionSession else { return }
        var flags: VTEncodeInfoFlags = []
        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTimestamp,
            duration: .invalid,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: &flags
        )
    }
    
    // MARK: - SCStreamDelegate & SCStreamOutput Callbacks
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard isStreaming, type == .screen else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        encodePixelBuffer(imageBuffer, presentationTimestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        logNative("SCStream capture session stopped with error: \(error.localizedDescription)", level: "ERROR")
        handleDisconnect()
    }
    
    // MARK: - Frame Parsing & Packetization
    
    func handleEncodedFrame(sampleBuffer: CMSampleBuffer) {
        guard isStreaming, let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        
        let isKeyframe = checkIsKeyframe(sampleBuffer)
        
        // 1. Send SPS/PPS header parameters on keyframe for decoder setup
        if isKeyframe {
            sendSpsPps(formatDescription: formatDescription)
        }
        
        // 2. Extract and format AVCC NALUs into Annex-B stream units
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        
        var length = 0
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>? = nil
        
        let status = CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &length,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        
        guard status == noErr, let rawData = dataPointer else { return }
        
        var annexBData = Data()
        var offset = 0
        while offset < totalLength {
            // Read 4-byte size prefix
            var naluSize: UInt32 = 0
            memcpy(&naluSize, rawData.advanced(by: offset), 4)
            naluSize = UInt32(bigEndian: naluSize)
            
            // Write Annex-B 4-byte start code (0x00000001)
            annexBData.append(contentsOf: [0, 0, 0, 1])
            
            // Append NALU body
            let naluBody = rawData.advanced(by: offset + 4)
            annexBData.append(UnsafeBufferPointer(start: UnsafePointer<UInt8>(OpaquePointer(naluBody)), count: Int(naluSize)))
            
            offset += 4 + Int(naluSize)
        }
        
        frameNumber += 1
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let flag: Int32 = isKeyframe ? 0x08 : 0x10 // 0x08 = I-Frame, 0x10 = P-Frame
        
        sendPacket(body: annexBData, flags: flag, timestamp: timestamp)
    }
    
    private func sendSpsPps(formatDescription: CMFormatDescription) {
        var parameterSetCount = 0
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDescription,
            parameterSetIndex: 0,
            parameterSetPointerOut: nil,
            parameterSetSizeOut: nil,
            parameterSetCountOut: &parameterSetCount,
            nalUnitHeaderLengthOut: nil
        )
        
        var configData = Data()
        for i in 0..<parameterSetCount {
            var parameterSetPointer: UnsafePointer<UInt8>? = nil
            var parameterSetSize = 0
            
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDescription,
                parameterSetIndex: i,
                parameterSetPointerOut: &parameterSetPointer,
                parameterSetSizeOut: &parameterSetSize,
                parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: nil
            )
            
            if let pointer = parameterSetPointer {
                configData.append(contentsOf: [0, 0, 0, 1])
                configData.append(pointer, count: parameterSetSize)
            }
        }
        
        if !configData.isEmpty {
            let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
            sendPacket(body: configData, flags: 0x04, timestamp: timestamp) // 0x04 = SPS/PPS Config
        }
    }
    
    private func checkIsKeyframe(_ sampleBuffer: CMSampleBuffer) -> Bool {
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
           let first = attachments.first {
            let notSync = first[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
            return !notSync
        }
        return false
    }
    
    private func sendPacket(body: Data, flags: Int32, timestamp: Int64) {
        guard let connection = connection else { return }
        
        var packetData = Data()
        writeInt32(Int32(body.count), into: &packetData)
        writeInt32(frameNumber, into: &packetData)
        writeInt64(timestamp, into: &packetData)
        writeInt32(flags, into: &packetData)
        packetData.append(body)
        
        connection.send(content: packetData, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.logNative("Packet send failure: \(error.localizedDescription)", level: "ERROR")
                self?.handleDisconnect()
            }
        })
    }
    
    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isStreaming, let connection = self.connection else { return }
            
            let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
            var packetData = Data()
            self.writeInt32(0, into: &packetData)
            self.writeInt32(0, into: &packetData)
            self.writeInt64(timestamp, into: &packetData)
            self.writeInt32(0x01, into: &packetData) // 0x01 = Heartbeat
            
            connection.send(content: packetData, completion: .contentProcessed { [weak self] error in
                if let error = error {
                    self?.logNative("Heartbeat send failure: \(error.localizedDescription)", level: "ERROR")
                    self?.handleDisconnect()
                }
            })
        }
    }
    
    private func handleDisconnect() {
        if isStreaming {
            logNative("Stream session disconnected.", level: "WARNING")
            stopMirroring()
        }
    }
    
    private func writeInt32(_ value: Int32, into data: inout Data) {
        var val = value.bigEndian
        withUnsafeBytes(of: &val) { data.append(contentsOf: $0) }
    }
    
    private func writeInt64(_ value: Int64, into data: inout Data) {
        var val = value.bigEndian
        withUnsafeBytes(of: &val) { data.append(contentsOf: $0) }
    }
    
    func getDisplays() -> [[String: Any]] {
        var displaysList = [[String: Any]]()
        let screens = NSScreen.screens
        for (index, screen) in screens.enumerated() {
            let name = screen.localizedName
            let rect = screen.frame
            var screenId = "\(index)"
            if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                screenId = screenNumber.stringValue
            }
            displaysList.append([
                "id": screenId,
                "name": name,
                "width": Int(rect.width),
                "height": Int(rect.height)
            ])
        }
        return displaysList
    }
    
    private func findAdbPath() -> String? {
        let paths = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb"
        ]
        let fileManager = FileManager.default
        for path in paths {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }
        if let whichOutput = executeShellCommand("/usr/bin/which", arguments: ["adb"])?.trimmingCharacters(in: .whitespacesAndNewlines),
           !whichOutput.isEmpty,
           fileManager.fileExists(atPath: whichOutput) {
            return whichOutput
        }
        return nil
    }
    
    func getDevices() -> [[String: Any]] {
        guard let adbPath = findAdbPath() else {
            logNative("adb not found in standard paths", level: "WARNING")
            return []
        }
        
        guard let output = executeShellCommand(adbPath, arguments: ["devices"]) else {
            return []
        }
        
        var devicesList = [[String: Any]]()
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let parts = line.split { $0.isWhitespace }.map(String.init)
            if parts.count >= 2 && parts[1] == "device" {
                let id = parts[0]
                var model = "Android Device"
                if let modelOutput = executeShellCommand(adbPath, arguments: ["-s", id, "shell", "getprop", "ro.product.model"])?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !modelOutput.isEmpty {
                    model = modelOutput
                }
                devicesList.append([
                    "id": id,
                    "model": model,
                    "status": "device"
                ])
            }
        }
        return devicesList
    }
    
    func runAdbCommand(action: String) -> Bool {
        guard let adbPath = findAdbPath() else {
            logNative("adb command failed: adb not found", level: "ERROR")
            return false
        }
        
        let args = action == "forward"
            ? ["forward", "tcp:8080", "tcp:8080"]
            : ["reverse", "tcp:8080", "tcp:8080"]
        
        logNative("Executing ADB config: \(adbPath) \(args.joined(separator: " "))")
        
        if executeShellCommand(adbPath, arguments: args) != nil {
            return true
        }
        return false
    }
    
    private func executeShellCommand(_ path: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
    
    private func logNative(_ message: String, level: String = "INFO") {
        DispatchQueue.main.async { [weak self] in
            self?.methodChannel?.invokeMethod("onLog", arguments: ["message": message, "level": level])
        }
    }
    
    private func notifyStatus(_ status: String, error: String? = nil) {
        DispatchQueue.main.async { [weak self] in
            self?.methodChannel?.invokeMethod("onStatusChanged", arguments: ["status": status, "error": error])
        }
    }
}
