//
//  GenerateCommand.swift
//  Bridgecraft
//
//  Created by Tamas Lustyik on 2018. 01. 23..
//  Copyright © 2018. Tamas Lustyik. All rights reserved.
//

import Foundation
import SourceKittenFramework
import XcodeEditor

extension GenerateCommand {
    static func execute(assumeNonnull: Bool,
                        sdkOverride: [String],
                        destOverride: [String],
                        outputPath: [String],
                        origProjectPath: String,
                        targetName: String) {
        let cmd = GenerateCommand(assumeNonnull: assumeNonnull,
                                  sdkOverride: sdkOverride,
                                  destOverride: destOverride,
                                  outputPath: outputPath,
                                  origProjectPath: origProjectPath,
                                  targetName: targetName)
        cmd.run()
    }
}

struct GenerateCommand {
    private let origProjectURL: URL
    private let tempProjectURL: URL
    private let bridgingSourceURL: URL
    private let preprocessedURL: URL
    private let outputFileURL: URL?
    
    private let assumeNonnull: Bool
    private let sdkOverride: String?
    private let destOverride: String?
    private let targetName: String
    
    init(assumeNonnull: Bool,
         sdkOverride: [String],
         destOverride: [String],
         outputPath: [String],
         origProjectPath: String,
         targetName: String) {
        self.assumeNonnull = assumeNonnull
        self.sdkOverride = sdkOverride.first
        self.destOverride = destOverride.first
        self.targetName = targetName
        
        origProjectURL = URL(fileURLWithPath: origProjectPath)

        let seed = arc4random() % 100
        
        let projectFolderURL = origProjectURL.deletingLastPathComponent()
        bridgingSourceURL = projectFolderURL.appendingPathComponent("Bridging-\(seed).m")
        preprocessedURL = bridgingSourceURL.deletingPathExtension().appendingPathExtension("h")
        
        if let path = outputPath.first {
            outputFileURL = URL(fileURLWithPath: path)
        }
        else {
            outputFileURL = nil
        }
        
        let tempName = "\(origProjectURL.deletingPathExtension().lastPathComponent)-\(seed).\(origProjectURL.pathExtension)"
        tempProjectURL = origProjectURL.deletingLastPathComponent().appendingPathComponent(tempName)
    }
    
    private func run() {
        do {
            // make a copy of the project
            try cloneProject()
            
            // get bridging header
            let headerPath = try bridgingHeaderPath()
            
            // generate dummy.m
            try generateBridgingSource(withHeaderPath: headerPath)
            
            // add dummy.m to the scheme's target
            try addBridgingSourceToProject()
            
            // get relevant compiler flags
            let compilerFlags = try compilerFlagsForBridgingSource()
            
            // preprocess dummy.m
            try preprocessBridgingSource(withCompilerFlags: compilerFlags)
            
            if assumeNonnull {
                // add nullability annotations
                try fixNullability()
            }
            
            // generate interface with sourcekitten
            let interface = try generateSwiftInterface(withCompilerFlags: compilerFlags)
            
            // clean up
            cleanUp()
            
            // write results
            try writeGeneratedInterfaceToFile(interface: interface)
        }
        catch {
            // clean up
            cleanUp()
            exit(2)
        }
    }

    private func cloneProject() throws {
        do {
            if FileManager.default.fileExists(atPath: tempProjectURL.path) {
                try FileManager.default.removeItem(at: tempProjectURL)
            }
            try FileManager.default.copyItem(at: origProjectURL, to: tempProjectURL)
        }
        catch {
            printError("cannot clone project at \(origProjectURL.path) to \(tempProjectURL.path): \(error)")
            throw error
        }
    }
    
    private func bridgingHeaderPath() throws -> String {
        let output: String
        do {
            output = try shell("/usr/bin/xcodebuild", args: [
                "-showBuildSettings",
                "-project", tempProjectURL.path,
                "-target", targetName
            ])
        }
        catch {
            printError("cannot query build settings for \(tempProjectURL.path): \(error)")
            throw error
        }
        
        var headerPath: String? = nil
        
        output.enumerateLines { (line, stop) in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("SWIFT_OBJC_BRIDGING_HEADER = ") {
                headerPath = trimmed.split(separator: "=").last?.trimmingCharacters(in: .whitespaces)
                stop = true
            }
        }
        
        guard let headerPathUnwrapped = headerPath else {
            printError("bridging header setting not found in project")
            throw BridgecraftError.unknown
        }
        
        return headerPathUnwrapped
    }

    private func generateBridgingSource(withHeaderPath headerPath: String) throws {
        do {
            let source = "#import \"\(headerPath)\"\n"
            try source.write(to: bridgingSourceURL, atomically: false, encoding: .utf8)
        }
        catch {
            printError("cannot write bridging source at \(bridgingSourceURL.path): \(error)")
            throw error
        }
    }

