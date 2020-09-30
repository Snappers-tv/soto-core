//===----------------------------------------------------------------------===//
//
// This source file is part of the Soto for AWS open source project
//
// Copyright (c) 2017-2020 the Soto project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Soto project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import AsyncHTTPClient
import BaggageContext
import Logging
import NIO
@testable import SotoCore
import SotoTestUtils
import XCTest

class CredentialProviderTests: XCTestCase {
    func testCredentialProvider() {
        let cred = StaticCredential(accessKeyId: "abc", secretAccessKey: "123", sessionToken: "xyz")

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try group.syncShutdownGracefully()) }
        let loop = group.next()
        var returned: Credential?
        XCTAssertNoThrow(returned = try cred.getCredential(on: loop, context: TestEnvironment.context).wait())

        XCTAssertEqual(returned as? StaticCredential, cred)
    }

    // make sure getCredential in client CredentialProvider doesnt get called more than once
    func testDeferredCredentialProvider() {
        class MyCredentialProvider: CredentialProvider {
            var alreadyCalled = false
            func getCredential(on eventLoop: EventLoop, context: Context) -> EventLoopFuture<Credential> {
                if self.alreadyCalled == false {
                    self.alreadyCalled = true
                    return eventLoop.makeSucceededFuture(StaticCredential(accessKeyId: "ACCESSKEYID", secretAccessKey: "SECRETACCESSKET"))
                } else {
                    return eventLoop.makeFailedFuture(CredentialProviderError.noProvider)
                }
            }
        }
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
        let eventLoop = eventLoopGroup.next()
        let context = CredentialProviderFactory.InitContext(httpClient: httpClient, eventLoop: eventLoop, context: TestEnvironment.context)
        let deferredProvider = DeferredCredentialProvider(context: context, provider: MyCredentialProvider())
        XCTAssertNoThrow(_ = try deferredProvider.getCredential(on: eventLoop, context: TestEnvironment.context).wait())
        XCTAssertNoThrow(_ = try deferredProvider.getCredential(on: eventLoop, context: TestEnvironment.context).wait())
    }

    func testConfigFileSuccess() {
        let credentials = """
        [default]
        aws_access_key_id = AWSACCESSKEYID
        aws_secret_access_key = AWSSECRETACCESSKEY
        """
        let filename = "credentials"
        let filenameURL = URL(fileURLWithPath: filename)
        XCTAssertNoThrow(try Data(credentials.utf8).write(to: filenameURL))
        defer { XCTAssertNoThrow(try FileManager.default.removeItem(at: filenameURL)) }

        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let eventLoop = eventLoopGroup.next()
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoop))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
        let factory = CredentialProviderFactory.configFile(credentialsFilePath: filenameURL.path)

        let provider = factory.createProvider(context: .init(httpClient: httpClient, eventLoop: eventLoop, context: TestEnvironment.context))

        var credential: Credential?
        XCTAssertNoThrow(credential = try provider.getCredential(on: eventLoop, context: TestEnvironment.context).wait())
        XCTAssertEqual(credential?.accessKeyId, "AWSACCESSKEYID")
        XCTAssertEqual(credential?.secretAccessKey, "AWSSECRETACCESSKEY")
    }

    func testConfigFileNotAvailable() {
        let filename = "credentials_not_existing"
        let filenameURL = URL(fileURLWithPath: filename)

        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let eventLoop = eventLoopGroup.next()
        defer { XCTAssertNoThrow(try eventLoopGroup.syncShutdownGracefully()) }
        let httpClient = HTTPClient(eventLoopGroupProvider: .shared(eventLoop))
        defer { XCTAssertNoThrow(try httpClient.syncShutdown()) }
        let factory = CredentialProviderFactory.configFile(credentialsFilePath: filenameURL.path)

        let provider = factory.createProvider(context: .init(httpClient: httpClient, eventLoop: eventLoop, context: TestEnvironment.context))

        XCTAssertThrowsError(_ = try provider.getCredential(on: eventLoop, context: TestEnvironment.context).wait()) { error in
            print("\(error)")
            XCTAssertEqual(error as? CredentialProviderError, .noProvider)
        }
    }
}
