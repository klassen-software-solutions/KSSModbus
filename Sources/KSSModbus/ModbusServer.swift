//
//  ModbusServer.swift
//  
//
//  Created by Steven W. Klassen on 2020-08-22.
//

import CModbus
import Foundation
import Logging


/**
 Implementation of a modbus server

 This class provides a simple API for writing a MODBUS server. (Also often called a Modbus Slave or
 Modbus Device). It handles most client requests automatically with a delegate used to add your
 custom business logic.
 */
public class ModbusServer {
    let mappingQueue = DispatchQueue(label: "KSSModbus.mapping.queue")
    var mapping: UnsafeMutablePointer<modbus_mapping_t>? = nil
    let logger = Logger(label: "KSSModbus.ModbusServer")

    /**
     Worker function

     This is the type of the lambda passed into the `async` and `sync` methods. It will be passed
     the address space providing access to the underlying coils, discrete inputs, and registers.

     - warning: The `addressSpace` provides a safe but temporary access to the underlying C
     memory of the modbus library. It is only guaranteed to be valid within the scope of the worker
     itself. If you copy the reference outside of the worker you risk at a minimum, corrupting the
     underlying data, and quite possibly core dumping the application.
     */
    public typealias Worker = (_ addressSpace: ModbusAddressSpace) -> Void

    /// The modbus connection
    public let conn: ModbusConnection

    /// The delegate used to add the specific business logic to the server.
    /// - note: This must be set before `start` is called and should not be changed while the
    /// server is running.
    public var delegate: ModbusServerDelegate! = nil

    /**
     Create a TCP based server

     - parameters:
        - hostAddress: The name or IP address on which the server will accept connections. If `nil` then
        connections will be allowed on any of the host's valid networks.
        - server: The name of the service, or the number of the port (as a string) on which the server will
        listen for connections.
        - attributes: Optional attributes that may be set when creating the server.
     - throws: A `ModbusError` if the server could not be created.
     */
    public init(onHostAddress hostAddress: String? = nil,
                onService service: String,
                withAttributes attributes: [ModbusConnection.Attributes] = [ModbusConnection.Attributes]()) throws
    {
        conn = try ModbusConnection(host: hostAddress ?? "",
                                    service: service,
                                    attributes: attributes)
    }

    /**
     Create a TCP based server

     This is a convenience initializer that takes a port number, converts it to a string, then calls the more
     general TCP based init method.
     */
    public convenience init(onHostAddress hostAddress: String? = nil,
                            onPort port: Int = 502,
                            withAttributes attributes: [ModbusConnection.Attributes] = [ModbusConnection.Attributes]()) throws
    {
        guard port > 0 else {
            throw ModbusError.invalidArgument(description: "port must be positive")
        }
        try self.init(onHostAddress: hostAddress, onService: "\(port)", withAttributes: attributes)
    }

    // RTU version
//    public init(_ slaveId: UInt8,
//                onDevice device: String,
//                withBaudRate baudRate: Int,
//                andParity parity: ModbusConnection.Parity,
//                andDataBits dataBits: ModbusConnection.DataBits,
//                andStopBits stopBits: ModbusConnection.StopBits,
//                andAttributes attributes: [ModbusConnection.Attributes] = [ModbusConnection.Attributes]()) throws
//    {
//        conn = try ModbusConnection(slaveId: slaveId, device: device, baudRate: baudRate,
//                                    parity: parity, dataBits: dataBits, stopBits: stopBits,
//                                    attributes: attributes)
//    }

    /**
     Starts running the service

     This starts the service in a background queue, then returns. At present the service will continue until the
     `ModbusServer` instance is cleaned up, but that may change in the near future. (We may add the ability
     to stop the service.

     - throws: A `ModbusError` if the service cannot be started.
     */
    public func start() throws {
        if delegate == nil {
            throw ModbusError.invalidState(description: "The delegate must be set before start is called")
        }

        if conn.service != nil {
            try startTcpService()
        } else {
            print("TODO: implement the RTU version")
        }
    }

    /**
     Performs an action that can access and set the coils, discrete inputs, and registers in a safe manner.
     Specifically this will run the given `worker` asynchronously on the necessary queue to allow safe
     access to the data, and will provide the `worker` will a reference to the underlying data objects.

     The purpose for this method is to allow your code to modify the state outside of a client request. To
     modify the state during a client request, you should implement the request handler portion of the
     delegate.
     */
    public func async(_ worker: @escaping Worker) {
        mappingQueue.async { [self] in
            let addressSpace = createAddressSpace()
            worker(addressSpace)
        }
    }

