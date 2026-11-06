import SceneKit
import SwiftUI

/*
 Объёмные наушники: настоящая 3D-сцена (SceneKit) со светом и бликами, на прозрачном фоне.
 Модель собрана из простых фигур: корпус, амбушюра (у Pro), ножка, сетка микрофона.
*/
struct AirPods3D: NSViewRepresentable {
    var pro = true

    func makeNSView(context: Context) -> SCNView {
        let v = PassThroughSCNView(frame: .zero)
        v.scene = Self.makeScene(pro: pro)
        v.backgroundColor = .clear
        v.wantsLayer = true
        v.layer?.isOpaque = false
        v.antialiasingMode = .multisampling4X
        v.rendersContinuously = true
        v.preferredFramesPerSecond = 60
        v.allowsCameraControl = false
        return v
    }

    func updateNSView(_ v: SCNView, context: Context) {}

    static func makeScene(pro: Bool) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear

        let pair = SCNNode()
        let left = bud(pro: pro)
        left.position = SCNVector3(-1.05, 0, 0)
        left.eulerAngles = SCNVector3(0, CGFloat.pi * 0.12, -0.12)
        let right = bud(pro: pro)
        right.scale = SCNVector3(-1, 1, 1)
        right.position = SCNVector3(1.05, 0, 0)
        right.eulerAngles = SCNVector3(0, -CGFloat.pi * 0.12, 0.12)
        pair.addChildNode(left)
        pair.addChildNode(right)
        pair.position = SCNVector3(0, 0.35, 0)
        pair.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 4.5)))
        scene.rootNode.addChildNode(pair)

        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 28
        cam.position = SCNVector3(0, 0.25, 6.6)
        scene.rootNode.addChildNode(cam)

        func light(_ type: SCNLight.LightType, _ intensity: CGFloat, _ pos: SCNVector3, _ color: NSColor = .white) {
            let n = SCNNode()
            n.light = SCNLight()
            n.light?.type = type
            n.light?.intensity = intensity
            n.light?.color = color
            n.position = pos
            if type == .directional || type == .spot { n.look(at: SCNVector3(0, 0, 0)) }
            scene.rootNode.addChildNode(n)
        }
        /* мягкий общий свет, ключевой сверху-слева, слабый заполняющий справа, контровой сзади */
        light(.ambient, 210, SCNVector3(0, 0, 0))
        light(.directional, 780, SCNVector3(-4, 5, 5))
        light(.omni, 220, SCNVector3(5, -2, 4), NSColor(white: 0.9, alpha: 1))
        light(.omni, 260, SCNVector3(0, 2, -6), NSColor(red: 1, green: 0.93, blue: 0.86, alpha: 1))
        return scene
    }

    static func gloss(_ c: NSColor, shininess: CGFloat = 0.85) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = c
        m.specular.contents = NSColor(white: 1, alpha: 1)
        m.shininess = shininess
        return m
    }

    /* один наушник; амбушюра смотрит внутрь (+x) */
    static func bud(pro: Bool) -> SCNNode {
        let node = SCNNode()
        let white = gloss(NSColor(white: 0.96, alpha: 1))

        let head = SCNNode(geometry: SCNSphere(radius: 0.62))
        head.geometry?.firstMaterial = white
        head.scale = SCNVector3(1.0, 0.9, 0.82)
        head.position = SCNVector3(0, 0.55, 0)
        node.addChildNode(head)

        if pro {
            let tip = SCNNode(geometry: SCNSphere(radius: 0.4))
            tip.geometry?.firstMaterial = gloss(NSColor(white: 0.82, alpha: 1), shininess: 0.25)
            tip.scale = SCNVector3(0.75, 1, 1)
            tip.position = SCNVector3(0.5, 0.58, 0.05)
            node.addChildNode(tip)
        } else {
            let grille = SCNNode(geometry: SCNSphere(radius: 0.2))
            grille.geometry?.firstMaterial = gloss(NSColor(white: 0.2, alpha: 1), shininess: 0.2)
            grille.scale = SCNVector3(0.4, 1, 1)
            grille.position = SCNVector3(0.58, 0.58, 0.05)
            node.addChildNode(grille)
        }

        let sensor = SCNNode(geometry: SCNSphere(radius: 0.12))
        sensor.geometry?.firstMaterial = gloss(NSColor(white: 0.08, alpha: 1), shininess: 0.9)
        sensor.scale = SCNVector3(1, 0.7, 0.35)
        sensor.position = SCNVector3(-0.15, 0.72, 0.5)
        node.addChildNode(sensor)

        let stemLen: CGFloat = pro ? 1.35 : 1.75
        let stem = SCNNode(geometry: SCNCapsule(capRadius: 0.2, height: stemLen))
        stem.geometry?.firstMaterial = white
        stem.position = SCNVector3(-0.08, 0.55 - stemLen / 2 - 0.15, -0.02)
        stem.eulerAngles = SCNVector3(0.08, 0, 0.06)
        node.addChildNode(stem)

        let mic = SCNNode(geometry: SCNCylinder(radius: 0.13, height: 0.02))
        mic.geometry?.firstMaterial = gloss(NSColor(white: 0.55, alpha: 1), shininess: 0.4)
        mic.position = SCNVector3(-0.08, 0.55 - stemLen - 0.13, -0.02)
        node.addChildNode(mic)
        return node
    }
}

/* клики проходят сквозь 3D-вид к SwiftUI (нажатие открывает меню «Звук») */
final class PassThroughSCNView: SCNView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
