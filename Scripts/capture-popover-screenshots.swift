#!/usr/bin/env swift

import CoreGraphics
import Foundation
import AppKit

private let popoverTabs = ["timer", "memo", "stats", "news", "agent"]
private let settingsTabs = ["general", "appearance", "timer", "hotkey", "category", "stats", "news", "agent", "memo", "data", "about"]
private let statsDetailModes = ["daily", "weekly", "monthly"]
private let allTargets = popoverTabs.map { "popover:\($0)" }
    + ["settings:general"]
    + statsDetailModes.map { "stats-detail:\($0)" }

private struct ScriptError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct CaptureOptions {
    var outputDirectory: URL?
    var targets = allTargets
    var skipBuild = false
    var derivedDataPath = URL(fileURLWithPath: "/private/tmp/horonghorong-screenshot-derived-data")
    var appPath: URL?

    init(arguments: [String]) throws {
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--output":
                outputDirectory = try Self.value(after: argument, at: &index, in: arguments).expandedFileURL
            case "--targets":
                let rawTargets = try Self.parseList(Self.value(after: argument, at: &index, in: arguments))
                guard !rawTargets.isEmpty else {
                    throw ScriptError(message: "--targets 값이 비어 있습니다.")
                }
                let invalidTargets = rawTargets.filter { !Self.isValidTarget($0) }
                guard invalidTargets.isEmpty else {
                    throw ScriptError(message: "알 수 없는 캡처 대상입니다: \(invalidTargets.joined(separator: ", "))")
                }
                targets = rawTargets
            case "--tabs":
                let rawTabs = try Self.parseList(Self.value(after: argument, at: &index, in: arguments))
                guard !rawTabs.isEmpty else {
                    throw ScriptError(message: "--tabs 값이 비어 있습니다.")
                }
                let invalidTabs = rawTabs.filter { !popoverTabs.contains($0) }
                guard invalidTabs.isEmpty else {
                    throw ScriptError(message: "알 수 없는 탭입니다: \(invalidTabs.joined(separator: ", "))")
                }
                targets = rawTabs.map { "popover:\($0)" }
            case "--skip-build":
                skipBuild = true
            case "--derived-data":
                derivedDataPath = try Self.value(after: argument, at: &index, in: arguments).expandedFileURL
            case "--app":
                appPath = try Self.value(after: argument, at: &index, in: arguments).expandedFileURL
                skipBuild = true
            case "--help", "-h":
                print(Self.help)
                exit(0)
            default:
                throw ScriptError(message: "알 수 없는 옵션입니다: \(argument)\n\n\(Self.help)")
            }
            index += 1
        }
    }

    private static func value(after option: String, at index: inout Int, in arguments: [String]) throws -> String {
        let valueIndex = index + 1
        guard arguments.indices.contains(valueIndex) else {
            throw ScriptError(message: "\(option) 옵션에 값이 필요합니다.")
        }
        index = valueIndex
        return arguments[valueIndex]
    }

    private static func parseList(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private static func isValidTarget(_ target: String) -> Bool {
        let parts = target.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        switch parts[0] {
        case "popover":
            return popoverTabs.contains(parts[1])
        case "settings":
            return settingsTabs.contains(parts[1])
        case "stats-detail":
            return statsDetailModes.contains(parts[1])
        default:
            return false
        }
    }

    static let help = """
    Usage:
      swift Scripts/capture-popover-screenshots.swift [options]

    Options:
      --output <dir>        PNG 저장 경로. 기본값: Artifacts/Screenshots
      --targets <list>      캡처 대상 목록. 기본값: popover 전체 + settings:general + stats-detail 전체
                            예: popover:timer,settings:appearance,stats-detail:weekly
      --tabs <list>         popover 탭만 캡처하는 호환 옵션. 예: timer,memo,stats
      --skip-build          기존 빌드 산출물을 사용합니다.
      --derived-data <dir>  xcodebuild DerivedData 경로. 기본값: /private/tmp/horonghorong-screenshot-derived-data
      --app <path>          직접 지정한 .app을 캡처합니다. 지정 시 빌드를 생략합니다.
      --help                도움말을 표시합니다.
    """
}