    /**
     Performs an action that can access and set the coils, discrete inputs, and registers in a safe manner.
     Specifically this will run the given `worker` synchronously on the necessary queue to allow safe
     access to the data, and will provide the `worker` will a reference to the underlying data objects.
     - note: Synchronous does not imply that the `worker` will run any faster than with `async`.
     It means that this method will block until the `worker` can be run.

     The purpose for this method is to allow your code to modify the state outside of a client request. To
     modify the state during a client request, you should implement the request handler portion of the
     delegate.
     */
    public func sync(_ worker: @escaping Worker) {
        mappingQueue.sync {
            let addressSpace = createAddressSpace()
            worker(addressSpace)
        }
    }

    deinit {
        if let mapping = mapping {
            modbus_mapping_free(mapping)
        }
    }
}

/**
 Defines a range of modbus data objects.
 - note: `startingIndex + count <= 10000` must be true
 */
public struct ModbusAddressRange {
    /// Starting index must be in the range 0-10000
    var startingIndex = 0

    /// Count must be in the range 0-10000
    var count = 0
}

/**
 Defines the address space that will need to be allocated for the server.
 - note: If a type is not set, it will default to a range of (0, 0) which indicates to the server that it should
 not be allocated.
 */
public struct ModbusAddressSpaceMeta {
    /// Coils are 1-bit objects that can be both read and written by both the client and the server.
    var coils: ModbusAddressRange

    /// Discrete inputs are 1-bit objects that can be read by the client (master), but only written by the server (slave/device).
    var discreteInputs: ModbusAddressRange

    /// Input registers are 16-bit values that can be read by the client (master), but only written by the server (slave/device).
    var inputRegisters: ModbusAddressRange

    /// Holding registers are 16-bit values that can be both read and written by both the client and the server.
    var holdingRegisters: ModbusAddressRange
}

/**
 The address space of the server

 This differs from `ModbusAddressSpaceMeta` in that the meta is the description used to create the space
 while this struct is used to provide a temporary access into the space. It is automatically created at the appropriate
 time and passed into the request handler and the worker objects.

 - warning: This is providing safe but temporary access into the underlying C data structure. It must only
 be used within the scope it is provided (either in the delegate request handler or in the worker objects). If you
 copy and access it outside of those scopes you risk corrupting the underlying data structure and possibly
 causing a core dump.
 */
public struct ModbusAddressSpace {
    /// Access to the coils
    var coils: CoilArray? = nil

    /// Access to the discrete inputs
    var discreteInputs: CoilArray? = nil

    /// Access to the input registers
    var inputRegisters: RegisterArray? = nil

    /// Access to the holding registers
    var holdingRegisters: RegisterArray? = nil
}

/**
 The server delegate

 This protocol is used to customize the behaviour of the server. At a minimum you must implement
 `modbusServerAddressSpaceMeta` in order to define the address space provided by the
 server. All the other items are optional.
 */
public protocol ModbusServerDelegate {
    /// This will be called as the service is started to define the allowable address space. It is
    /// the only required item of the protocol.
    var modbusServerAddressSpaceMeta : ModbusAddressSpaceMeta { get }

    /// By default the server will pass on to the handling code only the requests that write data.
    /// This greatly reduces the request processing calls since the regular polling of most clients
    /// will not be passed to the handler. But if this returns true, then read as well as write requests,
    /// will be passed on to the handler.
    var modbusServerProcessReadRequests : Bool { get }

    /// By default the server will pass on to the handling code only the requests to write data,
    /// or requests to read data if `modbusServerProcessReadRequests` is true.
    /// You can add the processing of the "other" requests by setting this value to return true.
    /// The "other" requests include things such as "mask write register", "get comm event counter",
    /// and other less used functions of the MODBUS protocol.
    var modbusServerProcessOtherRequests : Bool { get }

    /// The server will automatically handle requests by reading or writing the requested values
    /// and posting the correct response. If that is all you want, then you don't need to implement
    /// this method. This method exists to allow you to place your business logic between the
    /// receiving of the request and before the writing of the response.
    ///
    /// - note: After this method returns, the server will continue to post the correct response.
    /// If you do not want this to happen, your method should throw an error which will result
    /// in an error response. If your error is an instance of `ModbusError.modbusException` then
    /// that exception code will be the response. Otherwise, your exception will be logged locally
    /// and `ModbusReplyException.negativeAcknowledge` will be sent as the
    /// response.
    ///
    /// - note: Unless this method throws an exception, the modbus response code will
    /// process the incoming request, which will include writing the data in the request.
    ///
    /// - warning: The `addressSpace` is only guaranteed to be valid during this call.
    /// If you copy it out of this scope and attempt to use it, you risk corrupting the underlying
    /// data, and possibly core dumping your application.
    func modbusServerHandleRequest(_ server: ModbusServer,
                                   _ function: ModbusConnection.Function,
                                   _ addressSpace: ModbusAddressSpace) throws
}

