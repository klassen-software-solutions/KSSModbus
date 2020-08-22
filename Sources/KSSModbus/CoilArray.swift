//
//  CoilArray.swift
//  
//
//  Created by Steven W. Klassen on 2020-09-22.
//

import Foundation

// This code is heavily influenced by code found at https://github.com/dduan/BitArray, but has
// been modified to fit the needs of the modbus classes.

/**
 Space efficient representation of boolean data

 This class handles access to both the coils and the discrete inputs. It provides an array-like wrapper around
 the underlying byte array provided the the `libmodbus` C API. Typically you do not create these objects.
 Instead they are created for your by the `ModbusServer` class and passed to you at the appropriate times.

 - note: This is a fixed size array. You can read and modify the values, but you cannot remove or add more.

 - note: This is a class instead of a struct so that it is passed by reference into the handler.

 - note: The indices of this array refer to the MODBUS addresses of the underlying data. This means that
 it is 0-based (i.e. index 0 refers to coil 00001 or to discrete input 10001). However it also takes into account
 the starting index. So if you are providing, for example, discrete inputs at the addresses 10100 to 10109, this class would
 represent the 10 coils using the indices from 100 (for the starting input of 10101) to 109.

 - warning: The raw C pointer that is the basis for the storage must remain valid through the life cycle of
 this instance. You generally don't have to worry about that as it is handled by the `ModbusServer` code.
 But it does mean that you should not copy or reference this class outside of the scope in which it is provided
 to you.
 */
public final class CoilArray: RandomAccessCollection {
    /// The number of coils represented in this array.
    public let count: Int

    /// Returns true if there are no coils in this array.
    public var isEmpty: Bool { count == 0 }

    /// Returns the first index in this array. Note that this is not necessarily zero.
    public var startIndex: Int

    /// Returns one past the last valid index in this array.
    public var endIndex: Int { startIndex + count }

    let raw: UnsafeMutablePointer<UInt8>!

    init(_ startingRegister: Int32, _ count: Int32, _ raw: UnsafeMutablePointer<UInt8>?) {
        precondition(startingRegister >= 0 && startingRegister < 10000)
        precondition(count >= 0)
        precondition((startingRegister + count) <= 10000)

        if raw == nil {
            self.startIndex = 0
            self.count = 0
            self.raw = nil
        } else {
            self.startIndex = Int(startingRegister)
            self.count = Int(count)
            self.raw = raw
        }
    }

    /// Get/set a coil via a subscript. Note that this does not validate the index.
    public subscript(index: Int) -> Bool {
        get {
            let idx = index - startIndex
            let (byteCount, bitPosition) = idx.quotientAndRemainder(dividingBy: 8)
            return self.raw[byteCount] & self.mask(for: bitPosition) > 0
        }

        set(newValue) {
            let idx = index - startIndex
            let (byteCount, bitPosition) = idx.quotientAndRemainder(dividingBy: 8)
            if newValue {
                self.raw[byteCount] |= self.mask(for: bitPosition)
            } else {
                self.raw[byteCount] &= ~self.mask(for: bitPosition)
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
    public func validatingGet(at index: Int) throws -> Bool {
        try validate(index: index)
        return self[index]
    }

    /// Performs the index validation and then sets the value at the index.
    /// - throws: Any exception thrown by `validate(index:)`
    public func validatingSet(_ value: Bool, at index: Int) throws {
        try validate(index: index)
        self[index] = value
    }
}

// MARK: Private Implementation

extension CoilArray: CustomStringConvertible {
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

fileprivate extension CoilArray {
    @inline(__always)
    private func mask(for index: Int) -> UInt8 {
        switch index {
        case 0: return 0b00000001
        case 1: return 0b00000010
        case 2: return 0b00000100
        case 3: return 0b00001000
        case 4: return 0b00010000
        case 5: return 0b00100000
        case 6: return 0b01000000
        case 7: return 0b10000000
        default:
            fatalError("expected 0-7, got \(index)")
        }
    }
}
