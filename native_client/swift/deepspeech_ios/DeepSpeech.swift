//
//  DeepSpeech.swift
//  deepspeech_ios
//
//  Created by Reuben Morais on 14.06.20.
//  Copyright © 2020 Mozilla. All rights reserved.
//

import Foundation
import AVFoundation

import deepspeech_ios.libdeepspeech_Private

public class DeepSpeech {
    public class func open(path: String) -> OpaquePointer {
        let foo = UnsafeMutablePointer<AnyObject>.allocate(capacity: 1);
        var fooOpaque : OpaquePointer! = OpaquePointer(foo);
        DS_CreateModel(path, &fooOpaque);
        return fooOpaque;
    }

    public class func test(ptr: OpaquePointer, audioPath: String) -> String {
        let url = URL(fileURLWithPath: audioPath);
        let file = try! AVAudioFile(forReading: url);
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false);
        let buf = AVAudioPCMBuffer(pcmFormat: format!, frameCapacity: 1024);
        try! file.read(into: buf!);
        let buffer = UnsafeBufferPointer(start: buf!.int16ChannelData![0], count: Int(buf!.frameLength));
        let result = DS_SpeechToText(ptr, buffer.baseAddress!, buf!.frameLength);
        return String.init(cString: result!);
    }
}
