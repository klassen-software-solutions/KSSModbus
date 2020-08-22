//
//  CoilArrayTests.swift
//  
//
//  Created by Steven W. Klassen on 2020-09-23.
//

import XCTest
@testable import KSSModbus

class CoilArrayTests: XCTestCase {
    var raw: UnsafeMutablePointer<UInt8>? = nil

    override func tearDown() {
        if let raw = raw {
            raw.deallocate()
            self.raw = nil
        }
    }

    func testCreation() throws {
        var a = CoilArray(0, 5, createRawArray(ofLength: 1))
        assertEqual(to: 5) { a.count }
        assertFalse { a.isEmpty }
        assertEqual(to: 0) { a.startIndex }
        assertEqual(to: 5) { a.endIndex }

        a = CoilArray(10, 500, nil)
        assertEqual(to: 0) { a.count }
        assertTrue { a.isEmpty }
        assertEqual(to: 0) { a.startIndex }
        assertEqual(to: 0) { a.endIndex }
    }

    func testMutation() throws {
        assertEqual(to: [false, false, false, true, true]) {
            let a = CoilArray(0, 5, createRawArray(ofLength: 1))
            a[3] = true
            a[4] = true
            return Array(a)
        }
    }

    func testCountConsistency() throws {
        assertEqual(to: 17) {
            let a = CoilArray(0, 17, createRawArray(ofLength: 3))
            return a.count
        }
    }

    func testFillPattern() throws {
        let pattern: UInt8 = 0b11110101
        _ = createRawArray(ofLength: 2)
        raw![0] = pattern
        raw![1] = pattern

        assertEqual(to: [true, false, true]) {
            Array(CoilArray(0, 3, raw!))
        }

        assertEqual(to: [true, false, true, false, true, true, true, true]) {
            Array(CoilArray(0, 8, raw!))
        }

        assertEqual(to: [true, false, true, false, true, true, true, true, true, false, true, false, true]) {
            Array(CoilArray(0, 13, raw!))
        }

        assertEqual(to: [true, false, true, false, true, true, true, true, true, false, true, false, true, true, true, true]) {
            Array(CoilArray(0, 16, raw!))
        }
    }

    func testValidation() throws {
        let coils = CoilArray(0, 10, createRawArray(ofLength: 2))

        assertNoThrow {
            try coils.validate(index: 5)
        }
        assertThrowsError(ofValue: ModbusError.modbusException(exception: .illegalDataAddress)) {
            try coils.validate(index: -1)
        }
        assertThrowsError(ofValue: ModbusError.modbusException(exception: .illegalDataAddress)) {
            try coils.validate(index: 10)
        }

        assertNoThrow {
            _ = try coils.validatingGet(at: 5)
        }
        assertThrowsError(ofValue: ModbusError.modbusException(exception: .illegalDataAddress)) {
            _ = try coils.validatingGet(at: -3)
        }
        assertThrowsError(ofValue: ModbusError.modbusException(exception: .illegalDataAddress)) {
            _ = try coils.validatingGet(at: 100)
        }

        assertNoThrow {
            try coils.validatingSet(true, at: 5)
        }
        assertThrowsError(ofValue: ModbusError.modbusException(exception: .illegalDataAddress)) {
            try coils.validatingSet(true, at: -100)
        }
        assertThrowsError(ofValue: ModbusError.modbusException(exception: .illegalDataAddress)) {
            try coils.validatingSet(true, at: 208)
        }
        assertEqual(to: true) { coils[5] }
        assertEqual(to: UInt8(0b00100000)) { coils.raw[0] }
        assertEqual(to: UInt8(0)) { coils.raw[1] }
    }

    func testNonZeroStart() throws {
        let coils = CoilArray(100, 10, createRawArray(ofLength: 2))
        assertEqual(to: 10) { coils.count }
        assertFalse { coils.isEmpty }
        assertNotNil { coils.raw }
        assertEqual(to: 100) { coils.startIndex }
        assertEqual(to: 110) { coils.endIndex }
        for coil in coils {
            assertFalse { coil }
        }
        assertEqual(to: UInt8(0)) { coils.raw![0] }
        assertEqual(to: UInt8(0)) { coils.raw![1] }

        coils[105] = true
        coils[100] = true

        assertTrue { coils[100] }
        assertTrue { coils[105] }
        assertEqual(to: UInt8(0b00100001)) { coils.raw![0] }
        assertEqual(to: UInt8(0)) { coils.raw![1] }

        assertNoThrow {
            try coils.validate(index: 105)
        }
        assertThrowsError(ofValue: ModbusError.modbusException(exception: .illegalDataAddress)) {
            try coils.validate(index: 99)
        }
        assertThrowsError(ofValue: ModbusError.modbusException(exception: .illegalDataAddress)) {
            try coils.validate(index: 110)
        }

        assertNoThrow {
            _ = try coils.validatingGet(at: 105)
        }
        assertThrowsError(ofValue: ModbusError.modbusException(exception: .illegalDataAddress)) {
            _ = try coils.validatingGet(at: 18)
        }
        assertThrowsError(ofValue: ModbusError.modbusException(exception: .illegalDataAddress)) {
            _ = try coils.validatingGet(at: 208)
        }

        assertNoThrow {
            try coils.validatingSet(true, at: 109)
        }
        assertThrowsError(ofValue: ModbusError.modbusException(exception: .illegalDataAddress)) {
            try coils.validatingSet(true, at: 98)
        }
        assertThrowsError(ofValue: ModbusError.modbusException(exception: .illegalDataAddress)) {
            try coils.validatingSet(true, at: 112)
        }
        assertTrue { coils[109] }
        assertFalse { coils[112] }
        assertEqual(to: UInt8(0b00100001)) { coils.raw![0] }
        assertEqual(to: UInt8(0b00000010)) { coils.raw![1] }
    }

    func createRawArray(ofLength count: Int) -> UnsafeMutablePointer<UInt8> {
        raw = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        memset(raw, 0, count)   // sizeof(UInt8) will be 1
        return raw!
    }
}
