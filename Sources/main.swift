import Foundation
import CoreBluetooth
import CocoaMQTT

// MARK: - Configuration

struct MQTTConfig {
    let host: String
    let port: UInt16
    let username: String?
    let password: String?
    let topic: String
    let clientId: String
    
    static let `default` = MQTTConfig(
        host: "localhost",
        port: 1883,
        username: nil,
        password: nil,
        topic: "govee/sensors",
        clientId: "GoveeBLE-\(UUID().uuidString.prefix(8))"
    )
}

// MARK: - Data Structures

// Govee sensor reading - similar to the D struct
struct GoveeReading {
    let name: String
    let temperature: Float
    let humidity: Float
    let battery: UInt8
    
    // Convert to JSON string (like the D version)
    func toJSON() -> String {
        return """
        {"name":"\(name)","temperature":\(String(format: "%.1f", temperature)),"humidity":\(String(format: "%.1f", humidity)),"battery":\(battery)}
        """
    }
}

// MARK: - MQTT Client

class MQTTPublisher: NSObject {
    private var mqttClient: CocoaMQTT?
    private let config: MQTTConfig
    private var isConnected = false
    
    init(config: MQTTConfig = .default) {
        self.config = config
        super.init()
        setupMQTTClient()
    }
    
    private func setupMQTTClient() {
        mqttClient = CocoaMQTT(clientID: config.clientId, host: config.host, port: config.port)
        mqttClient?.username = config.username
        mqttClient?.password = config.password
        mqttClient?.delegate = self
        mqttClient?.keepAlive = 60
        mqttClient?.autoReconnect = true
        
        print("[MQTT] Configured client for \(config.host):\(config.port)")
    }
    
    func connect() {
        guard let client = mqttClient else { return }
        print("[MQTT] Connecting to \(config.host):\(config.port)...")
        _ = client.connect()
    }
    
    func disconnect() {
        mqttClient?.disconnect()
    }
    
    func publish(reading: GoveeReading) {
        guard isConnected, let client = mqttClient else {
            print("[MQTT] Not connected, cannot publish reading")
            return
        }
        
        let jsonData = reading.toJSON()
        let topic = "\(config.topic)/\(reading.name)"
        
        client.publish(topic, withString: jsonData, qos: .qos0)
        print("[MQTT] Published to \(topic): \(jsonData)")
    }
}

// MARK: - CocoaMQTTDelegate

extension MQTTPublisher: CocoaMQTTDelegate {
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        if ack == .accept {
            isConnected = true
            print("[MQTT] Connected successfully")
        } else {
            print("[MQTT] Connection failed with ack: \(ack)")
        }
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        // Message published successfully
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
        // Publish acknowledged
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        // We're only publishing, not subscribing
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
        // We're not subscribing to topics
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
        // We're not unsubscribing from topics
    }
    
    func mqttDidPing(_ mqtt: CocoaMQTT) {
        // Ping received
    }
    
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
        // Pong received
    }
    
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        isConnected = false
        if let error = err {
            print("[MQTT] Disconnected with error: \(error)")
        } else {
            print("[MQTT] Disconnected")
        }
    }
}

// MARK: - CoreBluetooth Scanner

class GoveeBLEScanner: NSObject {
    private var centralManager: CBCentralManager!
    private let queue = DispatchQueue(label: "govee.ble.queue")
    private let mqttPublisher: MQTTPublisher
    
    init(mqttConfig: MQTTConfig = .default) {
        self.mqttPublisher = MQTTPublisher(config: mqttConfig)
        super.init()
        // Initialize the central manager with our queue
        centralManager = CBCentralManager(delegate: self, queue: queue)
        // Connect to MQTT
        mqttPublisher.connect()
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("[BLE] Bluetooth not powered on")
            return
        }
        
        print("[BLE] Starting scan for Govee devices...")
        // Scan for all devices (nil services) with duplicate detection enabled
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }
    
    func stopScanning() {
        centralManager.stopScan()
        print("[BLE] Scan stopped")
    }
    
    func disconnect() {
        stopScanning()
        mqttPublisher.disconnect()
    }
}

// MARK: - CBCentralManagerDelegate

