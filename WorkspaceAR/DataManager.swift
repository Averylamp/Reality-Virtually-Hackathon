//
//  DataManager.swift
//  WorkspaceAR
//
//  Created by Avery Lamp on 10/7/17.
//  Copyright © 2017 Apple. All rights reserved.
//

import UIKit
import SceneKit

enum UserType {
    case Host
    case Client
}

enum State{
    case FindingPlane
    case AlignmentStage
    case Creative
}

protocol DataManagerDelegate {
    func receivedAlignmentPoints(points: [CGPoint])
    func receivedObjectsUpdate(objects: [SharedARObject])
    func receivedNewObject(object: SharedARObject)
    func newDevicesConnected(devices: [String])
}

class DataManager {
	
	var creativeIsMovingAPoint:Bool = false
	
    var delegate : DataManagerDelegate?
    
    static var sharedInstance: DataManager = {
        let dataManager = DataManager()
        return dataManager
    }()
    
    class func shared() -> DataManager {
        return sharedInstance
    }
    
    init(){
        connectivity.delegate = self
        initiateObjectStore()
        displayLink = CADisplayLink(target: self, selector: #selector(update))
        displayLink.preferredFramesPerSecond = 10
        displayLink.add(to: RunLoop.current, forMode: .defaultRunLoopMode)
        displayLink.isPaused = true
    }
    
    var lastSelectedObjectSet = 0
    var solarSystemObjects = [SharedARObjectDescriptor]()
    var chessObjects = [SharedARObjectDescriptor]()
    var constructionObjects = [SharedARObjectDescriptor]()
    
    
    var connectivity = ConnectivityManager()
    
    var allConnectedDevices = [String]()
    
    var userType: UserType?
    var state: State = State.AlignmentStage
    
    var alignmentSCNNodes = [SCNNode]()
    var alignmentPoints = [CGPoint]()
    
    var rootNode: SCNNode?
    var loadedNodes = [SCNNode]()
    
    var objects
        = [SharedARObject]()
    
    var currentObjectPlacing: SCNNode? 
    var currentObjectDescriptor: SharedARObjectDescriptor?
    var currentPhysicsBody: SCNPhysicsBody?
    var displayLink = CADisplayLink()
    
    @objc func update(){
//       print("Run loop update \(CACurrentMediaTime())")
        if let node = self.currentObjectPlacing, let root = rootNode{
            var data = [String: Any]()
            data["name"] = node.name!
            let newTransform = root.convertTransform(node.transform, from: node.parent)
            data["transform"] = newTransform.toFloatArray()
            print("Sending new Transform -\(newTransform)")
            sendAnimation(object: data)
        }
        
    }
    
    func createSharedARObjectForCurrentNode(){
        if let node = self.currentObjectPlacing, let objectDescriptor  = self.currentObjectDescriptor, let root = rootNode {
            let firstTransform = root.convertTransform(node.transform, from: node.parent)
            
            node.physicsBody?.isAffectedByGravity = true
            
            let sharedARObj = SharedARObject(name: objectDescriptor.name,
                                             modelName: objectDescriptor.modelName,
                                             animation: objectDescriptor.animations,
                                             transform: firstTransform,
                                             descriptionText: objectDescriptor.description,
                                             mass: Double(objectDescriptor.physicsBody.mass),
                                             restitution: Double(objectDescriptor.physicsBody.restitution))
            node.name = sharedARObj.id
            self.objects.append(sharedARObj)
            sendObject(object: sharedARObj)
            
        }
    }
    
    func lockNewNode(){
    //  For some reason crashes when calling.parent or trying to enter main queue
		if let node = self.currentObjectPlacing, let root = rootNode {
			
//			let an = CAAnimation.animation(withSceneName: node.name!)
//			node.addAnimation(an, forKey: "start")
			
			
            node.transform = root.convertTransform(node.transform, from: node.parent)
            node.removeFromParentNode()
            root.addChildNode(node)
            for item in self.objects{
                if item.name == node.name{
                    sendObject(object: item)
                }
            }
            if let descriptor = self.currentObjectDescriptor {
                node.physicsBody = descriptor.physicsBody.copy() as! SCNPhysicsBody
            }
            if let pBody = self.currentPhysicsBody{
                node.physicsBody = pBody.copy() as! SCNPhysicsBody
                self.currentPhysicsBody = nil
            }
            
            
            self.currentObjectDescriptor = nil
            self.currentObjectPlacing = nil
            self.displayLink.isPaused = true
        }
        print("Lock node called")
		DataManager.shared().creativeIsMovingAPoint = false
    }
    
    func nodeAnimation(nodeName: String, transform: SCNMatrix4){
        print("attempting to animate")
        if let root = rootNode, let movingNode = root.childNode(withName: nodeName, recursively: false){
            print("Animating new Transform \(transform.m41), \(transform.m42), \(transform.m43)")
            let animation = CABasicAnimation(keyPath: "transform")
            animation.fromValue = movingNode.transform
            animation.toValue = transform
            animation.duration = 12 / 60.0
            movingNode.addAnimation(animation, forKey: nil)
            movingNode.transform = transform
        }
        
    }
    
    func sendAnimation(object: [String: Any]){
        let objectData = NSKeyedArchiver.archivedData(withRootObject: object)
        connectivity.sendData(data: objectData)
    }
    
    func sendObject(object: SharedARObject){
        let objectData = NSKeyedArchiver.archivedData(withRootObject: object)
        connectivity.sendData(data: objectData)
    }
    
    func updateObject(object: SharedARObject){
        if let root = rootNode{
            if let node = root.childNode(withName: object.id, recursively: true){
                print("Updating transform of object")
                node.transform = object.transform
            }else{
                var physicsBody = SCNPhysicsBody()
                if object.mass > 0{
                    physicsBody = SCNPhysicsBody.dynamic()
                    physicsBody.mass = CGFloat(object.mass)
                    physicsBody.restitution = CGFloat(object.restitution)
                }else{
                    physicsBody = SCNPhysicsBody.static()
                }
                
                let objectDescriptor = SharedARObjectDescriptor(name: object.name, physicsBody: physicsBody, transform: object.transform, modelName: object.modelName, description: object.descriptionText, multipleAllowed: true, animations:object.animation)
                if let pointNode = objectDescriptor.BuildSCNNode(){
                    pointNode.name = object.id
                    root.addChildNode(pointNode)
                }else{
                    print("FAILED TO BUILD NODE")
                }
            }
        }
    }
    
    func updateWholeScene(){
        for object in objects{
            updateObject(object: object)
        }
    }
    
    func removeObject(object:SharedARObject){
        if let root = rootNode{
            if let node = root.childNode(withName: object.id, recursively: true){
                //TODO: - Animated remove
                node.removeFromParentNode()
            }
        }
        
    }
    
    func broadcastAlignmentPoints(){
        guard userType == .Host else {
            print("Not host, don't broadcast points")
            return
        }
        guard state == .Creative else{
            print("Not finished picking alignment points")
            return
        }
        let pointData = NSKeyedArchiver.archivedData(withRootObject: alignmentPoints)
        connectivity.sendData(data: pointData)
    }
    
    func fullReset(){
        if let node = self.rootNode{
            node.removeFromParentNode()
        }
        alignmentSCNNodes = [SCNNode]()
        alignmentPoints = [CGPoint]()
        objects = [SharedARObject]()
        allConnectedDevices = [String]()
        state = .AlignmentStage
        userType = nil
    }
    
}

extension DataManager: ConnectivityManagerDelegate{
    
