//
//  ViewController.swift
//  BLESmartCarWithARkitAndCoreML
//
//  Created by Andy W on 24/10/2018.
//  Copyright © 2018 Andy W. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import Vision
import CoreBluetooth

class ViewController: UIViewController, ARSCNViewDelegate, CBCentralManagerDelegate, CBPeripheralDelegate{
    
    private var planeNode: SCNNode?
    private var imageNode: SCNNode?
    private var animationInfo: AnimationInfo?
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var debugTextView: UITextView!
    @IBOutlet weak var textOverlay: UITextField!
    //BLE variables
    @IBOutlet weak var lblPeripheralName: UILabel!
    @IBOutlet weak var btnConnect: UIButton!
    @IBOutlet weak var btnDisconnect: UIButton!
    @IBOutlet weak var btnDiscoverPeripheral: UIButton!
    var manager : CBCentralManager!
    var myBluetoothPeripheral : CBPeripheral!
    var myCharacteristic : CBCharacteristic!
    var isMyPeripheralConected = false
    
    let dispatchQueueML = DispatchQueue(label: "com.hw.dispatchqueueml") // A Serial Queue
    var visionRequests = [VNRequest]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        //BLE Part
        initSetup()
        // --- ARKIT ---
        
        // Set the view's delegate
        sceneView.delegate = self
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true
        
        // Create a new scene
        let scene = SCNScene() // SCNScene(named: "art.scnassets/ship.scn")!
        
        // Set the scene to the view
        sceneView.scene = scene
        
        // --- ML & VISION ---
        
        // Setup Vision Model
        guard let selectedModel = try? VNCoreMLModel(for: gest5().model) else {
            fatalError("Could not load model. Ensure model has been drag and dropped (copied) to XCode Project. Also ensure the model is part of a target (see: https://stackoverflow.com/questions/45884085/model-is-not-part-of-any-target-add-the-model-to-a-target-to-enable-generation ")
        }
        
        // Set up Vision-CoreML Request
        let classificationRequest = VNCoreMLRequest(model: selectedModel, completionHandler: classificationCompleteHandler)
        classificationRequest.imageCropAndScaleOption = VNImageCropAndScaleOption.centerCrop // Crop from centre of images and scale to appropriate size.
        visionRequests = [classificationRequest]
        
