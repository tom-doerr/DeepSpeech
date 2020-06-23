//
//  DeepSpeech.swift
//  deepspeech_ios
//
//  Created by Reuben Morais on 14.06.20.
//  Copyright © 2020 Mozilla. All rights reserved.
//

import Foundation
import AVFoundation
import AudioToolbox
import Accelerate

import deepspeech_ios.libdeepspeech_Private

/// Holds audio information used for building waveforms
final class AudioContext {

    /// The audio asset URL used to load the context
    public let audioURL: URL

    /// Total number of samples in loaded asset
    public let totalSamples: Int

    /// Loaded asset
    public let asset: AVAsset

    // Loaded assetTrack
    public let assetTrack: AVAssetTrack

    private init(audioURL: URL, totalSamples: Int, asset: AVAsset, assetTrack: AVAssetTrack) {
        self.audioURL = audioURL
        self.totalSamples = totalSamples
        self.asset = asset
        self.assetTrack = assetTrack
    }

    public static func load(fromAudioURL audioURL: URL, completionHandler: @escaping (_ audioContext: AudioContext?) -> ()) {
        let asset = AVURLAsset(url: audioURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: NSNumber(value: true as Bool)])

        guard let assetTrack = asset.tracks(withMediaType: AVMediaType.audio).first else {
            fatalError("Couldn't load AVAssetTrack")
        }

        asset.loadValuesAsynchronously(forKeys: ["duration"]) {
            var error: NSError?
            let status = asset.statusOfValue(forKey: "duration", error: &error)
            switch status {
            case .loaded:
                guard
                    let formatDescriptions = assetTrack.formatDescriptions as? [CMAudioFormatDescription],
                    let audioFormatDesc = formatDescriptions.first,
                    let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormatDesc)
                    else { break }

                let totalSamples = Int((asbd.pointee.mSampleRate) * Float64(asset.duration.value) / Float64(asset.duration.timescale))
                let audioContext = AudioContext(audioURL: audioURL, totalSamples: totalSamples, asset: asset, assetTrack: assetTrack)
                completionHandler(audioContext)
                return

            case .failed, .cancelled, .loading, .unknown:
                print("Couldn't load asset: \(error?.localizedDescription ?? "Unknown error")")
            }

            completionHandler(nil)
        }
    }
}

func render(audioContext: AudioContext?, stream: OpaquePointer) {
    guard let audioContext = audioContext else {
        fatalError("Couldn't create the audioContext")
    }

    let sampleRange: CountableRange<Int> = 0..<audioContext.totalSamples

    guard let reader = try? AVAssetReader(asset: audioContext.asset)
        else {
            fatalError("Couldn't initialize the AVAssetReader")
    }

    reader.timeRange = CMTimeRange(start: CMTime(value: Int64(sampleRange.lowerBound), timescale: audioContext.asset.duration.timescale),
                                   duration: CMTime(value: Int64(sampleRange.count), timescale: audioContext.asset.duration.timescale))

    let outputSettingsDict: [String : Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsNonInterleaved: false
    ]

    let readerOutput = AVAssetReaderTrackOutput(track: audioContext.assetTrack,
                                                outputSettings: outputSettingsDict)
    readerOutput.alwaysCopiesSampleData = false
    reader.add(readerOutput)

    var sampleBuffer = Data()

    // 16-bit samples
    reader.startReading()
    defer { reader.cancelReading() }

    while reader.status == .reading {
        guard let readSampleBuffer = readerOutput.copyNextSampleBuffer(),
            let readBuffer = CMSampleBufferGetDataBuffer(readSampleBuffer) else {
                break
        }
        // Append audio sample buffer into our current sample buffer
        var readBufferLength = 0
        var readBufferPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(readBuffer,
                                    atOffset: 0,
                                    lengthAtOffsetOut: &readBufferLength,
                                    totalLengthOut: nil,
                                    dataPointerOut: &readBufferPointer)
        sampleBuffer.append(UnsafeBufferPointer(start: readBufferPointer, count: readBufferLength))
        CMSampleBufferInvalidate(readSampleBuffer)

        let totalSamples = sampleBuffer.count / MemoryLayout<Int16>.size
        print("read \(totalSamples) samples")
        
        sampleBuffer.withUnsafeBytes { (samples: UnsafeRawBufferPointer) in
            let unsafeBufferPointer = samples.bindMemory(to: Int16.self)
            let unsafePointer = unsafeBufferPointer.baseAddress!
            DS_FeedAudioContent(stream, unsafePointer, UInt32(totalSamples))
        }
        
        sampleBuffer.removeAll()
    }

    // if (reader.status == AVAssetReaderStatusFailed || reader.status == AVAssetReaderStatusUnknown)
    guard reader.status == .completed else {
        fatalError("Couldn't read the audio file")
    }
}