/// -:nodoc:-
public extension ModbusServerDelegate {
    var modbusServerProcessReadRequests : Bool { false }
    var modbusServerProcessOtherRequests : Bool { false }
    func modbusServerHandleRequest(_ server: ModbusServer,
                                   _ function: ModbusConnection.Function,
                                   _ addressSpace: ModbusAddressSpace) throws {}
}


// MARK: Private Implementation

fileprivate extension ModbusServer {
    func getSocket() throws -> Int32 {
        let sock = modbus_get_socket(conn.context)
        guard sock != -1 else {
            throw ModbusError.cLibModbusError(code: errno, method: "modbus_get_socket")
        }
        return sock
    }

    func setSocket(_ sock: Int32) throws {
        if modbus_set_socket(conn.context, sock) == -1 {
            throw ModbusError.cLibModbusError(code: errno, method: "modbus_set_socket")
        }
    }

    // This is highly based on code from
    // https://rderik.com/blog/using-kernel-queues-kqueue-notifications-in-swift/
    func handleConnection(fd: Int32) {
        let sockKqueue = kqueue()
        if sockKqueue == -1 {
            let msg = ModbusError.cLibKQueueError(code: errno, method: "kqueue").localizedDescription
            fatalError("System corruption detected: \(msg)")
        }
        defer {
            close(sockKqueue)
        }

        // Create the kevent structure that sets up our kqueue to listen
        // for notifications
        var sockKevent = kevent(
            ident: UInt(fd),
            filter: Int16(EVFILT_READ),
            flags: UInt16(EV_ADD | EV_ENABLE),
            fflags: 0,
            data: 0,
            udata: nil
        )

        if kevent(sockKqueue, &sockKevent, 1, nil, 0, nil) == -1 {
            let msg = ModbusError.cLibKQueueError(code: errno, method: "kevent").localizedDescription
            fatalError("sock \(fd) System corruption detected: \(msg)")
        }

        var event = kevent()
        var shouldContinue = true
        let query = Query(connection: conn)
        while shouldContinue {
            logger.info("sock: \(fd) Waiting for kevent")
            let status = kevent(sockKqueue, nil, 0, &event, 1, nil)
            if  status == 0 {
                logger.info("sock: \(fd) Timeout waiting for kevent")
            } else if status == -1 {
                let msg = ModbusError.cLibKQueueError(code: errno, method: "kevent").localizedDescription
                fatalError("sock \(fd) System corruption detected: \(msg)")
            } else if status > 0 {
                if (event.flags & UInt16(EV_EOF)) == EV_EOF {
                    logger.info("sock: \(fd) Connection closed by client (kevent)")
                    break
                }
                mappingQueue.sync {
                    try! self.setSocket(fd)
                    shouldContinue = handleRequest(query)
                }
            } else {
                fatalError("sock: \(fd) Error reading kevent, something is corrupted")
            }
        }
        logger.info("sock: \(fd) Handler exiting")
    }

    func handleRequest(_ query: Query) -> Bool {
        let rc = modbus_receive(conn.context, query.raw)
        if rc > 0 {
            do {
                try query.setCount(rc)
                let function = try ModbusConnection.Function.fromQuery(query)
                if shouldProcessRequest(function) {
                    logger.info("Processing request: \(function)")
                    try delegate.modbusServerHandleRequest(self, function, createAddressSpace())
                } else {
                    logger.info("Received request: \(function)")
                }
                if modbus_reply(conn.context, query.raw, rc, mapping) == -1 {
                    throw ModbusError.cLibModbusError(code: errno, method: "modbus_reply")
                }
            } catch ModbusError.modbusException(let exception) {
                // Note: we intentionally do not log this since it is just being reported
                // back to the master, hence none of its information is lost.
                modbus_reply_exception(conn.context, query.raw, exception.rawValue)
            } catch {
                // Note: we log this since it will be translated to a .negativeAcknowledge
                // before being reported to the master, and we may need to go back
                // in the logs and trace the problem.
                logger.error("Could not handle request: \(error.localizedDescription)")
                modbus_reply_exception(conn.context,
                                       query.raw,
                                       ModbusReplyException.negativeAcknowledge.rawValue)
            }
        } else if rc == -1 {
            if let realSock = try? getSocket() {
                logger.info("sock: \(realSock) Connection closed by client (modbus_receive)")
            } else {
                logger.info("Connection closed by client (modbus_receive)")
            }
            return false    // Should not continue
        }
        return true
    }

    func createAddressSpace() -> ModbusAddressSpace {
        let p = mapping!.pointee
        var addressSpace = ModbusAddressSpace()
        if let coils = p.tab_bits {
            addressSpace.coils = CoilArray(p.start_bits, p.nb_bits, coils)
        }
        if let discreteInputs = p.tab_input_bits {
            addressSpace.discreteInputs = CoilArray(p.start_input_bits,
                                                    p.nb_input_bits,
                                                    discreteInputs)
        }
        if let registers = p.tab_input_registers {
            addressSpace.inputRegisters = RegisterArray(p.start_input_registers,
                                                        p.nb_input_registers,
                                                        registers)
        }
        if let registers = p.tab_registers {
            addressSpace.holdingRegisters = RegisterArray(p.start_registers,
                                                          p.nb_registers,
                                                          registers)
        }
        return addressSpace
    }

    func shouldProcessRequest(_ function: ModbusConnection.Function) -> Bool {
        switch function {
        case .writeCoil, .writeCoils, .writeHoldingRegister, .writeHoldingRegisters:
            return true
        case .readDiscreteInputs, .readCoils, .readInputRegisters, .readHoldingRegisters:
            return delegate.modbusServerProcessReadRequests
        case .other:
            return delegate.modbusServerProcessOtherRequests
        }
    }

    func startTcpService() throws {
        try setupMapping()

        // This doesn't seem to actually have any effect. So for now we will just give
        // it a small default.
        let maxConnections: Int32 = 2
        var sock = modbus_tcp_pi_listen(conn.context, maxConnections)
        guard sock != -1 else {
            throw ModbusError.cLibModbusError(code: errno, method: "modbus_tcp_listen")
        }

        DispatchQueue.global(qos: .background).async { [self] in
            logger.info("Listening on port/service \(conn.service!), socket \(sock)")

            do {
                while true {
                    logger.info("Waiting to accept a new connection on socket \(sock)")
                    let localSock = modbus_tcp_pi_accept(conn.context, &sock)
                    if localSock == -1 {
                        throw ModbusError.cLibModbusError(code: errno, method: "modbus_tcp_accept")
                    }

                    DispatchQueue.global(qos: .background).async { [self] in
                        logger.info("sock: \(localSock) Connection opened")
                        handleConnection(fd: localSock)
                    }
                }
            } catch {
                logger.error("Service failed, exiting. Error: \(error.localizedDescription)")
            }
        }
    }

    func setupMapping() throws {
        if let mapping = mapping {
            modbus_mapping_free(mapping)
        }
        let meta = delegate.modbusServerAddressSpaceMeta
        try verifyAddressRange(meta.coils, name: "coils")
        try verifyAddressRange(meta.discreteInputs, name: "discreteInputs")
        try verifyAddressRange(meta.inputRegisters, name: "inputRegisters")
        try verifyAddressRange(meta.holdingRegisters, name: "holdingRegisters")
        mapping = modbus_mapping_new_start_address(UInt32(meta.coils.startingIndex),
                                                   UInt32(meta.coils.count),
                                                   UInt32(meta.discreteInputs.startingIndex),
                                                   UInt32(meta.discreteInputs.count),
                                                   UInt32(meta.holdingRegisters.startingIndex),
                                                   UInt32(meta.holdingRegisters.count),
                                                   UInt32(meta.inputRegisters.startingIndex),
                                                   UInt32(meta.inputRegisters.count))
        if mapping == nil {
            throw ModbusError.cLibModbusError(code: ENOMEM, method: "modbus_mapping_new_start_address")
        }
    }

    func verifyAddressRange(_ range: ModbusAddressRange, name: String) throws {
        if range.startingIndex < 0 || range.startingIndex > 9999 {
            throw ModbusError.invalidArgument(description: "\(name).startingIndex must be in the range 0-9999")
        }
        let maxCount = 10000 - range.startingIndex
        if range.count < 0 || range.count > maxCount {
            throw ModbusError.invalidArgument(description: "\(name).count must be in the range 0-\(maxCount)")
        }
    }
}