private extension String {
    var expandedFileURL: URL {
        URL(fileURLWithPath: (self as NSString).expandingTildeInPath)
    }
}

private func findRepoRoot(from start: URL) throws -> URL {
    var current = start
    while true {
        if FileManager.default.fileExists(atPath: current.appendingPathComponent("HorongHorong.xcodeproj").path) {
            return current
        }
        let parent = current.deletingLastPathComponent()
        guard parent.path != current.path else {
            throw ScriptError(message: "HorongHorong.xcodeproj를 찾을 수 없습니다.")
        }
        current = parent
    }
}

private func runCommand(_ executable: String, arguments: [String], currentDirectory: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw ScriptError(message: "\(executable) 실패: 종료 코드 \(process.terminationStatus)")
    }
}

private func builtAppPath(derivedDataPath: URL) throws -> URL {
    let productsDirectory = derivedDataPath
        .appendingPathComponent("Build")
        .appendingPathComponent("Products")
        .appendingPathComponent("Debug")
    let preferredApp = productsDirectory.appendingPathComponent("호롱호롱.app")
    if FileManager.default.fileExists(atPath: preferredApp.path) {
        return preferredApp
    }

    let apps = try FileManager.default.contentsOfDirectory(
        at: productsDirectory,
        includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "app" }

    guard let app = apps.first else {
        throw ScriptError(message: "빌드된 .app을 찾을 수 없습니다: \(productsDirectory.path)")
    }
    return app
}

private func waitForWindow(title: String, processID: pid_t, timeout: TimeInterval = 10) throws -> CGWindowID {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if let windowID = matchingWindow(title: title, processID: processID) {
            return windowID
        }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline

    throw ScriptError(message: "캡처할 창을 찾지 못했습니다: \(title)\n\(windowDiagnostics(processID: processID))")
}

private func matchingWindow(title: String, processID: pid_t) -> CGWindowID? {
    guard let windowInfo = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]] else {
        return nil
    }

    let ownerPIDKey = kCGWindowOwnerPID as String
    let windowNumberKey = kCGWindowNumber as String
    let windowNameKey = kCGWindowName as String
    let layerKey = kCGWindowLayer as String
    let boundsKey = kCGWindowBounds as String

    for info in windowInfo {
        guard intValue(info[ownerPIDKey]) == Int(processID),
              isCapturableLayer(intValue(info[layerKey])),
              (info[windowNameKey] as? String) == title,
              let number = uint32Value(info[windowNumberKey]) else {
            continue
        }
        return CGWindowID(number)
    }

    for info in windowInfo {
        guard intValue(info[ownerPIDKey]) == Int(processID),
              isCapturableLayer(intValue(info[layerKey])),
              let bounds = info[boundsKey] as? [String: Any],
              let width = doubleValue(bounds["Width"]),
              let height = doubleValue(bounds["Height"]),
              width >= 320,
              height >= 480,
              let number = uint32Value(info[windowNumberKey]) else {
            continue
        }
        return CGWindowID(number)
    }

    return nil
}

private func isCapturableLayer(_ layer: Int?) -> Bool {
    guard let layer else { return false }
    return (0...3).contains(layer)
}

