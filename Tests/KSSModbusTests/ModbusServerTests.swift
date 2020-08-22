//
//  ModbusServerTests.swift
//  
//
//  Created by Steven W. Klassen on 2020-08-22.
//

import Foundation
import KSSTest
import XCTest

@testable import CModbus
@testable import KSSModbus


final class ModbusServerTests: XCTestCase {
    func testManually() throws {
        // This "test" starts a modbus server for playing purposes. Enable the test
        // and run it when you need it, but don't check it in with this test enabled
        // as this test contains an infinite loop.
        try XCTSkipIf(true)

        var mbus: ModbusServer!
        do {
            mbus = try ModbusServer(onHostAddress: "127.0.0.1", onPort: 1502
                                    //, withAttributes: [.libModbusDebugging]
            )
            mbus.delegate = TestDelegate()
            try mbus.start()
        } catch {
            print("!! error: \(error.localizedDescription)")
            return
        }

        while true {
            sleep(10)
            print("!! waiting...")
            mbus.async { addressSpace in
                let counter = addressSpace.inputRegisters![0]
                addressSpace.inputRegisters![0] = counter + 1
                print("!!   incremented 1 to \(counter+1)")
            }
            mbus.sync { addressSpace in
                let counter = addressSpace.inputRegisters![1]
                addressSpace.inputRegisters![1] = counter + 1
                print("!!   incremented 2 to \(counter+1)")
            }
        }
    }

    func testTCPConstruction() throws {
        var sec: UInt32 = 0
        var usec: UInt32 = 0

        var mbus = try! ModbusServer()
        assertNotNil { mbus.conn.context }
        assertNil { mbus.conn.slaveId }
        assertEqual(to: 0.5) {
            modbus_get_response_timeout(mbus.conn.context, &sec, &usec)
            return toTimeInterval(seconds: sec, useconds: usec)
        }
        assertEqual(to: 0.5) {
            modbus_get_byte_timeout(mbus.conn.context, &sec, &usec)
            return toTimeInterval(seconds: sec, useconds: usec)
        }
        assertEqual(to: 0.0) {
            modbus_get_indication_timeout(mbus.conn.context, &sec, &usec)
            return toTimeInterval(seconds: sec, useconds: usec)
        }

        mbus = try! ModbusServer(withAttributes: [.responseTimeout(timeout: 1.5),
                                                  .byteTimeout(timeout: 2.5),
                                                  .indicationTimeout(timeout: 3.5)])
        assertNotNil { mbus.conn.context }
        assertNil { mbus.conn.slaveId }
        assertEqual(to: 1.5) {
            modbus_get_response_timeout(mbus.conn.context, &sec, &usec)
            return toTimeInterval(seconds: sec, useconds: usec)
        }
        assertEqual(to: 2.5) {
            modbus_get_byte_timeout(mbus.conn.context, &sec, &usec)
            return toTimeInterval(seconds: sec, useconds: usec)
        }
        assertEqual(to: 3.5) {
            modbus_get_indication_timeout(mbus.conn.context, &sec, &usec)
            return toTimeInterval(seconds: sec, useconds: usec)
        }

        assertThrowsError(ofValue: ModbusError.invalidArgument(description: "port must be positive")) {
            _ = try ModbusServer(onPort: -8)
        }
    }

//    func testRTUConstruction() {
//        var mbus = try! ModbusServer(2,
//                                     onDevice: "/dev/null",
//                                     withBaudRate: 9600,
//                                     andParity: .none,
//                                     andDataBits: .bits8,
//                                     andStopBits: .bits1)
//        assertNotNil { mbus.conn.context }
//        assertNil { mbus.conn.socket }
//        assertEqual(to: 2) { mbus.slaveId }
//        assertEqual(to: 0.5) { mbus.conn.responseTimeout }
//        assertEqual(to: 0.5) { mbus.conn.byteTimeout }
//        assertEqual(to: 0.0) { mbus.conn.indicationTimeout }
//
//        mbus = try! ModbusServer(2,
//                                 onDevice: "/dev/null",
//                                 withBaudRate: 9600,
//                                 andParity: .none,
//                                 andDataBits: .bits8,
//                                 andStopBits: .bits1,
//                                 andAttributes: [.responseTimeout(timeout: 1.5),
//                                                 .byteTimeout(timeout: 2.5),
//                                                 .indicationTimeout(timeout: 3.5)])
//        assertNotNil { mbus.conn.context }
//        assertNil { mbus.conn.socket }
//        assertEqual(to: 2) { mbus.slaveId }
//        assertEqual(to: 1.5) { mbus.conn.responseTimeout }
//        assertEqual(to: 2.5) { mbus.conn.byteTimeout }
//        assertEqual(to: 3.5) { mbus.conn.indicationTimeout }
//
//        assertThrowsError(ofType: ModbusError.Type.self) {
//            _ = try ModbusServer(2,
//                                 onDevice: "",
//                                 withBaudRate: 9600,
//                                 andParity: .odd,
//                                 andDataBits: .bits5,
//                                 andStopBits: .bits1)
//        }
//
//        assertThrowsError(ofValue: ModbusError.invalidArgument(description: "baud rate must be positive")) {
//            _ = try ModbusServer(2,
//                                 onDevice: "/dev/null",
//                                 withBaudRate: 0,
//                                 andParity: .odd,
//                                 andDataBits: .bits5,
//                                 andStopBits: .bits1)
//        }
//
//        assertThrowsError(ofValue: ModbusError.invalidArgument(description: "baud rate must be positive")) {
//            _ = try ModbusServer(2,
//                                 onDevice: "/dev/null",
//                                 withBaudRate: -3,
//                                 andParity: .odd,
//                                 andDataBits: .bits5,
//                                 andStopBits: .bits1)
//        }
//    }

}


// Will echo coil and holding registers to discrete inputs and input registers, respectively
struct TestDelegate: ModbusServerDelegate {
    var modbusServerAddressSpaceMeta: ModbusAddressSpaceMeta {
        ModbusAddressSpaceMeta(coils: .init(count: 10),
                               discreteInputs: .init(count: 10),
                               inputRegisters: .init(count: 10),
                               holdingRegisters: .init(count: 10))
    }

    func modbusServerHandleRequest(_ server: ModbusServer,
                                   _ function: ModbusConnection.Function,
                                   _ addressSpace: ModbusAddressSpace) throws
    {
        switch function {
        case .writeCoil(let address, let value):
            try addressSpace.discreteInputs!.validatingSet(value, at: address)
        case .writeCoils(let address, let values):
            print("!! address: \(address)")
            print("!! values.startIndex: \(values.startIndex)")
            assert(address == values.startIndex)
            try addressSpace.discreteInputs!.validate(index: values.startIndex)
            try addressSpace.discreteInputs!.validate(index: values.endIndex - 1)
            for addr in values.indices {
                addressSpace.discreteInputs![addr] = values[addr]
            }
        case .writeHoldingRegister(let address, let value):
            try addressSpace.inputRegisters!.validatingSet(value, at: address)
        case .writeHoldingRegisters(let address, let values):
            assert(address == values.startIndex)
            try addressSpace.inputRegisters!.validate(index: values.startIndex)
            try addressSpace.inputRegisters!.validate(index: values.endIndex - 1)
            for addr in values.indices {
                addressSpace.inputRegisters![addr] = values[addr]
            }
        default:
            break;
        }
    }
}
