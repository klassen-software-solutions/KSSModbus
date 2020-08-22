//
//  VersionTests.swift
//  
//
//  Created by Steven W. Klassen on 2020-08-22.
//

import CModbus
import Foundation
import KSSTest
import XCTest


final class VersionTests: XCTestCase {
    func testCLibModbusIsCompatible() {
        // If this test fails it means we have brought in a non-back-compatible change
        // to the C library. This implies that extra careful testing will be needed and
        // changes to our code are likely. Once we are happy with the change, this test
        // should be modified to match.
        assertTrue { libmodbus_version_major == 3 && libmodbus_version_minor >= 1 }
    }
}