    func connectedDevicesChanged(manager: ConnectivityManager, connectedDevices: [String]) {
        print("--- Connected Devices Changed ---")
        var newDevices = [String]()
        for device in connectedDevices{
            if !self.allConnectedDevices.contains(device){
                newDevices.append(device)
            }
        }
        print("New Devices: \(newDevices)")
        if newDevices.count > 0{
            self.broadcastAlignmentPoints()
            for object in self.objects{
                self.sendObject(object: object)
                self.updateObject(object: object)
            }
        }
        self.allConnectedDevices  = connectedDevices
        DispatchQueue.main.async {
            self.delegate?.newDevicesConnected(devices: newDevices)
        }
    }
    
    func dataReceived(manager: ConnectivityManager, data: Data) {
        
        print("Received Data" )
        DispatchQueue.main.async {
            let object = NSKeyedUnarchiver.unarchiveObject(with: data)
            if let newAlignmentPoints = object as? [CGPoint]{
                if newAlignmentPoints != self.alignmentPoints{
                    self.alignmentPoints = newAlignmentPoints
                    self.delegate?.receivedAlignmentPoints(points: self.alignmentPoints)
                }
            }
            if let newObject = object as? SharedARObject{
                print("AR Object update received")
                self.updateObject(object: newObject)
                self.delegate?.receivedNewObject(object: newObject)
            }
            if let animationObject = object as? [String: Any], let nodeName = animationObject["name"] as? String, let transformValues = animationObject["transform"] as? [Float]{
//                print("received animation values \(SCNMatrix4.matrixFromFloatArray(transformValue: transformValues))")
                self.nodeAnimation(nodeName: nodeName, transform: SCNMatrix4.matrixFromFloatArray(transformValue: transformValues))
            }
        }
    }
}

extension DataManager{
    
    
    func initiateObjectStore(){
        solarSystemObjects = [SharedARObjectDescriptor]()
        chessObjects = [SharedARObjectDescriptor]()
        constructionObjects = [SharedARObjectDescriptor]()
        
        let stationaryPhysicsBody = SCNPhysicsBody.static()
        
         solarSystemObjects.append(SharedARObjectDescriptor(name: "Whole Solar System", physicsBody: stationaryPhysicsBody.copy() as! SCNPhysicsBody, transform: SCNMatrix4Identity, modelName: "SolarSystem_1", description: "The sun is the center of our solar system.  It is 109 times larger than Earth", multipleAllowed: false, animations: []))
        solarSystemObjects.append(SharedARObjectDescriptor(name: "Sun", physicsBody: stationaryPhysicsBody.copy() as! SCNPhysicsBody, transform: SCNMatrix4Identity, modelName: "SolarSystem_Sun", description: "The Sun is the center of our solar system.  It is 109 times larger than Earth", multipleAllowed: false, animations: []))
        solarSystemObjects.append(SharedARObjectDescriptor(name: "Mercury", physicsBody: stationaryPhysicsBody.copy() as! SCNPhysicsBody, transform: SCNMatrix4Identity, modelName: "SolarSystem_Mercury", description: "Mercury is made out of solid iron.  It is the closest to the sun", multipleAllowed: false, animations: []))
        solarSystemObjects.append(SharedARObjectDescriptor(name: "Venus", physicsBody: stationaryPhysicsBody.copy() as! SCNPhysicsBody, transform: SCNMatrix4Identity, modelName: "SolarSystem_Venus", description: "Venus is the brightest planet in our sky.", multipleAllowed: false, animations: []))
        solarSystemObjects.append(SharedARObjectDescriptor(name: "Earth", physicsBody: stationaryPhysicsBody.copy() as! SCNPhysicsBody, transform: SCNMatrix4Identity, modelName: "SolarSystem_Earth", description: "Earth is our home.  It has life and water", multipleAllowed: false, animations: []))
        solarSystemObjects.append(SharedARObjectDescriptor(name: "Mars", physicsBody: stationaryPhysicsBody.copy() as! SCNPhysicsBody, transform: SCNMatrix4Identity, modelName: "SolarSystem_Mars", description: "Mars has the largest volcano in our solar system. Elon Musk may try to live there!", multipleAllowed: false, animations: []))
        solarSystemObjects.append(SharedARObjectDescriptor(name: "Jupiter", physicsBody: stationaryPhysicsBody.copy() as! SCNPhysicsBody, transform: SCNMatrix4Identity, modelName: "SolarSystem_Jupiter", description: "Jupiter is the largest planet in our solar system.  A day on Jupiter is only 10 hours long!", multipleAllowed: false, animations: []))
        solarSystemObjects.append(SharedARObjectDescriptor(name: "Saturn", physicsBody: stationaryPhysicsBody.copy() as! SCNPhysicsBody, transform: SCNMatrix4Identity, modelName: "SolarSystem_Saturn", description: "Saturn is the lightest planet.  It has rings that are 30 feet thick", multipleAllowed: false, animations: []))
        solarSystemObjects.append(SharedARObjectDescriptor(name: "Uranus", physicsBody: stationaryPhysicsBody.copy() as! SCNPhysicsBody, transform: SCNMatrix4Identity, modelName: "SolarSystem_Uranus", description: "Uranus is on a tilted orbit.  It has rings like Saturn too!", multipleAllowed: false, animations: []))
        solarSystemObjects.append(SharedARObjectDescriptor(name: "Neptune", physicsBody: stationaryPhysicsBody.copy() as! SCNPhysicsBody, transform: SCNMatrix4Identity, modelName: "SolarSystem_Neptune", description: "A year on Neptune is 165 years on Earth!", multipleAllowed: false, animations: []))
        solarSystemObjects.append(SharedARObjectDescriptor(name: "Pluto", physicsBody: stationaryPhysicsBody.copy() as! SCNPhysicsBody, transform: SCNMatrix4Identity, modelName: "SolarSystem_Pluto", description: "The smallest dwarf planet in our solar system.", multipleAllowed: false, animations: []))
      
        // Chess
        let chessphysics = SCNPhysicsBody.static()
        chessObjects.append(SharedARObjectDescriptor(name: "Chess Board", physicsBody: chessphysics.copy() as! SCNPhysicsBody, transform: SCNMatrix4Identity, modelName: "ChessMatch", description: "Play chess with your friends!!", multipleAllowed: false, animations: []))
      
        // Blocks
        let cubeGeometry = SCNBox(width: 0.09, height: 0.09, length: 0.09, chamferRadius: 0.0)
        let physicsShape = SCNPhysicsShape(geometry: cubeGeometry, options:nil)
        var physics = SCNPhysicsBody(type: .dynamic, shape: physicsShape)
        physics.mass = 0.5
        physics.restitution = 0.4
        

        
        constructionObjects.append(SharedARObjectDescriptor(name: "Wood", physicsBody: physics.copy() as! SCNPhysicsBody, transform: SCNMatrix4Identity, modelName: "Block_Wood", description: "", multipleAllowed: false,animations: []))
        constructionObjects.append(SharedARObjectDescriptor(name: "Metal", physicsBody: physics.copy() as! SCNPhysicsBody, transform: SCNMatrix4Identity, modelName: "Block_Metal", description: "", multipleAllowed: false, animations: []))
        constructionObjects.append(SharedARObjectDescriptor(name: "Rubber", physicsBody: physics.copy() as! SCNPhysicsBody, transform: SCNMatrix4Identity, modelName: "Block_Rubber", description: "", multipleAllowed: false,  animations: []))
        solarSystemObjects.append(SharedARObjectDescriptor(name: "Candle", physicsBody: stationaryPhysicsBody.copy() as! SCNPhysicsBody, transform: SCNMatrix4Identity, modelName: "candle", description: "A candle for play", multipleAllowed: false, animations: []))
        solarSystemObjects.append(SharedARObjectDescriptor(name: "Cup", physicsBody: stationaryPhysicsBody.copy() as! SCNPhysicsBody, transform: SCNMatrix4Identity, modelName: "cup", description: "Why not a cup?", multipleAllowed: false, animations: []))
        solarSystemObjects.append(SharedARObjectDescriptor(name: "Chair", physicsBody: stationaryPhysicsBody.copy() as! SCNPhysicsBody, transform: SCNMatrix4Identity, modelName: "chair", description: "Why not a chair?", multipleAllowed: false, animations: []))
        solarSystemObjects.append(SharedARObjectDescriptor(name: "Lamp", physicsBody: stationaryPhysicsBody.copy() as! SCNPhysicsBody, transform: SCNMatrix4Identity, modelName: "lamp", description: "Why not a lamp?", multipleAllowed: false, animations: []))
        
        
    }
}


extension CAAnimation {
	class func animation(withSceneName name: String) -> CAAnimation {
		guard let scene = SCNScene(named: name) else {
			fatalError("Failed to find scene with name \(name).")
		}
		
		var animation: CAAnimation?
		scene.rootNode.enumerateChildNodes { (child, stop) in
			guard let firstKey = child.animationKeys.first else { return }
			animation = child.animation(forKey: firstKey)
			stop.initialize(to: true)
		}
		
		guard let foundAnimation = animation else {
			fatalError("Failed to find animation named \(name).")
		}
		
		foundAnimation.fadeInDuration = 0.3
		foundAnimation.fadeOutDuration = 0.3
		foundAnimation.repeatCount = 1
		
		return foundAnimation
	}
}