fileprivate class Query {
    let headerLength: Int
    let raw = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(MODBUS_TCP_MAX_ADU_LENGTH))

    var maxIndex: Int {
        count - headerLength
    }

    var count: Int = 0 {
        willSet {
            precondition(newValue >= 0 && newValue <= MODBUS_TCP_MAX_ADU_LENGTH)
        }
    }

    init(connection conn: ModbusConnection) {
        let length = modbus_get_header_length(conn.context)
        guard length != -1 else {
            let error = ModbusError.cLibModbusError(code: errno, method: "modbus_get_header_length")
            fatalError("System corruption detected: \(error.localizedDescription)")
        }
        self.headerLength = Int(length)
    }

    func setCount(_ count: Int32) throws {
        guard count >= 0 && count <= MODBUS_TCP_MAX_ADU_LENGTH else {
            throw ModbusError.modbusException(exception: .illegalDataAddress)
        }
        self.count = Int(count)
    }

    func readUInt8(fromOffset offset: Int) throws -> UInt8 {
        guard offset >= 0 && offset < maxIndex else {
            throw ModbusError.modbusException(exception: .illegalDataAddress)
        }
        return raw[headerLength + offset]
    }

    func readUInt16(fromOffset offset: Int) throws -> UInt16 {
        guard offset >= 0 && (offset+1) < maxIndex else {
            throw ModbusError.modbusException(exception: .illegalDataAddress)
        }
        return readUInt16NoCheck(fromOffset: offset)
    }

    fileprivate func readUInt16NoCheck(fromOffset offset: Int) -> UInt16 {
        let msb = UInt16(raw[headerLength + offset])
        let lsb = UInt16(raw[headerLength + offset + 1])
        return (msb << 8) + lsb
    }

    func readBool(fromOffset offset: Int) throws -> Bool {
        let u16 = try readUInt16(fromOffset: offset)
        guard u16 == 0x00 || u16 == 0xff00 else {
            throw ModbusError.modbusException(exception: .illegalDataValue)
        }
        return u16 == 0xff00
    }
}

