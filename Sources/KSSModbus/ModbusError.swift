//
//  ModbusError.swift
//  
//
//  Created by Steven W. Klassen on 2020-08-21.
//

import CModbus
import Foundation
import Logging


/**
 Errors that may be reported from this library.
 */
public enum ModbusError: Error {
    /// Errors reported from the libmodbus C library. The `code` is the value of `errno` at the
    /// time of the error and `method` is the name of the C method that reported the error.
    case cLibModbusError(code: Int32, method: String)

    /// Errors reported from the `kqueue` and related methods. The `code` is the value of
    /// `errno` at the time of the error and `method` is the name of the C method that
    /// reported the error.
    case cLibKQueueError(code: Int32, method: String)

    /// An invalid argument was provided. `description` will give more details.
    case invalidArgument(description: String)

    /// An invalid state was detected. `description` will give more details.
    case invalidState(description: String)

    /// Errors that match a modbus exception code.
    case modbusException(exception: ModbusReplyException)
}

/**
 Exception codes used in the modbus protocol.
 */
public enum ModbusReplyException: UInt32 {
    /// Received function code is not valid
    case illegalFunction = 1

    /// The data address of one or more entities are not allowed or do not exist in the slave
    case illegalDataAddress = 2

    /// A data value is not accepted by the slave
    case illegalDataValue = 3

    /// Unrecoverable error occurred while the slave was attempting to perform the action
    case slaveDeviceFailure = 4

    /// The slave has accepted the request and is processing it, but it will take a long time to complete
    case acknowledge = 5

    /// The slave is busy. The master can try again later
    case slaveDeviceBusy = 6

    /// The slave cannot perform the programming function. This library also uses this to report an
    /// error that occurs that is not better described by the other exceptions in this list
    case negativeAcknowledge = 7

    /// The slave detected a parity error in the memory
    case memoryParityError = 8

    /// Indicates a misconfigured gateway (specific for modbus gateways)
    case gatewayPathUnavailable = 10

    /// The slave in a gateway does not respond (specific for modbus gateways)
    case gatewayTargetDeviceFailedToRespond = 11
}

// MARK: Private Implementation

extension ModbusError: LocalizedError {
    public var errorDescription: String? {
        var desc = "\(String(describing: type(of: self))).\(self)"
        if let extra = extra {
            desc.append(": \(extra)")
        }
        return desc
    }

    private var extra: String? {
        switch self {
        case .cLibModbusError(let code, _):
            return String(cString: modbus_strerror(code))
        case .cLibKQueueError(let code, _):
            return String(cString: strerror(code))
        case .modbusException(let exception):
            return descriptionFor(modbusReplyException: exception)
        case .invalidState, .invalidArgument:
            return nil
        }
    }

    // Note: these descriptions are taken from Wikipedia:
    // https://en.wikipedia.org/wiki/Modbus#Exception_responses
    private func descriptionFor(modbusReplyException exception : ModbusReplyException) -> String {
        switch exception {
        case .illegalFunction:
            return "Function code received in the query is not recognized or allowed by slave"
        case .illegalDataAddress:
            return "Data address of some or all the required entities are not allowed or do not exist in slave"
        case .illegalDataValue:
            return "Value is not accepted by slave"
        case .slaveDeviceFailure:
            return "Unrecoverable error occurred while slave was attempting to perform requested action"
        case .acknowledge:
            return "Slave has accepted request and is processing it, but a long duration of time is required"
        case .slaveDeviceBusy:
            return "Slave is engaged in processing a long-duration command"
        case .negativeAcknowledge:
            return "Slave cannot perform the programming functions"
        case .memoryParityError:
            return "Slave detected a parity error in memory"
        case .gatewayPathUnavailable:
            return "Specialized for Modbus gateways. Indicates a misconfigured gateway"
        case .gatewayTargetDeviceFailedToRespond:
            return "Specialized for Modbus gateways. Sent when slave fails to respond"
        }
    }
}

func cLibErrorMessage(for functionName: String) -> Logger.Message {
    let msg = ModbusError.cLibModbusError(code: errno, method: functionName).localizedDescription
    return Logger.Message("\(msg)")
}