    private func addBridgingSourceToProject() throws {
        guard let project = XCProject(filePath: tempProjectURL.path) else {
            printError("cannot load project at \(tempProjectURL.path)")
            throw BridgecraftError.unknown
        }
        
        let data: Data
        do {
            data = try Data(contentsOf: bridgingSourceURL, options: [])
        }
        catch {
            printError("cannot load bridging source at \(tempProjectURL.path): \(error)")
            throw error
        }
        
        let fileName = bridgingSourceURL.lastPathComponent
        let sourceFileDef = XCSourceFileDefinition(name: fileName,
                                                   data: data,
                                                   type: .SourceCodeObjC)
        
        let group = project.mainGroup()
        group?.addSourceFile(sourceFileDef)
        
        guard let sourceFile = project.file(withName: fileName) else {
            printError("cannot add source file to project")
            throw BridgecraftError.unknown
        }
        
        guard let target = project.target(withName: targetName) else {
            printError("cannot find target \(targetName)")
            throw BridgecraftError.unknown
        }
        target.addMember(sourceFile)
        
        project.save()
    }
    
    private func compilerFlagsForBridgingSource() throws -> [String] {
        var args = [
            "clean", "build", "-n",
            "-project", tempProjectURL.path,
            "-target", targetName
        ]
        
        if let sdk = sdkOverride {
            args += ["-sdk", sdk]
        }
        
        if let dest = destOverride {
            args += ["-destination", dest]
        }
        
        let output: String
        do {
            output = try shell("/usr/bin/xcodebuild", args: args)
        }
        catch {
            printError("cannot dry-run build for \(tempProjectURL.path)")
            throw error
        }
        
        let pattern = "-c \(bridgingSourceURL.resolvingSymlinksInPath().path)"
        var compilerFlags: [String]? = nil
        
        let gluedPrefixes = ["-I", "-D", "-F", "-mmacosx-version-min"]
        let splitPrefixes = ["-iquote", "-arch", "-isysroot"]
        
        output.enumerateLines { (line, stop) in
            guard line.range(of: pattern) != nil else {
                return
            }
            
            let escapedLine = line.replacingOccurrences(of: "\\ ", with: "##")
            let tokens = escapedLine.split(separator: " ")
            let pairs = zip(tokens, tokens.dropFirst())
            
            let relevantTokens = pairs
                .flatMap { pair -> [String] in
                    
                    if gluedPrefixes.contains(where: { pair.0.hasPrefix($0) }) {
                        return [String(pair.0)]
                    }
                    else if splitPrefixes.contains(where: { pair.0.hasPrefix($0) }) {
                        return [String(pair.0), String(pair.1)]
                    }
                    return []
                }
                .map { $0.replacingOccurrences(of: "##", with: " ") }
            
            compilerFlags = relevantTokens
            stop = true
        }
        
        guard let compilerFlagsUnwrapped = compilerFlags else {
            printError("cannot parse compiler flags")
            throw BridgecraftError.unknown
        }
        
        return compilerFlagsUnwrapped
    }
    
    private func preprocessBridgingSource(withCompilerFlags compilerFlags: [String]) throws {
        do {
            try shell("/usr/bin/clang", args: [
                "-x", "objective-c", "-C", "-fmodules", "-fimplicit-modules",
                "-E", bridgingSourceURL.path,
                "-o", preprocessedURL.path
                ] + compilerFlags)
        }
        catch {
            printError("failed to preprocess file at \(bridgingSourceURL.path): \(error)")
            throw error
        }
    }
    
    private func fixNullability() throws {
        do {
            let src = try String(contentsOf: preprocessedURL)
            let wrappedSrc =
                """
                #import <Foundation/Foundation.h>
                NS_ASSUME_NONNULL_BEGIN
                \(src)
                NS_ASSUME_NONNULL_END
                """
            try wrappedSrc.write(to: preprocessedURL, atomically: false, encoding: .utf8)
        }
        catch {
            printError("failed to fix nullability in preprocessed file at \(preprocessedURL.path): \(error)")
            throw error
        }
    }
    
    private func generateSwiftInterface(withCompilerFlags compilerFlags: [String]) throws -> String {
        let req = Request.interface(file: preprocessedURL.path,
                                    uuid: UUID().uuidString,
                                    arguments: compilerFlags)
        let result: [String: SourceKitRepresentable]
        do {
            result = try req.send()
        }
        catch {
            printError("failed to generate interface for \(preprocessedURL.path): \(error)")
            throw error
        }
        
        guard let srcText = result["key.sourcetext"] as? String, !srcText.isEmpty else {
            printError("generated interface is empty")
            throw BridgecraftError.unknown
        }
        
        return srcText
    }
    
    private func writeGeneratedInterfaceToFile(interface: String) throws {
        let header =
            """
            // Generated using Bridgecraft \(version) - https://github.com/lvsti/Bridgecraft
            // DO NOT EDIT
            """
        
        let output = "\(header)\n\n\(interface)"
        
        if let url = outputFileURL {
            do {
                try output.write(to: url, atomically: true, encoding: .utf8)
            }
            catch {
                printError("cannot write output to \(url): \(error)")
                throw BridgecraftError.unknown
            }
        }
        else {
            print("\(output)")
        }
    }
    
    private func cleanUp() {
        _ = try? FileManager.default.removeItem(at: tempProjectURL)
        _ = try? FileManager.default.removeItem(at: bridgingSourceURL)
        _ = try? FileManager.default.removeItem(at: preprocessedURL)
    }
    
}