        // Begin Loop to Update CoreML
        loopCoreMLUpdate()
    }
    
    //BLE components
    @IBAction func discoverPeripheral(_ sender: Any) {
        manager = CBCentralManager(delegate: self, queue: nil)
    }
    @IBAction func connect(_ sender: Any) {
        if manager !== nil {
            manager.connect(myBluetoothPeripheral, options: nil) //connect to my peripheral
        } else {
            btnConnect.isEnabled = false
        }
    }
    @IBAction func disconnect(_ sender: Any) {
        manager.cancelPeripheralConnection(myBluetoothPeripheral)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        var msg = ""
        switch central.state {
        case .poweredOff:
            msg = "Bluetooth is Off"
        case .poweredOn:
            msg = "Bluetooth is On"
            manager.scanForPeripherals(withServices: nil, options: nil)
        case .unsupported:
            msg = "Not Supported"
        default:
            msg = ""
        }
        print("STATE: " + msg)
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if peripheral.name == "HC-08" { //if is it my peripheral, then connect
            
            lblPeripheralName.isHidden = false
            lblPeripheralName.text = peripheral.name ?? "Default"
            
            self.myBluetoothPeripheral = peripheral     //save peripheral
            self.myBluetoothPeripheral.delegate = self
            manager.stopScan()                          //stop scanning for peripherals
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isMyPeripheralConected = true //when connected change to true
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        initSetup()
    }
    func initSetup(){
        initUI()
        initLogic()
    }
    func initUI(){
        btnDiscoverPeripheral.setTitle("Discocer Devices", for: .normal)
        lblPeripheralName.text = "Discovering..."
        btnConnect.setTitle("Connect", for: .normal)
        btnDisconnect.setTitle("Disconnected", for: .normal)
        btnDisconnect.isEnabled = false
        lblPeripheralName.isHidden = true
    }
    func initLogic(){
        isMyPeripheralConected = false //and to falso when disconnected
        if myBluetoothPeripheral != nil{
            if myBluetoothPeripheral.delegate != nil {
                myBluetoothPeripheral.delegate = nil
            }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let servicePeripheral = peripheral.services as [CBService]! { //get the services of the perifereal
            for service in servicePeripheral {
                //Look for the characteristics of the services
                print(service.uuid.uuidString)
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let characterArray = service.characteristics as [CBCharacteristic]! {
            for cc in characterArray {
                print(cc.uuid.uuidString)
                if(cc.uuid.uuidString == "FFE1") { //properties: read, write
                    myCharacteristic = cc //saved it to send data in another function.
                    updateUiOnSuccessfullConnectionAfterFoundCharacteristics()
                }
            }
        }
    }
    func updateUiOnSuccessfullConnectionAfterFoundCharacteristics(){
        btnConnect.setTitle("Connected", for: .normal)
        btnDisconnect.setTitle("Disconnect", for: .normal)
        btnDisconnect.isEnabled = true
    }
    
    //BLE Message delivery function
    func writeValue(onOff : String) {
        
        if isMyPeripheralConected { //check if myPeripheral is connected to send data
            let dataToSend: Data = onOff.data(using: String.Encoding.utf8)!
            myBluetoothPeripheral.writeValue(dataToSend, for: myCharacteristic, type: CBCharacteristicWriteType.withoutResponse)    //Writing the data to the peripheral
        } else {
            print("Not connected")
        }
    }
    
    //------------------------------------------------ viewController funcs and AI + AR part-------------------------------------------------
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        //AR tracking image goes here. Saved in AR Resources folder
        guard let referenceImages = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) else {
            fatalError("Missing expected tracking images")
        }
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        configuration.maximumNumberOfTrackedImages = 4
        // Add previously loaded images to ARScene configuration as detectionImages
        configuration.detectionImages = referenceImages
        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
    // MARK: - ARSCNViewDelegate, renderers
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async {
            // Do any desired updates to SceneKit here.
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let imageAnchor = anchor as? ARImageAnchor else {
            return
        }
        //1. Load plane scn
        let planeScene = SCNScene(named: "art.scnassets/plane.scn")!
        let planeNode = planeScene.rootNode.childNode(withName: "plane", recursively: true)!
        //2. Calculate size regarding planeNode's bounding box
        let (min, max) = planeNode.boundingBox
        let size = SCNVector3Make(max.x - min.x, max.y - min.y, max.z - min.z)
        //3. Calculate ratio difference between real image and object size
        let widthRatio = Float(imageAnchor.referenceImage.physicalSize.width)/size.x
        let heightRatio = Float(imageAnchor.referenceImage.physicalSize.height)/size.z
        //Using smallest difference ratio so that the object fits into the image
        let finalRatio = [widthRatio, heightRatio].min()!
        //4. Set transform from imageAnchor data
        planeNode.transform = SCNMatrix4(imageAnchor.transform)
        // 5. Animate appearance by scaling model from 0 to previously calculated value.
        let appearanceAction = SCNAction.scale(to: CGFloat(finalRatio), duration: 0.4)
        appearanceAction.timingMode = .easeOut
        // Set initial scale to 0.
        planeNode.scale = SCNVector3Make(0, 0, 0)
        // Add to root node.
        sceneView.scene.rootNode.addChildNode(planeNode)
        // Run the appearance animation.
        planeNode.runAction(appearanceAction)
        
        self.planeNode = planeNode
        self.imageNode = node
    }
    
    // MARK: - MACHINE LEARNING
    func loopCoreMLUpdate() {
        // Continuously run CoreML whenever it's ready. (Preventing 'hiccups' in Frame Rate)
        dispatchQueueML.async {
            // 1. Run Update.
            self.updateCoreML()
            // 2. Loop this function.
            self.loopCoreMLUpdate()
        }
    }
    
    func updateCoreML() {
        // Get Camera Image as RGB
        let pixbuff : CVPixelBuffer? = (sceneView.session.currentFrame?.capturedImage)
        if pixbuff == nil { return }
        let ciImage = CIImage(cvPixelBuffer: pixbuff!)
        
        // Prepare CoreML/Vision Request
        let imageRequestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        
        // Run Vision Image Request
        do {
            try imageRequestHandler.perform(self.visionRequests)
        } catch {
            print(error)
        }
    }
    
    func classificationCompleteHandler(request: VNRequest, error: Error?) {
        // Catch Errors
        if error != nil {
            print("Error: " + (error?.localizedDescription)!)
            return
        }
        guard let observations = request.results else {
            print("No results")
            return
        }
        
        // Get Classifications
        let classifications = observations[0...2] // top 3 results
            .flatMap({ $0 as? VNClassificationObservation })
            .map({ "\($0.identifier) \(String(format:" : %.2f", $0.confidence))" })
            .joined(separator: "\n")
        
        // Render Classifications
        DispatchQueue.main.async {
            // Display Debug Text on screen
            self.debugTextView.text = "TOP 3 PROBABILITIES: \n" + classifications
            
            // Display Top Symbol
            var symbol = "❎"
            let topPrediction = classifications.components(separatedBy: "\n")[0]
            let topPredictionName = topPrediction.components(separatedBy: ":")[0].trimmingCharacters(in: .whitespaces)
            // Only display a prediction if confidence is above 1%
            let topPredictionScore:Float? = Float(topPrediction.components(separatedBy: ":")[1].trimmingCharacters(in: .whitespaces))
            if (topPredictionScore != nil && topPredictionScore! > 0.01) {
                
                if (topPredictionName == "f") {
                    symbol = "⬆️"
                    self.writeValue(onOff: "f")
                }
                if (topPredictionName == "r") { symbol = "➡️"
                    self.writeValue(onOff: "r")
                }
                if (topPredictionName == "l") { symbol = "⬅️"
                    self.writeValue(onOff: "l")
                }
                if (topPredictionName == "s") { symbol = "⏹"
                    self.writeValue(onOff: "s")
                }
                if (topPredictionName == "b") { symbol = "⬇️"
                    self.writeValue(onOff: "b")
                }
                if (topPredictionName == "car") {
                    print("Car found")
                }
            }
            
            self.textOverlay.text = symbol
            
        }
        
    }
    
    // MARK: - HIDE STATUS BAR
    override var prefersStatusBarHidden : Bool { return true }
    
}