fileprivate extension ModbusConnection.Function {
    static func fromQuery(_ query: Query) throws -> Self {
        let code = try query.readUInt8(fromOffset: 0)
        switch code {
        case 1, 2, 3, 4:  // read coils, discrete inputs, holding registers, or input registers
            let address = Int(try query.readUInt16(fromOffset: 1))
            let count = Int(try query.readUInt16(fromOffset: 3))

            if code == 1 { return .readCoils(address: address, count: count) }
            else if code == 2 { return .readDiscreteInputs(address: address, count: count) }
            else if code == 3 { return .readHoldingRegisters(address: address, count: count) }
            else {
                assert(code == 4)
                return .readInputRegisters(address: address, count: count)
            }
        case 5:     // write single coil
            let address = Int(try query.readUInt16(fromOffset: 1))
            let value = try query.readBool(fromOffset: 3)
            return .writeCoil(address: address, value: value)
        case 15:    // write multiple coils
            let address = Int(try query.readUInt16(fromOffset: 1))
            let length = Int(try query.readUInt16(fromOffset: 3))
            let numberOfBytes = Int(try query.readUInt8(fromOffset: 5))
            guard numberOfBytes == (query.maxIndex - 6) else {
                throw ModbusError.modbusException(exception: .illegalDataValue)
            }
            let coils = CoilArray(Int32(address), Int32(length), query.raw + query.headerLength + 6)
            return .writeCoils(address: address, values: coils)
        case 6:     // write holding register
            let address = Int(try query.readUInt16(fromOffset: 1))
            let value = try query.readUInt16(fromOffset: 3)
            return .writeHoldingRegister(address: address, value: value)
        case 16:    // write holding registers
            let address = Int(try query.readUInt16(fromOffset: 1))
            let length = Int(try query.readUInt16(fromOffset: 3))
            let numberOfBytes = Int(try query.readUInt8(fromOffset: 5))
            guard numberOfBytes == (query.maxIndex - 6) else {
                throw ModbusError.modbusException(exception: .illegalDataValue)
            }
            guard numberOfBytes == length * 2 else {
                throw ModbusError.modbusException(exception: .illegalDataValue)
            }
            let voidPtr = OpaquePointer(query.raw + query.headerLength + 6)
            let u16Ptr = UnsafeMutablePointer<UInt16>(voidPtr)
            let registers = RegisterArray(Int32(address), Int32(length), u16Ptr, areBigEndian: true)
            return .writeHoldingRegisters(address: address, values: registers)
        default:
            return .other(functionCode: code)
        }
    }
}
