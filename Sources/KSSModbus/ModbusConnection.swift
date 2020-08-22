//
//  ModbusConnection.swift
//  
//
//  Created by Steven W. Klassen on 2020-08-22.
//

import CModbus
import Foundation
import Logging


/**
 Representation of a single modbus connection. Each modbus server will have exactly one of these and modbus
 clients (master) will have one or more.
 */
public class ModbusConnection {
    /// Returns true if this is a TCP/IP connection and false if it is a serial connection.
    public var isTcpConnection: Bool { service != nil }

    /// Name of the modbus service or port. This will be nil if it is a serial connection.
    public let service: String?

    /// ID of the slave. For a modbus service (slave) this will be its id. For a modbus client (master) this will
    /// be the id of the slave it is talking to. For a TCP service, this will be nil.
    public var slaveId: UInt8? {
        if isTcpConnection {
            return nil
        }

        errno = 6
        let slave = modbus_get_slave(context)
        if slave < 0 || slave > 255 {
            let msg = ModbusError.cLibModbusError(code: errno, method: "modbus_get_slave").localizedDescription
            fatalError("System corruption detected: \(msg)")
        }
        return UInt8(slave)
    }

    let context: OpaquePointer?
    let logger = Logger(label: "KSSModbus.ModbusConnection")
    static let slaveIdNotUsed: UInt8 = 255

    init(host: String, service: String, attributes: [Attributes] = [Attributes]()) throws {
        self.service = service
        context = modbus_new_tcp_pi(host.isEmpty ? nil : host, service)
        if context == nil {
            throw ModbusError.cLibModbusError(code: errno, method: "modbus_new_tcp_pi")
        }

        try postInit(withSlaveId: nil, andAttributes: attributes)
    }

//    init(slaveId: UInt8?,
//         device: String,
//         baudRate: Int,
//         parity: Parity,
//         dataBits: DataBits,
//         stopBits: StopBits,
//         attributes: [Attributes] = [Attributes]()) throws
//    {
//        guard baudRate > 0 else {
//            throw ModbusError.invalidArgument(description: "baud rate must be positive")
//        }
//        context = modbus_new_rtu(device, Int32(baudRate), parity.rawValue,
//                                 dataBits.rawValue, stopBits.rawValue)
//        try postInit(withSlaveId: slaveId, andAttributes: attributes)
//    }

    deinit {
        if context != nil {
            modbus_free(context)
        }
    }
}

public extension ModbusConnection {
    /// Attributes that may be specified when creating the connection.
    enum Attributes {
        /// Timeout interval used to wait for a response. The default value is 0.5 seconds.
        case responseTimeout(timeout: TimeInterval)

        /// Timeout interval between two consecutive bytes of a message. The default value is 0.5 seconds.
        case byteTimeout(timeout: TimeInterval)

        /// Timeout interval used by the server to wait for an indication from the client. The default value is 0 seconds
        /// signifying no timeout.
        case indicationTimeout(timeout: TimeInterval)

        /// Turn on the debug logging of the underlying C library. Note that this does not use the logger used by
        /// the rest of this library, hence there is no control over it other than to turn it on or off. By default it
        /// is off.
        case libModbusDebugging
    }

    /// Used to specify the parity of the serial connection.
    enum Parity: Int8 {
        /// No parity
        case none = 78  // 'N'

        /// Even parity
        case even = 69  // 'E'

        /// Odd parity
        case odd = 79   // 'O'
    }

    /// Used to specify the number of data bits in the serial connection.
    enum DataBits: Int32 {
        /// 5 bits
        case bits5 = 5

        /// 6 bits
        case bits6 = 6

        /// 7 bits
        case bits7 = 7

        /// 8 bits
        case bits8 = 8
    }

    /// Used to specify the number of stop bits in the serial connection.
    enum StopBits: Int32 {
        /// 1 stop bit
        case bits1 = 1

