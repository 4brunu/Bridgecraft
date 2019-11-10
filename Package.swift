// swift-tools-version:4.2
//
//  Package.swift
//  Bridgecraft
//
//  The MIT License (MIT)
//
//  Copyright (c) 2018 Tamas Lustyik
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import PackageDescription

let package = Package(
    name: "Bridgecraft",
    products: [
        .executable(name: "bridgecraft", targets: ["Bridgecraft"]),
    ],
    dependencies: [
        .package(url: "https://github.com/kylef/Commander.git", from: "0.9.1"),
        .package(url: "https://github.com/jpsim/SourceKitten.git", from: "0.27.0"),
        .package(url: "https://github.com/tomlokhorst/XcodeEdit.git", from: "2.7.4"),
    ],
    targets: [
        .target(
            name: "Bridgecraft",
            dependencies: ["Commander", "SourceKittenFramework", "XcodeEdit"],
            path: "Bridgecraft"
        ),
    ],
    swiftLanguageVersions: [.v4, .v4_2]
)
