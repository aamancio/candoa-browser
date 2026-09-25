// Records one window, and only that window, to a QuickTime movie.
//
//   swiftc -O -framework ScreenCaptureKit -framework AVFoundation \
//     -o /tmp/record-window Scripts/record-window.swift
//   /tmp/record-window <CGWindowID> <seconds> <output.mov>
//
// ScreenCaptureKit composes the window off screen, so whatever sits in front
// of it, and the pointer, never make it into the clip. Used by
// Scripts/site-screenshots.sh for the website's feature loop.
import AppKit
import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

let args = CommandLine.arguments
guard args.count == 4, let windowID = UInt32(args[1]), let seconds = Double(args[2]) else {
    fputs("usage: record-window <CGWindowID> <seconds> <output.mov>\n", stderr)
    exit(2)
}
let outputURL = URL(fileURLWithPath: args[3])
try? FileManager.default.removeItem(at: outputURL)

final class Recorder: NSObject, SCStreamOutput {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    var started = false
    var frames = 0

    init(size: CGSize) throws {
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 40_000_000],
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid else { return }
        // Skip frames ScreenCaptureKit marks as not fully drawn.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let status = attachments.first?[.status] as? Int,
           status != SCFrameStatus.complete.rawValue {
            return
        }
        if !started {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(buffer))
            started = true
        }
        if input.isReadyForMoreMediaData, input.append(buffer) { frames += 1 }
    }

    func finish() async {
        guard started else { return }
        input.markAsFinished()
        await writer.finishWriting()
    }
}

// A window-server connection and a run loop: ScreenCaptureKit needs both,
// even from a command-line tool.
_ = NSApplication.shared
Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            fputs("window \(windowID) is not on screen\n", stderr); exit(1)
        }
        let scale = 2.0
        let size = CGSize(width: (window.frame.width * scale).rounded(), height: (window.frame.height * scale).rounded())
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(size.width)
        config.height = Int(size.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 8
        let recorder = try Recorder(size: size)
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: DispatchQueue(label: "record-window"))
        try await stream.startCapture()
        try await Task.sleep(for: .seconds(seconds))
        try await stream.stopCapture()
        await recorder.finish()
        print("wrote \(outputURL.path): \(recorder.frames) frames at \(Int(size.width))x\(Int(size.height))")
    } catch {
        fputs("record-window: \(error)\n", stderr); exit(1)
    }
    exit(0)
}
RunLoop.main.run()
