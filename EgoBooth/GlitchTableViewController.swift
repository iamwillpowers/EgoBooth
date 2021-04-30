//
//  GlitchSelector.swift
//  EgoBooth
//
//  Created by Darkstar on 4/30/21.
//

import UIKit

protocol GlitchTableViewDelegate {
    func didSelectGlitch(_ glitch: String)
}

class GlitchTableViewController: UITableViewController {

    struct ShaderInfo {
        var fileName: String
        var title: String
    }

    var delegate: GlitchTableViewDelegate?
    private var shaderInfo: [ShaderInfo] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        shaderInfo.append(ShaderInfo(fileName: "edgehighlights", title: "Edge Highlights"))
        shaderInfo.append(ShaderInfo(fileName: "infrared", title: "Infrared"))
        shaderInfo.append(ShaderInfo(fileName: "points", title: "Pointillize"))
        shaderInfo.append(ShaderInfo(fileName: "delirium", title: "Delirium"))
        shaderInfo.append(ShaderInfo(fileName: "reflect", title: "Reflecting Pool"))
        shaderInfo.append(ShaderInfo(fileName: "lighttunnel", title: "Light Tunnel"))
        shaderInfo.append(ShaderInfo(fileName: "edge", title: "Edge"))
        shaderInfo.append(ShaderInfo(fileName: "fisheye", title: "Fisheye"))
        shaderInfo.append(ShaderInfo(fileName: "radialblur", title: "Radial Blur"))
        shaderInfo.append(ShaderInfo(fileName: "matrix", title: "Inside the Matrix"))
        shaderInfo.append(ShaderInfo(fileName: "crt", title: "Old TV"))
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return shaderInfo.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "shaderCellIdentifier", for: indexPath)

        cell.textLabel?.text = shaderInfo[indexPath.row].title

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        delegate?.didSelectGlitch(shaderInfo[indexPath.row].fileName)
        self.dismiss(animated: true, completion: nil)
    }
}
