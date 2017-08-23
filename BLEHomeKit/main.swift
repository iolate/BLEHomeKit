//
//  main.swift
//  BLEHomeKit
//
//  Created by Seungho Kim on 2017. 3. 1..
//  Copyright © 2017 iolate. All rights reserved.
//

import Foundation
import CoreBluetooth
import SwiftSocket // https://github.com/swiftsocket/SwiftSocket

class BleAccessoryController: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var centralManager: CBCentralManager?
    var connectedPeripheral: CBPeripheral?
    var selectedCharacter: CBCharacteristic?
    
    var isPowered = false
    
    override init() {
        super.init()
        
        centralManager = CBCentralManager.init(delegate: self, queue: nil)
    }
    
    func accessory(_ power: Bool) {
        self.peripheralSendString(power ? "n" : "f")
    }
    
    //MARK: - CoreBluetooth
    func connectToPeripheral(_ peripheral: CBPeripheral) {
        if self.connectedPeripheral != nil {
            self.centralManager?.cancelPeripheralConnection(self.connectedPeripheral!)
        }
        self.connectedPeripheral = peripheral
        self.selectedCharacter = nil;
        self.centralManager?.connect(peripheral, options: nil)
    }
    //MARK: CentralManager
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices:[CBUUID.init(string: "ffe0")], options: nil);
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("Discovered", peripheral)
        if peripheral.name == "BLEHK" {
            self.centralManager?.stopScan()
            self.connectToPeripheral(peripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected!")
        
        peripheral.delegate = self
        peripheral.discoverServices([CBUUID.init(string: "ffe0")])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected!")
        
        self.connectedPeripheral = nil
        self.selectedCharacter = nil
        self.centralManager?.scanForPeripherals(withServices:[CBUUID.init(string: "ffe0")], options:nil)
    }
    
    //MARK: Peripheral
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service: CBService in peripheral.services! {
            peripheral.discoverCharacteristics([CBUUID.init(string: "ffe1")], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for character: CBCharacteristic in service.characteristics! {
            self.selectedCharacter = character
            peripheral.setNotifyValue(true, for: character)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let received = String.init(data: characteristic.value!, encoding: .utf8)
        
        if received == "n" {
            self.isPowered = true
        }else if received == "f" {
            self.isPowered = false
        }
        
        //print("Power changed:", self.isPowered ? "true" : "false")
    }
    
    func peripheralSendString(_ str: String) {
        if self.connectedPeripheral == nil || self.selectedCharacter == nil {
            return
        }
        
        self.connectedPeripheral?.writeValue(str.data(using: .utf8)!, for: self.selectedCharacter!, type: .withoutResponse)
    }
}


//MARK: -
let accessoryController = BleAccessoryController.init()
let queue = DispatchQueue(label: "kr.iolate.tcpserver.queue")

//MARK: TCPServer
func tcpResponse(client: TCPClient) {
    let data = client.read(1)
    let received = String.init(bytes: data!, encoding: .utf8)
    if received == "n" {
        accessoryController.accessory(true)
        _ = client.send(data: "n".data(using: .utf8)!)
    } else if received == "f" {
        accessoryController.accessory(false)
        _ = client.send(data: "f".data(using: .utf8)!)
    } else if received == "o" {
        if accessoryController.isPowered {
            _ = client.send(data: "n".data(using: .utf8)!)
        }else {
            _ = client.send(data: "f".data(using: .utf8)!)
        }
    } else {
        _ = client.send(data: "?".data(using: .utf8)!)
    }
    client.close()
}

func tcpServer() {
    let server = TCPServer(address: "127.0.0.1", port: 7101)
    switch server.listen() {
    case .success:
        while true {
            if let client = server.accept() {
                tcpResponse(client: client)
            }
        }
    case .failure(let error):
        print(error)
    }
}

queue.async {
    while true {
        print("TCPServer start!")
        tcpServer()
        print("TCPServer ended.")
    }
}

//MARK: -
RunLoop.main.run()
