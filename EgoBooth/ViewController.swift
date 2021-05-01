//
//  ViewController.swift
//  EgoBooth
//
//  Created by Will Powers on 9/12/16.
//  Copyright (c) 2021 Ion6, LLC. All rights reserved.
//

import UIKit
import MetalKit

final class ViewController: UIViewController {

    struct Attribute {
        static let vertex:Int = 0
        static let texturePosition:Int = 1
    }

    struct Uniform {
        static let videoFrame:Int = 0
        static let globalTime:Int = 1
        static let resolution:Int = 2
        static let touchpoint:Int = 3
        static let cameraResolution:Int = 4
    }

    let vertexData: [Float] = [
        1.0, -1.0,     1.0, 0.0,
        1.0, 1.0,      1.0, 1.0,
        -1.0, 1.0,     0.0, 1.0,
        -1.0, -1.0,    0.0, 0.0
    ]

    let indexData: [UInt32] = [0, 1, 2, 2, 3, 0]

    @IBOutlet weak var metalView: MTKView!
    private var metalDevice: MTLDevice?
    private var metalCommandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!

    private var vertexBuffer: MTLBuffer!
    private var indicesBuffer: MTLBuffer!

    private var cameraFeed: CameraFeed?
    private var viewSize: [CGFloat] = [ 0.0, 0.0 ]
    private var cameraResolution: [CGFloat] = [ 0.0, 0.0 ]
    private var touchPoint: [Float] = [ 0.5, 0.5 ]
    private var startDate: Date?
    private var touchSpeed: Float = 0.0
    private var selectedShader: String = "Fisheye"
    private var glitchTableVC: GlitchTableViewController?
    @IBOutlet weak var cameraButton: UIButton!

    private func setupMetal() {

        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            assertionFailure("Couldn't create metal device")
            return
        }

        metalCommandQueue = metalDevice.makeCommandQueue()
        metalView.device = metalDevice
        metalView.delegate = self

        let vertexBufferSize = vertexData.size()
        vertexBuffer = metalDevice.makeBuffer(bytes: vertexData,
                                              length: vertexBufferSize,
                                              options: .storageModeShared)

        let indicesBufferSize = indexData.size()
        indicesBuffer = metalDevice.makeBuffer(bytes: indexData,
                                               length: indicesBufferSize,
                                               options: .storageModeShared)
        self.metalDevice = metalDevice
    }

    @IBAction func showGlitchSelector() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        glitchTableVC = storyboard.instantiateViewController(
            withIdentifier: "GlitchTableVC") as? GlitchTableViewController
        guard let tableVC = glitchTableVC else {
            return
        }
        tableVC.delegate = self
        self.present(tableVC, animated: true, completion: nil)
    }

    @IBAction func rotateCamera() {
        cameraFeed?.rotateCamera()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        cameraButton.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.8)
        cameraButton.layer.cornerRadius = cameraButton.bounds.size.height / 2.0
        cameraButton.layer.masksToBounds = true
        cameraButton.contentEdgeInsets = UIEdgeInsets(top: 8.0, left: 8.0, bottom: 8.0, right: 8.0)

        let scale = UIScreen.main.scale
        viewSize[0] = self.view.frame.size.width*scale
        viewSize[1] = self.view.frame.size.height*scale

        cameraResolution[0] = UIScreen.main.bounds.height
        cameraResolution[1] = UIScreen.main.bounds.width

        setupMetal()
        registerShader(shaderFile: "Fisheye")

        startDate = Date()
        touchSpeed = 0.5
        if let mtlDevice = self.metalDevice {
            cameraFeed = CameraFeed(metalDevice: mtlDevice)
            cameraFeed?.startCapture()
        }
    }

    private func registerShader(shaderFile: String) {
        guard let mtlDevice = self.metalDevice,
              let path = Bundle.main.path(forResource: shaderFile, ofType: "metal"),
              let source = try? String(contentsOfFile: path, encoding: .utf8) else {
            assertionFailure("Invalid shader file")
            return
        }

        do {
            let library = try mtlDevice.makeLibrary(source: source, options: nil)
            let vertexProgram = library.makeFunction(name: "vertex_func")
            let fragmentProgram = library.makeFunction(name: "fragment_func")
            let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
            pipelineStateDescriptor.vertexFunction = vertexProgram
            pipelineStateDescriptor.fragmentFunction = fragmentProgram
            pipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipelineState = try mtlDevice.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
        } catch let error {
            assertionFailure("Error registering shader \(error)")
        }
    }

    private func getGlobalTime() -> Float {
        let elapsed: TimeInterval = Date().timeIntervalSince(startDate!)
        return Float(elapsed)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else {
            return
        }
        let touchLocation = touch.location(in: self.view)
        touchPoint[0] = Float(touchLocation.x / self.view.frame.size.width)
        touchPoint[1] = Float(touchLocation.y / self.view.frame.size.height)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else {
            return
        }
        let touchLocation = touch.location(in: self.view)
        touchPoint[0] = Float(touchLocation.x / self.view.frame.size.width)
        touchPoint[1] = Float(touchLocation.y / self.view.frame.size.height)
    }

    override var shouldAutorotate : Bool {
        return false
    }

    override var prefersStatusBarHidden : Bool {
        return false
    }

    override var supportedInterfaceOrientations : UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }
}

extension ViewController: MTKViewDelegate {

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable else {
          return
        }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)

        guard let commandBuffer = metalCommandQueue.makeCommandBuffer() else {
          return
        }

        guard let renderEncoder = commandBuffer
          .makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setRenderPipelineState(pipelineState)

        renderEncoder.drawIndexedPrimitives(
          type: .triangle,
          indexCount: indexData.count,
          indexType: .uint32,
          indexBuffer: indicesBuffer,
          indexBufferOffset: 0)

        renderEncoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
//    glClearColor(0.0, 0.0, 0.0, 1.0)
//    glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
//
//    guard cameraFeed?.videoTextureCache != nil else {
//        return
//    }
//
//    glBindVertexArrayOES(vertexArray)
//    glUseProgram(shader)
//
//    glUniform1f(uniforms[Uniform.globalTime], getGlobalTime())
//    glUniform2f(uniforms[Uniform.resolution], GLfloat(viewSize[0]), GLfloat(viewSize[1]))
//    glUniform2f(uniforms[Uniform.cameraResolution], GLfloat(cameraResolution[0]), GLfloat(cameraResolution[1]))
//    glUniform2f(uniforms[Uniform.touchpoint], touchPoint[0], touchPoint[1])
//    glUniform1i(uniforms[Uniform.videoFrame], 2)
//
//    glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
//    glBindVertexArrayOES(0)
  }
}

extension ViewController: GlitchTableViewDelegate {
    func didSelectGlitch(_ glitch: String) {
        selectedShader = glitch
        startDate = Date()
        touchSpeed = 0.5

//        guard loadShader(fragmentName: selectedShader) else {
//            assertionFailure("Error loading camera shader.")
//            return
//        }
    }
}