extension GoveeBLEScanner: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("[BLE] State updated: \(central.state.rawValue)")
        
        switch central.state {
        case .poweredOn:
            print("[BLE] Bluetooth is powered on")
            startScanning()
        case .poweredOff:
            print("[BLE] Bluetooth is powered off")
        case .unsupported:
            print("[BLE] Bluetooth is not supported on this device")
        case .unauthorized:
            print("[BLE] Bluetooth use is not authorized")
        case .resetting:
            print("[BLE] Bluetooth is resetting")
        case .unknown:
            print("[BLE] Bluetooth state is unknown")
        @unknown default:
            print("[BLE] Unknown Bluetooth state: \(central.state.rawValue)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, 
                       didDiscover peripheral: CBPeripheral, 
                       advertisementData: [String: Any], 
                       rssi RSSI: NSNumber) {
        
        // Get the device name
        let deviceName = peripheral.name ?? "Unknown"
        
        // Only process Govee devices (like the D version)
        guard deviceName.hasPrefix("GV5179") else {
            return
        }
        
        // Extract manufacturer data & publish
        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            if let goveeReading = parseGoveeData(manufacturerData, deviceName: deviceName) {
                mqttPublisher.publish(reading: goveeReading)
            }
        }
    }
}

// MARK: - Govee Data Parsing

// Parse Govee manufacturer data (ported from D version)
func parseGoveeData(_ data: Data, deviceName: String) -> GoveeReading? {
    guard data.count >= 8 else {
        return nil
    }
    
    // Convert Data to byte array for easier manipulation
    let bytes = [UInt8](data)
    
    return decodeGovee(bytes, name: deviceName)
}

// Decode Govee sensor data from raw bytes (ported from D version)
func decodeGovee(_ payload: [UInt8], name: String) -> GoveeReading? {
    guard payload.count >= 8 else {
        return nil
    }
    
    // Extract temperature and humidity (big-endian format)
    // This matches the D implementation: bigEndianToNative!int(payload[3 .. 7]) & 0x00FFFFFF
    let tempRaw = Int(payload[4]) << 16 | Int(payload[5]) << 8 | Int(payload[6])
    let humRaw = tempRaw % 1000
    let battery = payload[7]
    
    // Convert to actual values (matches D version calculation)
    let temperature = Float(tempRaw / 1000) / 10.0
    let humidity = Float(humRaw) / 10.0
    
    return GoveeReading(
        name: name,
        temperature: temperature,
        humidity: humidity,
        battery: battery
    )
}

// MARK: - Configuration Loading

func loadMQTTConfig() -> MQTTConfig {
    let env = ProcessInfo.processInfo.environment
    
    let host = env["MQTT_HOST"] ?? "localhost"
    let port = UInt16(env["MQTT_PORT"] ?? "1883") ?? 1883
    let username = env["MQTT_USERNAME"]
    let password = env["MQTT_PASSWORD"]
    let topic = env["MQTT_TOPIC"] ?? "govee/sensors"
    let clientId = env["MQTT_CLIENT_ID"] ?? "GoveeBLE-\(UUID().uuidString.prefix(8))"
    
    print("[Config] MQTT Host: \(host):\(port)")
    print("[Config] MQTT Topic: \(topic)")
    if username != nil {
        print("[Config] MQTT Username: \(username!)")
    }
    
    return MQTTConfig(
        host: host,
        port: port,
        username: username,
        password: password,
        topic: topic,
        clientId: String(clientId)
    )
}

// MARK: - Main Application

func main() {
    print("[BLE] Launching Govee BLE observer (Swift version with MQTT)")
    
    // Load MQTT configuration from environment
    let mqttConfig = loadMQTTConfig()
    let scanner = GoveeBLEScanner(mqttConfig: mqttConfig)
    
    // Setup signal handlers for clean shutdown
    let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    source.setEventHandler {
        print("\n[Main] Received interrupt signal, shutting down...")
        scanner.disconnect()
        exit(0)
    }
    source.resume()
    signal(SIGINT, SIG_IGN)
    
    print("[Main] Press Ctrl+C to stop scanning...")
    
    // Keep the scanner alive
    withExtendedLifetime(scanner) {
        // Keep the app running
        // In Swift, we use RunLoop to keep the app alive (like NSRunLoop in the D version)
        RunLoop.main.run()
    }
}

// Start the application
main()
