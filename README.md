# Govee BLE Observer (Swift)

This is a Swift implementation of the Govee BLE (Bluetooth Low Energy) observer that scans for Govee temperature/humidity sensors, outputs their readings in JSON format, and publishes them to an MQTT broker.

## Features

- Native CoreBluetooth integration 
- MQTT publishing with automatic reconnection
- Filters for Govee devices (GV5179 series)
- Parses temperature, humidity, and battery data
- Outputs JSON format compatible with the original D version
- Configurable via environment variables
- Clean shutdown handling
- macOS native application

## Requirements

- macOS 10.15+ (for CoreBluetooth)
- Swift 6.1+
- Bluetooth enabled
- Bluetooth permissions granted

## Building

```bash
swift build
```

## Configuration

The application can be configured using environment variables:

```bash
export MQTT_HOST="your-mqtt-broker.com"     # Default: localhost
export MQTT_PORT="1883"                     # Default: 1883
export MQTT_USERNAME="your-username"        # Optional
export MQTT_PASSWORD="your-password"        # Optional  
export MQTT_TOPIC="govee/sensors"          # Default: govee/sensors
export MQTT_CLIENT_ID="GoveeBLE-unique"    # Auto-generated if not set
```

## Running

### With default settings (localhost MQTT):
```bash
swift run
```

### With custom MQTT broker:
```bash
MQTT_HOST="mqtt.example.com" MQTT_USERNAME="user" MQTT_PASSWORD="pass" swift run
```

### Build and run the release executable:
```bash
swift build -c release
.build/release/GoveeBLE
```

## Code Structure

The Swift implementation is organized into several key parts:

### Data Structures
- `GoveeReading`: Struct representing sensor data with JSON output capability

### CoreBluetooth Integration
- `GoveeBLEScanner`: Main class handling BLE scanning
- Implements `CBCentralManagerDelegate` for BLE events

### Data Parsing
- `parseGoveeData()`: Extracts Govee data from manufacturer advertisement data
- `decodeGovee()`: Decodes raw bytes into temperature/humidity/battery values

## Swift vs D Implementation

This Swift version provides several advantages over the D version:

1. **Native CoreBluetooth**: No need for complex Objective-C bindings
2. **Better error handling**: Swift's optional types prevent null pointer issues
3. **Memory safety**: Automatic reference counting eliminates memory leaks
4. **Platform integration**: Native macOS app with proper permissions
5. **Easier deployment**: Single executable with no external dependencies

## Example Output

### Console Output:
```json
{"name":"GV5179-Test","temperature":23.5,"humidity":45.2,"battery":85}
```

### MQTT Topics:
Readings are published to individual topics per device:
- Topic: `govee/sensors/GV5179-ABC123`
- Payload: `{"name":"GV5179-ABC123","temperature":23.5,"humidity":45.2,"battery":85}`

### MQTT Message Structure:
- **QoS Level**: 0 (fire and forget)
- **Retained**: false
- **Topic Pattern**: `{MQTT_TOPIC}/{device_name}`
- **Payload**: JSON string with sensor data

## Permissions

The app will request Bluetooth permissions when first run. Make sure to grant these permissions for the scanner to work properly.

## Swift Concepts Used

For those new to Swift, this project demonstrates:

- **Classes and Structs**: Object-oriented programming with value/reference types
- **Protocols**: Swift's version of interfaces (CBCentralManagerDelegate)
- **Extensions**: Adding functionality to existing types
- **Optionals**: Safe handling of potentially nil values
- **Data Types**: Working with Data and UInt8 arrays
- **String Interpolation**: Building JSON strings
- **Delegates**: Callback pattern for BLE events
- **RunLoop**: Keeping the app alive for continuous scanning
- **DispatchQueue**: Background queues for BLE operations
- **Signal Handling**: Graceful shutdown with Ctrl+C

## Testing MQTT Connection

You can test the MQTT functionality using various MQTT tools:

### Using mosquitto_sub:
```bash
# Subscribe to all Govee topics
mosquitto_sub -h localhost -t "govee/sensors/+"

# Subscribe with authentication
mosquitto_sub -h mqtt.example.com -u username -P [REDACTED:password] -t "govee/sensors/+"
```

### Using MQTT Explorer:
1. Install [MQTT Explorer](http://mqtt-explorer.com/)
2. Connect to your MQTT broker
3. Subscribe to `govee/sensors/+` to see all device readings

## Troubleshooting

### Bluetooth Issues:
- Ensure Bluetooth is enabled in System Preferences
- Grant Bluetooth permissions when prompted
- Make sure no other apps are using Bluetooth extensively

### MQTT Issues:
- Check MQTT broker connectivity: `telnet your-broker 1883`
- Verify credentials if using authentication
- Check firewall settings for MQTT port (usually 1883 or 8883)
- Monitor MQTT broker logs for connection attempts

### No Govee Devices Found:
- Ensure Govee devices are powered on and advertising
- Check that devices are in range (typically <30 feet)
- Verify device names start with "GV5179" (other models may need code changes)