        /// 2 stop bits
        case bits2 = 2
    }

    /// Used to specify the function code of a modbus request. Note that in each of these the `address`
    /// parameter is the zero based version, leaving out the leading type digit. Hence, for example, the
    /// address of the first possible input register is address 0, not "30001". And so on for the other types.
    /// All the addresses must be from 0 to 9999.
    enum Function {
        /// Read multiple discrete inputs.
        case readDiscreteInputs(address: Int, count: Int)               // function code 2

        /// Read multiple coils.
        case readCoils(address: Int, count: Int)                        // function code 1

        /// Write a single coil.
        case writeCoil(address: Int, value: Bool)                       // function code 5

        /// Write multiple coils.
        /// - note: `values` will contain values of the coils to be written, not the entire address
        /// space of the server. In addition, `values.startIndex == address` will be true.
        case writeCoils(address: Int, values: CoilArray)                // function code 15

        /// Read multiple input registers.
        case readInputRegisters(address: Int, count: Int)               // function code 4

        /// Read multiple holding registers.
        case readHoldingRegisters(address: Int, count: Int)             // function code 3

        /// Write a single holding register.
        case writeHoldingRegister(address: Int, value: UInt16)          // function code 6

        /// Write multiple holding registers.
        /// - note: `values` will contain the values of the registers to be written, not the entire
        /// address space of the server. In addition, `values.startIndex == address` will
        /// be true.
        case writeHoldingRegisters(address: Int, values: RegisterArray) // function code 16

        /// Specifies some other modbus function not directly supported by our code. If you need to
        /// use these you will need to lookup the meaning of the function code and respond accordingly.
        /// But virtually all the time this will not be necessary as the underlying modbus code will be
        /// handling these values automatically.
        case other(functionCode: UInt8)
    }
}

// MARK: Private Implementation

fileprivate extension ModbusConnection {
    func postInit(withSlaveId slaveId: UInt8?, andAttributes attributes: [Attributes]) throws {
        let i32 = Int32(slaveId ?? ModbusConnection.slaveIdNotUsed)
        if modbus_set_slave(context, i32) == -1 {
            throw ModbusError.cLibModbusError(code: errno, method: "modbus_set_slave")
        }

        try setAttributes(attributes)
    }

    func setAttributes(_ attributes: [Attributes]) throws {
        for attribute in attributes {
            switch attribute {
            case .responseTimeout(let timeInterval):
                let t = toTimeout(timeInterval)
                if modbus_set_response_timeout(context, t.seconds, t.useconds) == -1 {
                    throw ModbusError.cLibModbusError(code: errno, method: "modbus_set_response_timeout")
                }
            case .byteTimeout(let timeInterval):
                let t = toTimeout(timeInterval)
                if modbus_set_byte_timeout(context, t.seconds, t.useconds) == -1 {
                    throw ModbusError.cLibModbusError(code: errno, method: "modbus_set_byte_timeout")
                }
            case .indicationTimeout(let timeInterval):
                let t = toTimeout(timeInterval)
                if modbus_set_indication_timeout(context, t.seconds, t.useconds) == -1 {
                    throw ModbusError.cLibModbusError(code: errno, method: "modbus_set_indication_timeout")
                }
            case .libModbusDebugging:
                if modbus_set_debug(context, 1) == -1 {
                    throw ModbusError.cLibModbusError(code: errno, method: "modbus_set_debug")
                }
            }
        }
    }
}

func toTimeInterval(seconds: UInt32, useconds: UInt32) -> Double {
    return Double(seconds) + (Double(useconds) / 1000000.0)
}

func toTimeout(_ interval: TimeInterval) -> (seconds: UInt32, useconds: UInt32) {
    let decimalPart: Double = interval.truncatingRemainder(dividingBy: 1)
    let integerPart: Double = interval.rounded(.towardZero)
    return (seconds: UInt32(integerPart), useconds: UInt32(decimalPart * 1000000.0))
}
