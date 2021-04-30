//
//  ViewController.swift
//  EgoBooth
//
//  Created by Will Powers on 9/12/16.
//  Copyright (c) 2021 Ion6, LLC. All rights reserved.
//

import UIKit
import GLKit

final class ViewController: GLKViewController {

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

    private var attributes: [GLint] = [GLint](repeatElement(0, count: 2))
    private var uniforms: [GLint] = [GLint](repeatElement(0, count: 5))

    private var context: EAGLContext!

    private var shader: GLuint = 0

    private var vertexArray: GLuint = 0
    private var vertexBuffer: GLuint = 0

    private var cameraFeed: CameraFeed?
    private var viewSize: [CGFloat] = [ 0.0, 0.0 ]
    private var cameraResolution: [CGFloat] = [ 0.0, 0.0 ]
    private var touchPoint: [Float] = [ 0.5, 0.5 ]
    private var startDate: Date?
    private var touchSpeed: Float = 0.0
    private var selectedShader: String = "fisheye"
    private var glitchTableVC: GlitchTableViewController?
    @IBOutlet weak var cameraButton: UIButton!

    private var vertexSource:String {
        return "attribute vec4 position;" +
               "attribute vec2 texCoord;" +
               "varying highp vec2 v_TexCoord;" +
               "void main()" +
               "{" +
               "        gl_Position = position;" +
               "        v_TexCoord = texCoord;" +
               "}"
    }

    private func BUFFER_OFFSET(_ i: Int) -> UnsafeRawPointer {
        return UnsafeRawPointer(bitPattern: i)!
    }

    private func setupGL() {

        let scale = UIScreen.main.scale
        viewSize[0] = self.view.frame.size.width*scale
        viewSize[1] = self.view.frame.size.height*scale

        cameraResolution[0] = UIScreen.main.bounds.height
        cameraResolution[1] = UIScreen.main.bounds.width

        self.context = EAGLContext(api: .openGLES2)
        guard let ctxt = self.context else {
            assertionFailure("Failed to create ES context")
            return
        }

        let view = self.view as! GLKView
        view.context = ctxt
        view.drawableDepthFormat = .format24
        EAGLContext.setCurrent(ctxt)

        startDate = Date()
        touchSpeed = 0.5

        guard loadShader(fragmentName: selectedShader) else {
            assertionFailure("Error loading camera shader.")
            return
        }

        setupBuffers()
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

    private func loadShader(fragmentName: String) -> Bool {

        var vertShader: GLuint = 0
        var fragShader: GLuint = 0

        if shader != 0 {
            glDeleteProgram(shader)
            shader = 0
        }

        shader = glCreateProgram()

        if compileShader(&vertShader, type: GLenum(GL_VERTEX_SHADER), strCode: vertexSource) == false {
            assertionFailure("Failed to compile vertex shader")
            return false
        }

        guard let filePath = Bundle.main.url(forResource: fragmentName, withExtension: "fsh") else {
            return false
        }

        do {
            let fragmentData = try NSData(contentsOf: filePath, options: [.uncached, .alwaysMapped])
            if let fragmentSource = NSString(data: fragmentData as Data, encoding: String.Encoding.utf8.rawValue) {
                if compileShader(&fragShader, type: GLenum(GL_FRAGMENT_SHADER), strCode: fragmentSource as String) == false {
                    print("Failed to compile fragment shader")
                    return false
                }
            }
        } catch let error as NSError {
            fatalError(error.localizedFailureReason!)
        }

        // Attach vertex shader to program.
        glAttachShader(shader, vertShader)

        // Attach fragment shader to program.
        glAttachShader(shader, fragShader)

        // Link program.
        if linkProgram(shader) == false {
            assertionFailure("Failed to link program: \(shader)")

            if vertShader != 0 {
                glDeleteShader(vertShader)
                vertShader = 0
            }
            if fragShader != 0 {
                glDeleteShader(fragShader)
                fragShader = 0
            }
            if shader != 0 {
                glDeleteProgram(shader)
                shader = 0
            }

            return false
        }

        attributes[Attribute.vertex] = glGetAttribLocation(shader, "position")
        attributes[Attribute.texturePosition] = glGetAttribLocation(shader, "texCoord")

        uniforms[Uniform.touchpoint] = glGetUniformLocation(shader, "u_TouchPoint")
        uniforms[Uniform.videoFrame] = glGetUniformLocation(shader, "u_VideoFrame")
        uniforms[Uniform.globalTime] = glGetUniformLocation(shader, "u_GlobalTime")
        uniforms[Uniform.resolution] = glGetUniformLocation(shader, "u_Resolution")
        uniforms[Uniform.cameraResolution] = glGetUniformLocation(shader, "u_CameraResolution")

        // Release vertex and fragment shaders.
        if vertShader != 0 {
            glDetachShader(shader, vertShader)
            glDeleteShader(vertShader)
        }
        if fragShader != 0 {
            glDetachShader(shader, fragShader)
            glDeleteShader(fragShader)
        }

        return true
    }

    private func tearDownGL() {
        EAGLContext.setCurrent(self.context)
        glDeleteBuffers(1, &vertexBuffer)
        glDeleteVertexArraysOES(1, &vertexArray)

        if shader != 0 {
            glDeleteProgram(shader)
            shader = 0
        }
    }

    private func compileShader(_ shader: inout GLuint, type: GLenum, strCode: String) -> Bool {
        var status: GLint = 0

        var cStringSource = (strCode as NSString).utf8String
        shader = glCreateShader(type)
        glShaderSource(shader, 1, &cStringSource, nil)
        glCompileShader(shader)

        var logLength: GLint = 0
        glGetShaderiv(shader, GLenum(GL_INFO_LOG_LENGTH), &logLength)
        if logLength > 0 {
            var infoLog: [GLchar] = [GLchar](repeating: 0, count: Int(logLength))
            var infoLogLength: GLsizei = 0
            glGetShaderInfoLog(shader, logLength, &infoLogLength, &infoLog)
            let messageString = NSString(bytes: infoLog, length: Int(infoLogLength), encoding: String.Encoding.ascii.rawValue)
            print("Shader compile log: \(String(describing: messageString))")
        }

        glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &status)
        if status == 0 {
            glDeleteShader(shader)
            return false
        }
        return true
    }

