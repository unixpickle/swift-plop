import ArgumentParser
import Charts
import SwiftUI
import UniformTypeIdentifiers

@main
struct Main: AsyncParsableCommand {
  @Option(name: .shortAndLong, help: "width of the plot")
  var width: Float = 400.0

  @Option(name: .shortAndLong, help: "height of the plot")
  var height: Float = 400.0

  @Option(name: .shortAndLong, help: "padding of the plot")
  var padding: Float = 10.0

  @Option(name: .long, help: "minimum x value")
  var xMin: Double? = nil

  @Option(name: .long, help: "maximum x value")
  var xMax: Double? = nil

  @Option(name: .long, help: "minimum y value")
  var yMin: Double? = nil

  @Option(name: .long, help: "maximum y value")
  var yMax: Double? = nil

  @Option(name: .shortAndLong, help: "smoothing EMA rate (from 0 to 1)")
  var smoothing: Double = 0.0

  @Option(name: .shortAndLong, help: "y axis field name")
  var x: String? = nil

  @Option(name: .shortAndLong, help: "output file path")
  var outPath: String

  @Option(name: .shortAndLong, help: "y axis field name")
  var y: String

  @Option(name: .long, help: "x axis label")
  var xLabel: String? = nil

  @Option(name: .long, help: "y axis label")
  var yLabel: String? = nil

  @Option(name: .long, help: "resolution scale")
  var imageScale: Float = 1.0

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
        let samples = Sample.smooth(Sample.sortAndDedup(rawSamples), ema: smoothing)
        data.append(contentsOf: samples)
      } catch {
        print("error parsing \(namesAndPaths[i+1]): \(error)")
      }
    }

    let xMin = self.xMin ?? data.map { $0.x }.min()
    let xMax = self.xMax ?? data.map { $0.x }.max()
    let yMin = self.yMin ?? data.map { $0.y }.min()
    let yMax = self.yMax ?? data.map { $0.y }.max()

    var content: AnyView = AnyView(
      Chart(data) {
        LineMark(
          x: .value("X", $0.x),
          y: .value("Y", $0.y)
        ).foregroundStyle(by: .value("Name", $0.name))
      }.chartXScale(domain: (xMin ?? 0.0)...(xMax ?? 1)).chartYScale(
        domain: (yMin ?? 0.0)...(yMax ?? 1)
      ))

    if let xLabel = xLabel {
      content = AnyView(content.chartXAxisLabel(xLabel))
    }
    if let yLabel = yLabel {
      content = AnyView(content.chartYAxisLabel(yLabel))
    }

    let renderer = ImageRenderer(
      content: content.frame(width: 400, height: 400).padding(10)
    )
    renderer.scale = CGFloat(imageScale)
    do {
      try saveImageWithWhiteBackground(
        originalCGImage: renderer.cgImage!, outputURL: URL(filePath: outPath))
    } catch {
      print("error saving: \(error)")
    }
  }
}

enum SaveError: Error {
  case writePNGFailed
  case contextCreationFailed
}

func saveImageWithWhiteBackground(originalCGImage: CGImage, outputURL: URL) throws {
  let width = originalCGImage.width
  let height = originalCGImage.height
  let colorSpace = CGColorSpaceCreateDeviceRGB()

  guard
    let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  else {
    throw SaveError.contextCreationFailed
  }

  context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))

  context.draw(originalCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))

  guard let finalImage = context.makeImage() else {
    throw SaveError.contextCreationFailed
  }

  guard
    let destination = CGImageDestinationCreateWithURL(
      outputURL as CFURL, UTType.png.identifier as CFString, 1, nil)
  else {
    throw SaveError.writePNGFailed
  }
  CGImageDestinationAddImage(destination, finalImage, nil)
  if !CGImageDestinationFinalize(destination) {
    throw SaveError.writePNGFailed
  }
}
