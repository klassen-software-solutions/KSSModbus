//
//  RegisterArray.swift
//  
//
//  Created by Steven W. Klassen on 2020-09-22.
//

import Foundation


/**
 Space efficient representation of register data

 This class handles access to both the input and holding registers. It provides an array-like wrapper around
 the underlying pointers provided the the `libmodbus` C API. Typically you do not create these objects.
 Instead they are created for your by the `ModbusServer` class and passed to you at the appropriate times.

 - note: This is a fixed size array. You can read and modify the values, but you cannot remove or add more.

 - note: This is a class instead of a struct so that it is passed by reference into the handler.

 - note: The indices of this array refer to the MODBUS addresses of the underlying data. This means that
 it is 0-based (i.e. index 0 refers to input register 30001 or to holding register 40001). However it also takes into account
 the starting index. So if you are providing, for example, holding registers at the addresses 40100 to 40109, this class would
 represent the 10 coils using the indices from 100 (for register 40101) to 109.

 - warning: The raw C pointer that is the basis for the storage must remain valid through the life cycle of
 this instance. You generally don't have to worry about that as it is handled by the `ModbusServer` code.
 But it does mean that you should not copy or reference this class outside of the scope in which it is provided
 to you.
 */
public final class RegisterArray: RandomAccessCollection {
    /// The number of registers represented in this array
    public let count: Int

    /// True if there are no registers in this array
    public var isEmpty: Bool { count == 0 }

    /// The first index in the array. Note that this is not necessarily zero.
    public let startIndex: Int

    /// One past the last valid index in this array
    public var endIndex: Int { startIndex + count }

    // Why the byte swap? When accessing the data in the internal modbus storage,
    // it uses the native endian hence no byte swap is necessary. But when accessing
    // the register data in a modbus request, it is always given in a big endian
    // format. So if our architecture is not big endian, we need to byte swap.
    // This API handles that automatically so the developer using a `RegisterArray`
    // does not need to know the nature of the underlying data.
    let registers: UnsafeMutablePointer<UInt16>!
    let mustByteSwap: Bool

    init(_ startingRegister: Int32,
         _ count: Int32,
         _ registers: UnsafeMutablePointer<UInt16>?,
         areBigEndian: Bool = false)
    {
        precondition(startingRegister >= 0 && startingRegister < 10000)
        precondition(count >= 0)
        precondition((startingRegister + count) <= 10000)

        self.mustByteSwap = areBigEndian && !archIsBigEndian()
        if registers == nil {
            self.startIndex = 0
            self.count = 0
            self.registers = nil
        } else {
            self.startIndex = Int(startingRegister)
            self.count = Int(count)
            self.registers = registers
        }
    }

    /// Get/set a register via a subscript. Note that this does not validate the index.
    public subscript(index: Int) -> UInt16 {
        get {
            if mustByteSwap {
                return registers[index - startIndex].bigEndian
            } else {
                return registers[index - startIndex]
            }
        }
        set {
            if mustByteSwap {
                registers[index - startIndex] = newValue.bigEndian
            } else {
                registers[index - startIndex] = newValue
            }
        }
    }

    /// Validate that a given index can be passed into the subscript operator.
    /// - throws: A `ModbusError.modbusException(exception: .illegalDataAddress)`
    /// if the validation fails. In the `ModbusServer` code this will be caught and passed back to the
    /// client.
    public func validate(index: Int) throws {
        guard index >= startIndex && index < endIndex else {
            throw ModbusError.modbusException(exception: .illegalDataAddress)
        }
    }

    /// Performs the index validation and then returns the value at the index.
    /// - throws: Any exception thrown by `validate(index:)`
    public func validatingGet(at index: Int) throws -> UInt16 {
        try validate(index: index)
        return self[index]
    }

    /// Performs the index validation and then sets the value at the index.
    /// - throws: Any exception thrown by `validate(index:)`
    public func validatingSet(_ value: UInt16, at index: Int) throws {
        try validate(index: index)
        self[index] = value
    }
}

// MARK: Private Implementation

extension RegisterArray: CustomStringConvertible {
    public var description: String {
        let cutoff = 10
        if count <= cutoff {
            return Array(self).description
        } else {
            // Need to ensure we are not copying large arrays just for our logging.
            let slice = self[startIndex ..< startIndex.advanced(by: cutoff)]
            var s = Array(slice).description
            s.removeLast()
            s.append(", + \(count - cutoff) more]")
            return s
        }
    }
}

fileprivate func archIsBigEndian() -> Bool {
    let number: UInt32 = 0x12345678
    let converted = number.bigEndian
    return number == converted
}
