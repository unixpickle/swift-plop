// The Swift Programming Language
// https://docs.swift.org/swift-book

import ArgumentParser
import Charts
import SwiftUI

@main
struct Main: AsyncParsableCommand {
  @Option(name: .shortAndLong, help: "width of the plot")
  var width: Float = 400.0

  @Option(name: .shortAndLong, help: "height of the plot")
  var height: Float = 400.0

  @Option(name: .shortAndLong, help: "padding of the plot")
  var padding: Float = 10.0

  @Option(name: .shortAndLong, help: "smoothing EMA rate (from 0 to 1)")
  var smoothing: Double = 0.0

  @Option(name: .shortAndLong, help: "y axis field name")
  var x: String? = nil

  @Option(name: .shortAndLong, help: "output file path")
  var outPath: String

  @Option(name: .shortAndLong, help: "y axis field name")
  var y: String

  @Argument(help: "a sequence of [name] [path] pairs")
  var namesAndPaths: [String]

  @MainActor
  mutating func run() async {
    if namesAndPaths.count % 2 != 0 || namesAndPaths.isEmpty {
      print("must path a series of [name] [path] pairs.")
      return
    }

    var data = [Sample]()
    for i in stride(from: 0, through: namesAndPaths.count - 2, by: 2) {
      do {
        let rawSamples = try Sample.parse(
          URL(filePath: namesAndPaths[i + 1]), name: namesAndPaths[i], y: y, x: x)
        let samples = Sample.smooth(rawSamples, ema: smoothing)
        data.append(contentsOf: Sample.sortAndDedup(samples))
      } catch {
        print("error parsing \(namesAndPaths[i+1]): \(error)")
      }
    }

    let renderer = ImageRenderer(
      content: Chart(data) {
        LineMark(
          x: .value("X", $0.x),
          y: .value("Y", $0.y)
        ).foregroundStyle(by: .value("Name", $0.name))
      }.frame(width: 400, height: 400).padding(10)
    )
    do {
      try saveImageWithWhiteBackground(
        originalImage: renderer.nsImage!, outputURL: URL(filePath: outPath))
    } catch {
      print("error saving: \(error)")
    }
  }
}

enum SaveError: Error {
  case createTIFFFailed
  case createBitmapRepFailed
  case createPNGFailed
  case writePNGFailed(Error)
}

func saveImageWithWhiteBackground(originalImage: NSImage, outputURL: URL) throws {
  let imageSize = originalImage.size
  let newImage = NSImage(size: imageSize)

  newImage.lockFocus()

  NSColor.white.setFill()
  let rect = NSRect(origin: .zero, size: imageSize)
  rect.fill()
  originalImage.draw(in: rect)

  newImage.unlockFocus()

  guard let tiffData = newImage.tiffRepresentation else {
    throw SaveError.createTIFFFailed
  }
  guard let bitmapRep = NSBitmapImageRep(data: tiffData) else {
    throw SaveError.createBitmapRepFailed
  }
  guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
    throw SaveError.createPNGFailed
  }
  do {
    try pngData.write(to: outputURL)
  } catch {
    throw SaveError.writePNGFailed(error)
  }
}