    private func setupBuffers() {

        let vertexData:[Float] = [
            -1.0, -1.0,     1.0, 1.0,
            1.0, -1.0,      1.0, 0.0,
            -1.0, 1.0,      0.0, 1.0,
            1.0, 1.0,       0.0, 0.0
        ]

        glGenVertexArraysOES(1, &vertexArray)
        glBindVertexArrayOES(vertexArray)

        glGenBuffers(1, &vertexBuffer)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vertexBuffer)
        glBufferData(GLenum(GL_ARRAY_BUFFER),
                     MemoryLayout<GLfloat>.size*vertexData.count,
                     vertexData,
                     GLenum(GL_STATIC_DRAW))

        glEnableVertexAttribArray(GLuint(attributes[Attribute.vertex]))
        glVertexAttribPointer(GLuint(attributes[Attribute.vertex]),
                              2,
                              GLenum(GL_FLOAT),
                              GLboolean(GL_FALSE),
                              GLsizei(MemoryLayout<GLfloat>.size*4),
                              nil)

        glEnableVertexAttribArray(GLuint(attributes[Attribute.texturePosition]))
        glVertexAttribPointer(GLuint(attributes[Attribute.texturePosition]),
                              2,
                              GLenum(GL_FLOAT),
                              GLboolean(GL_FALSE),
                              GLsizei(MemoryLayout<GLfloat>.size*4),
                              BUFFER_OFFSET(MemoryLayout<GLfloat>.size*2))

        glBindVertexArrayOES(0)
    }

    private func linkProgram(_ prog: GLuint) -> Bool {
        var errorStatus: GLint = 0
        glLinkProgram(prog)

        glGetProgramiv(prog, GLenum(GL_LINK_STATUS), &errorStatus)
        return errorStatus != 0
    }

    private func validateProgram(prog: GLuint) -> Bool {
        //var logLength: GLsizei = 0
        var status: GLint = 0

        glValidateProgram(prog)
        //        glGetProgramiv(prog, GLenum(GL_INFO_LOG_LENGTH), &logLength)
        //        if logLength > 0 {
        //            var log: [GLchar] = [GLchar](repeating: 0, count: Int(logLength))
        //            glGetProgramInfoLog(prog, logLength, &logLength, &log)
        //            print("Program validate log: \n\(log)")
        //        }

        glGetProgramiv(prog, GLenum(GL_VALIDATE_STATUS), &status)
        var returnVal = true
        if status == 0 {
            returnVal = false
        }
        return returnVal
    }

    @IBAction func rotateCamera() {
        cameraFeed?.rotateCamera()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self

        cameraButton.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.8)
        cameraButton.layer.cornerRadius = cameraButton.bounds.size.height / 2.0
        cameraButton.layer.masksToBounds = true
        cameraButton.contentEdgeInsets = UIEdgeInsets(top: 8.0, left: 8.0, bottom: 8.0, right: 8.0)

        setupGL()
        cameraFeed = CameraFeed(context: self.context)
        cameraFeed?.startCapture()
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

extension ViewController : GLKViewControllerDelegate {

    func glkViewControllerUpdate(_ controller: GLKViewController) { }

    func glkViewController(_ controller: GLKViewController, willPause pause: Bool) { }

    override func glkView(_ view: GLKView, drawIn rect: CGRect) {

        glClearColor(0.0, 0.0, 0.0, 1.0)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))

        guard cameraFeed?.videoTextureCache != nil else {
            return
        }

        glBindVertexArrayOES(vertexArray)
        glUseProgram(shader)

        glUniform1f(uniforms[Uniform.globalTime], getGlobalTime())
        glUniform2f(uniforms[Uniform.resolution], GLfloat(viewSize[0]), GLfloat(viewSize[1]))
        glUniform2f(uniforms[Uniform.cameraResolution], GLfloat(cameraResolution[0]), GLfloat(cameraResolution[1]))
        glUniform2f(uniforms[Uniform.touchpoint], touchPoint[0], touchPoint[1])
        glUniform1i(uniforms[Uniform.videoFrame], 2)

        glDisable(GLenum(GL_DEPTH_TEST))
        glDepthMask(GLboolean(truncating: false))
        glDisable(GLenum(GL_SAMPLE_ALPHA_TO_COVERAGE))
        glDisable(GLenum(GL_BLEND))

        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
        glBindVertexArrayOES(0)
    }
}

extension ViewController: GlitchTableViewDelegate {
    func didSelectGlitch(_ glitch: String) {
        selectedShader = glitch
        startDate = Date()
        touchSpeed = 0.5

        guard loadShader(fragmentName: selectedShader) else {
            assertionFailure("Error loading camera shader.")
            return
        }

        setupBuffers()
    }
}