public class DeepSpeech {
    public class func open(path: String) -> OpaquePointer {
        var fooOpaque: OpaquePointer!
        DS_CreateModel(path, &fooOpaque)
        return fooOpaque
    }
    
    public class func createStream(modelState: OpaquePointer) -> OpaquePointer {
        var fooOpaque: OpaquePointer!
        DS_CreateStream(modelState, &fooOpaque)
        return fooOpaque
    }

    public class func test(modelState: OpaquePointer, audioPath: String) {
        let url = URL(fileURLWithPath: audioPath)

        //var format = AudioStreamBasicDescription.init()
        //format.mSampleRate = 16000;
        //format.mFormatID = kAudioFormatLinearPCM;
        //format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked;
        //format.mBitsPerChannel = 16;
        //format.mChannelsPerFrame = 1;
        //format.mBytesPerFrame = format.mChannelsPerFrame * format.mBitsPerChannel / 8;
        //format.mFramesPerPacket = 1;
        //format.mBytesPerPacket = format.mFramesPerPacket * format.mBytesPerFrame;
        //
        //var file = Optional<ExtAudioFileRef>.init(nilLiteral: ());
        //let status = ExtAudioFileCreateWithURL(url as CFURL,
        //                                       kAudioFileWAVEType,
        //                                       &format,
        //                                       nil,
        //                                       0,
        //                                       &file)
        //print("status: \(status)")
        //let status2 = ExtAudioFileSetProperty(file!,
        //                                     kExtAudioFileProperty_ClientDataFormat,
        //                                     UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
        //                                     &format)
        //print("status: \(status2)")
        //
        //ExtAudioFileRead(file, <#T##ioNumberFrames: UnsafeMutablePointer<UInt32>##UnsafeMutablePointer<UInt32>#>, <#T##ioData: UnsafeMutablePointer<AudioBufferList>##UnsafeMutablePointer<AudioBufferList>#>)
        
        let stream = createStream(modelState: modelState)
        AudioContext.load(fromAudioURL: url, completionHandler: { audioContext in
            guard let audioContext = audioContext else {
                fatalError("Couldn't create the audioContext")
            }
            render(audioContext: audioContext, stream: stream)
            let result = DS_FinishStream(stream)
            let asStr = String.init(cString: result!)
            print("asStr: \(asStr)")
            //return asStr
        })
        
        //let file = try! AVAudioFile(forReading: url)
        //print("file length \(file.length)")
        //let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)!
        //let stream = createStream(modelState: modelState)
        //while file.framePosition < file.length {
        //    let pcmBuf = AVAudioPCMBuffer.init(pcmFormat: format, frameCapacity: 8 * 1024)! // arbitrary frameCapacity
        //    try! file.read(into: pcmBuf)
        //    if pcmBuf.frameLength == 0 {
        //        break
        //    }
        //    print("read \(pcmBuf.frameLength) frames into buffer")
        //    let rawPtr = pcmBuf.audioBufferList.pointee.mBuffers.mData!
        //    let ptr = rawPtr.bindMemory(to: Int16.self, capacity: Int(pcmBuf.frameLength))
        //    print("first few samples: \(ptr[0]) \(ptr[1]) \(ptr[2]) \(ptr[3]) ")
        //    DS_FeedAudioContent(stream, ptr, UInt32(pcmBuf.frameLength))
        //}
        //let result = DS_FinishStream(stream)
        //return String.init(cString: result!)
    }
}
