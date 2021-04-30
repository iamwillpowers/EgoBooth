//
//  CameraOverlay.swift
//  EgoBooth
//
//  Created by Will Powers on 2/9/17.
//  Copyright © 2017 Ion6, LLC. All rights reserved.
//

import AVFoundation
import OpenGLES
import UIKit

final class CameraFeed: NSObject {

    var videoTextureCache: CVOpenGLESTextureCache?
    private var rgbaTexture: CVOpenGLESTexture?
    private var captureSession:AVCaptureSession?
    private var captureDevice:AVCaptureDevice?
    private var videoOutput:AVCaptureVideoDataOutput?
    private var cameraPosition: AVCaptureDevice.Position = .front
    private weak var context: EAGLContext?

    init(context: EAGLContext) {
        self.context = context
    }
    
    func startCapture() {
        
        let devicePosition = cameraPosition
        // TODO: Accomodate more than just the wide angle camera
        let deviceDescoverySession = AVCaptureDevice.DiscoverySession.init(
            deviceTypes: [AVCaptureDevice.DeviceType.builtInWideAngleCamera],
            mediaType: AVMediaType.video,
            position: devicePosition)
            
        for device in deviceDescoverySession.devices {
            if device.position == devicePosition {
                captureDevice = device
                if captureDevice != nil {
                    beginSession()
                }
                break
            }
        }
    }
        
    func pauseSession() {
        if let session = captureSession, session.isRunning {
            session.stopRunning()
        }
    }
    
    func resumeSession() {
        if let session = captureSession, session.isRunning == false {
            session.startRunning()
        }
    }

    func rotateCamera() {
        pauseSession()
        cameraPosition = cameraPosition == .back ? .front : .back
        startCapture()
    }
    
    private func beginSession() {
        
        captureSession = AVCaptureSession()
        
        guard let session = captureSession else {
            return
        }

        guard let device = captureDevice else {
            return
        }

        guard !session.isRunning else {
            assertionFailure("Session is already running!")
            return
        }

        guard let ctxt = self.context else {
            return
        }
        
        let status = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault,
                                                  nil,
                                                  ctxt,
                                                  nil,
                                                  &videoTextureCache)
        guard status == kCVReturnSuccess else {
            assertionFailure("Couldn't create video cache! \(status)")
            return
        }
        
        do {
            let input:AVCaptureDeviceInput = try AVCaptureDeviceInput(device: device)
            
            guard session.canAddInput(input) else {
                assertionFailure("Couldn't add video input.")
                return
            }
            
            session.addInput(input)

            videoOutput = AVCaptureVideoDataOutput()
            
            guard let output = videoOutput else {
                assertionFailure("Error creating video output.")
                return
            }
            
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [((kCVPixelBufferPixelFormatTypeKey as NSString) as String) :
                                        NSNumber(value: kCVPixelFormatType_32BGRA)]
            output.setSampleBufferDelegate(self, queue: DispatchQueue.main)

            guard session.canAddOutput(output) else {
                assertionFailure("Couldn't add video output.")
                return
            }

            session.addOutput(output)
            session.sessionPreset = AVCaptureSession.Preset.high
            session.startRunning()
            
        } catch let error {
            assertionFailure("error: \(error.localizedDescription)")
        }
    }
}


extension CameraFeed : AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard videoTextureCache != nil else {
            assertionFailure("No video texture cache")
            return
        }

        rgbaTexture = nil
        // Periodic texture cache flush every frame
        CVOpenGLESTextureCacheFlush(videoTextureCache!, 0)

        // CVOpenGLESTextureCacheCreateTextureFromImage will create GLES texture
        // optimally from CVImageBufferRef.
        glActiveTexture(GLenum(GL_TEXTURE2))
        let status = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                  videoTextureCache!,
                                                                  pixelBuffer,
                                                                  nil,
                                                                  GLenum(GL_TEXTURE_2D),
                                                                  GL_RGBA,
                                                                  GLsizei(width),
                                                                  GLsizei(height),
                                                                  GLenum(GL_BGRA),
                                                                  GLenum(GL_UNSIGNED_BYTE),
                                                                  0,
                                                                  &rgbaTexture)

        guard status == kCVReturnSuccess else {
            assertionFailure("Error at CVOpenGLESTextureCacheCreateTextureFromImage \(status)")
            return
        }

        if let texture = rgbaTexture {
            glBindTexture(CVOpenGLESTextureGetTarget(texture), CVOpenGLESTextureGetName(texture))
            glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE))
            glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE))
        }

        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
    }
}
