//
//  File.swift
//  
//
//  Created by Steven W. Klassen on 2020-09-22.
//

import Foundation
import KSSTest
import XCTest

@testable import KSSModbus


final class RegisterArrayTest: XCTestCase {
    var raw: UnsafeMutablePointer<UInt16>? = nil

    override func tearDown() {
        if let raw = raw {
            raw.deallocate()
            self.raw = nil
        }
    }

    func testBasicCreation() throws {
        let registers = RegisterArray(0, 10, createRawArray(ofLength: 10))
        assertEqual(to: 10) { registers.count }
        assertFalse { registers.isEmpty }
        assertNotNil { registers.registers }
        assertEqual(to: 0) { registers.startIndex }
        assertEqual(to: 10) { registers.endIndex }
        for register in registers {
            assertEqual(to: 0) { register }
        }

        for index in 0..<registers.count {
            registers[index] = UInt16(index)
        }

        for index in 0..<registers.count {
            assertEqual(to: UInt16(index)) { registers[index] }
        }

        assertEqual(to: 0) { registers.first }
        assertEqual(to: 9) { registers.last }

        assertNoThrow {
            try registers.validate(index: 5)
        }
        assertThrowsError(ofValue: ModbusError.modbusException(exception: .illegalDataAddress)) {
            try registers.validate(index: -1)
        }
        assertThrowsError(ofValue: ModbusError.modbusException(exception: .illegalDataAddress)) {
            try registers.validate(index: 10)
        }

        assertNoThrow {
            _ = try registers.validatingGet(at: 5)
        }
        assertThrowsError(ofValue: ModbusError.modbusException(exception: .illegalDataAddress)) {
            _ = try registers.validatingGet(at: -3)
        }
        assertThrowsError(ofValue: ModbusError.modbusException(exception: .illegalDataAddress)) {
            _ = try registers.validatingGet(at: 100)
        }

        assertNoThrow {
            try registers.validatingSet(UInt16(30), at: 5)
        }
        assertThrowsError(ofValue: ModbusError.modbusException(exception: .illegalDataAddress)) {
            try registers.validatingSet(UInt16(30), at: -100)
        }
        assertThrowsError(ofValue: ModbusError.modbusException(exception: .illegalDataAddress)) {
            try registers.validatingSet(UInt16(30), at: 208)
        }
        assertEqual(to: UInt16(30)) { registers[5] }
    }

    func testEmptyCreation() throws {
        let registers = RegisterArray(0, 0, nil)
        assertEqual(to: 0) { registers.count }
        assertTrue { registers.isEmpty }
        assertNil { registers.registers }
    }

    func testNonZeroStart() throws {
        let registers = RegisterArray(100, 10, createRawArray(ofLength: 10))
        assertEqual(to: 10) { registers.count }
        assertFalse { registers.isEmpty }
        assertNotNil { registers.registers }
        assertEqual(to: 100) { registers.startIndex }
        assertEqual(to: 110) { registers.endIndex }
        for register in registers {
            assertEqual(to: 0) { register }
        }

        registers[105] = UInt16(105)
        registers[100] = UInt16(100)

        assertEqual(to: UInt16(100)) { registers[100] }
        assertEqual(to: UInt16(105)) { registers[105] }

        assertNoThrow {
            try registers.validate(index: 105)
        }
        assertThrowsError(ofValue: ModbusError.modbusException(exception: .illegalDataAddress)) {
            try registers.validate(index: 99)
        }
        assertThrowsError(ofValue: ModbusError.modbusException(exception: .illegalDataAddress)) {
            try registers.validate(index: 110)
        }

        assertNoThrow {
            _ = try registers.validatingGet(at: 105)
        }
        assertThrowsError(ofValue: ModbusError.modbusException(exception: .illegalDataAddress)) {
            _ = try registers.validatingGet(at: 18)
        }
        assertThrowsError(ofValue: ModbusError.modbusException(exception: .illegalDataAddress)) {
            _ = try registers.validatingGet(at: 208)
        }

        assertNoThrow {
            try registers.validatingSet(UInt16(30), at: 105)
        }
        assertThrowsError(ofValue: ModbusError.modbusException(exception: .illegalDataAddress)) {
            try registers.validatingSet(UInt16(30), at: 98)
        }
        assertThrowsError(ofValue: ModbusError.modbusException(exception: .illegalDataAddress)) {
            try registers.validatingSet(UInt16(30), at: 112)
        }
        assertEqual(to: UInt16(30)) { registers[105] }
    }

    func testBigEndian() throws {
        let array = createRawArray(ofLength: 10)
        for i in 1...10 {
            array[i-1] = UInt16(i).bigEndian
        }

        let registers = RegisterArray(0, 10, array, areBigEndian: true)
        for i in 1...10 {
            assertEqual(to: UInt16(i)) { registers[i-1] }
        }
    }

    func createRawArray(ofLength count: Int) -> UnsafeMutablePointer<UInt16> {
        raw = UnsafeMutablePointer<UInt16>.allocate(capacity: count)
        memset(raw, 0, 2 * count)   // sizeof(UInt16) will be 2
        return raw!
    }
}
