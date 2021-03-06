import XCTest
@testable import PerfectNet
import PerfectThread

class PerfectNetTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        NetEvent.initialize()
    }
    
    func testClientServer() {
        
        let port = UInt16(6500)
        
        do {
            
            let server = NetTCP()
            let client = NetTCP()
            
            try server.bind(port: port, address: "127.0.0.1")
            server.listen()
            
            #if swift(>=3.0)
                let serverExpectation = self.expectation(withDescription: "server")
                let clientExpectation = self.expectation(withDescription: "client")
            #else
                let serverExpectation = self.expectationWithDescription("server")
                let clientExpectation = self.expectationWithDescription("client")
            #endif
            
            try server.accept(timeoutSeconds: NetEvent.noTimeout) {
                (inn: NetTCP?) -> () in
                guard let n = inn else {
                    XCTAssertNotNil(inn)
                    return
                }
                let b = [UInt8(1)]
                do {
                    n.write(bytes: b) {
                        sent in
                        
                        XCTAssertTrue(sent == 1)
                        
                        n.readBytesFully(count: 1, timeoutSeconds: 5.0) {
                            read in
                            XCTAssert(read != nil)
                            XCTAssert(read?.count == 1)
                        }
                        
                        serverExpectation.fulfill()
                    }
                }
            }
            
            try client.connect(address: "127.0.0.1", port: port, timeoutSeconds: 5) {
                (inn: NetTCP?) -> () in
                guard let n = inn else {
                    XCTAssertNotNil(inn)
                    return
                }
                let b = [UInt8(1)]
                do {
                    n.readBytesFully(count: 1, timeoutSeconds: 5.0) {
                        read in
                        
                        XCTAssert(read != nil)
                        XCTAssert(read!.count == 1)
                        
                        n.write(bytes: b) {
                            sent in
                            
                            XCTAssertTrue(sent == 1)
                            
                            clientExpectation.fulfill()
                        }
                    }
                }
            }
            #if swift(>=3.0)
                self.waitForExpectations(withTimeout: 10000, handler: {
                    _ in
                    server.close()
                    client.close()
                })
            #else
                self.waitForExpectationsWithTimeout(10000, handler: {
                _ in
                server.close()
                client.close()
                })
            #endif
            
        } catch PerfectNetError.NetworkError(let code, let msg) {
            XCTAssert(false, "Exception: \(code) \(msg)")
        } catch let e {
            XCTAssert(false, "Exception: \(e)")
        }
    }

    func testClientServerReadTimeout() {
        
        let port = UInt16(6500)
        
        do {
            
            let server = NetTCP()
            let client = NetTCP()
            
            try server.bind(port: port, address: "127.0.0.1")
            server.listen()
            
            #if swift(>=3.0)
                let serverExpectation = self.expectation(withDescription: "server")
                let clientExpectation = self.expectation(withDescription: "client")
            #else
                let serverExpectation = self.expectationWithDescription("server")
                let clientExpectation = self.expectationWithDescription("client")
            #endif
            
            try server.accept(timeoutSeconds: NetEvent.noTimeout) {
                (inn: NetTCP?) -> () in
                guard let _ = inn else {
                    XCTAssertNotNil(inn)
                    return
                }
                Threading.sleep(seconds: 5)
                serverExpectation.fulfill()
            }
            
            var once = false
            try client.connect(address: "127.0.0.1", port: port, timeoutSeconds: 5) {
                (inn: NetTCP?) -> () in
                guard let n = inn else {
                    XCTAssertNotNil(inn)
                    return
                }
                
                do {
                    n.readBytesFully(count: 1, timeoutSeconds: 2.0) {
                        read in
                        
                        XCTAssert(read == nil)
                        XCTAssert(once == false)
                        once = !once
                        Threading.sleep(seconds: 7)
                        XCTAssert(once == true)
                        clientExpectation.fulfill()
                    }
                }
            }
            
            #if swift(>=3.0)
                self.waitForExpectations(withTimeout: 10000, handler: {
                    _ in
                    server.close()
                    client.close()
                })
            #else
                self.waitForExpectationsWithTimeout(10000, handler: {
                _ in
                server.close()
                client.close()
                })
            #endif
            
        } catch PerfectNetError.NetworkError(let code, let msg) {
            XCTAssert(false, "Exception: \(code) \(msg)")
        } catch let e {
            XCTAssert(false, "Exception: \(e)")
        }
    }
    
    func testTCPSSLClient() {
        
        let address = "www.treefrog.ca"
        let requestString = [UInt8](("GET / HTTP/1.0\r\nHost: \(address)\r\n\r\n").utf8)
        let requestCount = requestString.count
        #if swift(>=3.0)
            let clientExpectation = self.expectation(withDescription: "client")
        #else
            let clientExpectation = self.expectationWithDescription("client")
        #endif
        let net = NetTCPSSL()
        
        let setOk = net.setDefaultVerifyPaths()
        XCTAssert(setOk, "Unable to setDefaultVerifyPaths \(net.sslErrorCode(resultCode: 1))")
        
        do {
            try net.connect(address: address, port: 443, timeoutSeconds: 5.0) {
                (net: NetTCP?) -> () in
                
                if let ssl = net as? NetTCPSSL {
                    
                    ssl.beginSSL {
                        (success: Bool) in
                        
                        XCTAssert(success, "Unable to begin SSL \(ssl.errorStr(forCode: Int32(ssl.errorCode())))")
                        if !success {
                            clientExpectation.fulfill()
                            return
                        }
                        
                        do {
                            let x509 = ssl.peerCertificate
                            XCTAssert(x509 != nil)
                            let peerKey = x509?.publicKeyBytes
                            XCTAssert(peerKey != nil && peerKey!.count > 0)
                        }
                        
                        ssl.write(bytes: requestString) {
                            (sent:Int) -> () in
                            
                            XCTAssert(sent == requestCount)
                            
                            ssl.readBytesFully(count: 1, timeoutSeconds: 5.0) {
                                (readBytes: [UInt8]?) -> () in
                                
                                XCTAssert(readBytes != nil && readBytes!.count > 0)
                                
                                var readBytesCpy = readBytes!
                                readBytesCpy.append(0)
                                let ptr = UnsafeMutablePointer<CChar>(readBytesCpy)
                                let s1 = String(validatingUTF8: ptr)!
                                
                                ssl.readSomeBytes(count: 4096) {
                                    (readBytes: [UInt8]?) -> () in
                                    
                                    XCTAssert(readBytes != nil && readBytes!.count > 0)
                                    
                                    var readBytesCpy = readBytes!
                                    readBytesCpy.append(0)
                                    let ptr = UnsafeMutablePointer<CChar>(readBytesCpy)
                                    let s2 = String(validatingUTF8: ptr)!
                                    
                                    let s = s1 + s2
                                    
                                    XCTAssert(s.characters.starts(with: "HTTP/1.1 200 OK".characters))
                                    
                                    clientExpectation.fulfill()
                                }
                            }
                        }
                    }
                } else {
                    XCTAssert(false, "Did not get NetTCPSSL back after connect")
                }
            }
        } catch {
            XCTAssert(false, "Exception thrown")
        }
        
        #if swift(>=3.0)
            self.waitForExpectations(withTimeout: 10000) {
                _ in
                net.close()
            }
        #else
            self.waitForExpectationsWithTimeout(10000) {
            (_: NSError?) in
            net.close()
            }
        #endif
    }
    
    static var allTests : [(String, (PerfectNetTests) -> () throws -> Void)] {
        return [
            ("testClientServer", testClientServer),
            ("testClientServerReadTimeout", testClientServerReadTimeout),
            ("testTCPSSLClient", testTCPSSLClient),
            
        ]
    }
}