private func windowDiagnostics(processID: pid_t) -> String {
    guard let windowInfo = CGWindowListCopyWindowInfo(
        [.optionAll, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]] else {
        return "WindowServer 목록을 읽지 못했습니다."
    }

    let ownerPIDKey = kCGWindowOwnerPID as String
    let windowNumberKey = kCGWindowNumber as String
    let windowNameKey = kCGWindowName as String
    let layerKey = kCGWindowLayer as String
    let boundsKey = kCGWindowBounds as String

    let matches = windowInfo.compactMap { info -> String? in
        guard intValue(info[ownerPIDKey]) == Int(processID) else { return nil }
        let number = uint32Value(info[windowNumberKey]).map(String.init) ?? "?"
        let layer = intValue(info[layerKey]).map(String.init) ?? "?"
        let name = (info[windowNameKey] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "(no title)"
        let bounds = info[boundsKey] as? [String: Any]
        let width = doubleValue(bounds?["Width"]).map { String(format: "%.0f", $0) } ?? "?"
        let height = doubleValue(bounds?["Height"]).map { String(format: "%.0f", $0) } ?? "?"
        return "window=\(number) layer=\(layer) size=\(width)x\(height) title=\(name)"
    }

    if matches.isEmpty {
        return "PID \(processID)에 속한 WindowServer 창이 없습니다."
    }
    return "PID \(processID) WindowServer 창:\n" + matches.joined(separator: "\n")
}

private func captureWindow(id windowID: CGWindowID, to outputURL: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-o", "-l\(windowID)", outputURL.path]
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0,
          FileManager.default.fileExists(atPath: outputURL.path) else {
        throw ScriptError(message: "PNG 저장에 실패했습니다. macOS 화면 기록 권한을 확인해 주세요: \(outputURL.path)")
    }
}

private func intValue(_ value: Any?) -> Int? {
    switch value {
    case let value as Int:
        return value
    case let value as Int32:
        return Int(value)
    case let value as NSNumber:
        return value.intValue
    default:
        return nil
    }
}

private func uint32Value(_ value: Any?) -> UInt32? {
    switch value {
    case let value as UInt32:
        return value
    case let value as Int where value >= 0:
        return UInt32(value)
    case let value as NSNumber:
        return value.uint32Value
    default:
        return nil
    }
}

private func doubleValue(_ value: Any?) -> Double? {
    switch value {
    case let value as Double:
        return value
    case let value as CGFloat:
        return Double(value)
    case let value as Int:
        return Double(value)
    case let value as NSNumber:
        return value.doubleValue
    default:
        return nil
    }
}

private func launchApp(appPath: URL, target: String) throws -> NSRunningApplication {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = ["--screenshot-target", target]
    configuration.activates = true
    configuration.addsToRecentItems = false
    configuration.createsNewApplicationInstance = true
    configuration.environment = ProcessInfo.processInfo.environment.merging(
        ["HORONGHORONG_SCREENSHOT_TARGET": target],
        uniquingKeysWith: { _, newValue in newValue }
    )

    let semaphore = DispatchSemaphore(value: 0)
    var launchedApp: NSRunningApplication?
    var launchError: Error?

    NSWorkspace.shared.openApplication(at: appPath, configuration: configuration) { app, error in
        launchedApp = app
        launchError = error
        semaphore.signal()
    }

    semaphore.wait()
    if let launchError {
        throw launchError
    }
    guard let launchedApp else {
        throw ScriptError(message: "앱 실행에 실패했습니다: \(appPath.path)")
    }
    return launchedApp
}

private func capture(target: String, appPath: URL, outputDirectory: URL) throws {
    let fileIdentifier = target.replacingOccurrences(of: ":", with: "-")
    let title = "HorongHorong Screenshot - \(fileIdentifier)"
    let runningApp = try launchApp(appPath: appPath, target: target)

    defer {
        runningApp.terminate()
    }

    let windowID = try waitForWindow(title: title, processID: runningApp.processIdentifier)
    Thread.sleep(forTimeInterval: 0.4)
    let outputURL = outputDirectory.appendingPathComponent("\(fileIdentifier).png")
    try captureWindow(id: windowID, to: outputURL)
    print("✓ \(target) -> \(outputURL.path)")
}

do {
    let options = try CaptureOptions(arguments: CommandLine.arguments)
    let repoRoot = try findRepoRoot(from: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    let outputDirectory = options.outputDirectory ?? repoRoot
        .appendingPathComponent("Artifacts")
        .appendingPathComponent("Screenshots")
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    if !options.skipBuild {
        try runCommand(
            "/usr/bin/xcodebuild",
            arguments: [
                "build",
                "-scheme", "HorongHorong",
                "-configuration", "Debug",
                "-destination", "platform=macOS",
                "-derivedDataPath", options.derivedDataPath.path,
            ],
            currentDirectory: repoRoot
        )
    }

    let appPath = try options.appPath ?? builtAppPath(derivedDataPath: options.derivedDataPath)
    for target in options.targets {
        try capture(target: target, appPath: appPath, outputDirectory: outputDirectory)
    }
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
