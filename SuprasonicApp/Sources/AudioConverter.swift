import Foundation
import AVFoundation

class AudioConverter {
    enum ConversionError: Error {
        case fileNotFound
        case formatInitializationFailed
        case conversionFailed
        case cannotCreateOutput
    }
    
    /// Converts an audio file to 16kHz Mono Float32 standard format
    static func convertToStandardFormat(inputURL: URL) async throws -> ([Float], URL) {
        // 1. Validate Input
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: inputURL.path) else {
            throw ConversionError.fileNotFound
        }
        
        let asset = AVAsset(url: inputURL)
        _ = try await asset.load(.duration)
        
        // 2. Prepare Output (Temp file)
        let tempDir = fileManager.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent(UUID().uuidString + ".wav")
        
        // 3. Target Format: 16kHz, Mono, Float32
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            throw ConversionError.formatInitializationFailed
        }
        
        // 4. Perform Conversion using AVAssetReader/Writer or AVAudioConverter
        // Using AVAudioFile for simplicity
        let inputFile = try AVAudioFile(forReading: inputURL)
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: format.settings)
        
        // Create converter
        guard let converter = AVAudioConverter(from: inputFile.processingFormat, to: format) else {
            throw ConversionError.formatInitializationFailed
        }
        
        // Convert in chunks


        
        var error: NSError?
        var totalSamples: [Float] = []
        
        // Simple loop to read and write (this might be slow for huge files, but safe)
        // Better approach: Read entire file if memory allows, or stream.
        // Given ASR context, we usually want the whole buffer in memory for the MeetingManager anyway.
        
        // Let's use the converter callback pattern

        // Note: Resampling changes length.
        let ratio = 16000.0 / inputFile.processingFormat.sampleRate
        let targetFrameCount = AVAudioFrameCount(Double(inputFile.length) * ratio) + 4096
        
        // We will read simply loop reading from input and writing to output
        // actually existing helper extension? No.
        
        // Simplified Logic: Read into buffer, Convert, Write
        // We need an output buffer to hold converted data
        let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: targetFrameCount)!
        

        
        _ = converter.convert(to: pcmBuffer, error: &error) { packetCount, outStatus in
             // Input Block
             let inputCapacity = AVAudioFrameCount(Double(packetCount) / ratio) + 100
             if let inputBuff = AVAudioPCMBuffer(pcmFormat: inputFile.processingFormat, frameCapacity: inputCapacity) {
                 do {
                     try inputFile.read(into: inputBuff)
                     if inputBuff.frameLength == 0 {
                         outStatus.pointee = .endOfStream
                         return nil
                     }
                     outStatus.pointee = .haveData
                     return inputBuff
                 } catch {
                     outStatus.pointee = .endOfStream
                     return nil
                 }
             }
             outStatus.pointee = .endOfStream
             return nil
        }
        
        if let err = error {
            throw err
        }
        
        // Write to file
        try outputFile.write(from: pcmBuffer)
        
        // Extract samples
        if let data = pcmBuffer.floatChannelData?[0] {
            let bufferPointer = UnsafeBufferPointer(start: data, count: Int(pcmBuffer.frameLength))
            totalSamples = Array(bufferPointer)
        }
        
        print("✅ AudioConverter: Converted \(inputURL.lastPathComponent) -> \(totalSamples.count) samples")
        
        return (totalSamples, outputURL)
    }
}
