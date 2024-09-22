import Foundation

enum LoadError: Error {
  case decodeString
  case parseField(String)
  case missingKeys(String)
}

struct LineField {
  let name: String
  let value: Double

  private static let expr = #/([^ ]*)=([^ ]*)/#
  private static let stepExpr = #/step ([0-9]*):/#

  public static func extract(_ s: some StringProtocol) throws -> [LineField] {
    var result = [LineField]()
    for match in String(s).matches(of: expr) {
      guard let parsed = Double(match.2) else {
        throw LoadError.parseField("could not parse field '\(match.1)' value '\(match.2)'")
      }
      result.append(LineField(name: String(match.1), value: parsed))
    }
    if let match = String(s).firstMatch(of: stepExpr) {
      guard let step = Int(match.1) else {
        throw LoadError.parseField("could not parse step value '\(match.1)'")
      }
      result.append(LineField(name: "step", value: Double(step)))
    }
    return result
  }
}

struct Sample: Identifiable {
  let name: String
  let x: Double
  let y: Double

  var id: String {
    "\(name)\(x)"
  }

  public static func parse(_ from: URL, name: String, y: String, x: String? = nil) throws
    -> [Sample]
  {
    guard let contents = String(data: try Data(contentsOf: from), encoding: .utf8) else {
      throw LoadError.decodeString
    }
    var result = [Sample]()
    var allKeys = Set<String>()
    var idx = 0.0
    for line in contents.split(separator: "\n") {
      let fields = try LineField.extract(line)
      var mapping = [String: Double]()
      for field in fields {
        mapping[field.name] = field.value
        allKeys.insert(field.name)
      }
      if let value = mapping[y] {
        if let key = if let x = x { mapping[x] } else { idx } {
          result.append(Sample(name: name, x: key, y: value))
        }
        idx += 1.0
      }
    }
    if result.isEmpty && !allKeys.isEmpty {
      throw LoadError.missingKeys(
        "could not find y/x pair y=\(y) x=\(x ?? "none") in keys \(allKeys)")
    }
    return result
  }

  public static func sortAndDedup(_ items: [Sample]) -> [Sample] {
    var items = items.enumerated().sorted(by: { ($0.1.id, $0.0) < ($1.1.id, $1.0) })
    var i = 0
    while i < items.count - 1 {
      if items[i].1.id == items[i + 1].1.id {
        items.remove(at: i)
      } else {
        i += 1
      }
    }
    return items.map { $0.1 }
  }

  public static func smooth(_ items: [Sample], ema: Double) -> [Sample] {
    var mean: Double = 0.0
    var count: Double = 0.0
    var result = [Sample]()
    for item in items {
      mean = mean * ema + item.y * (1 - ema)
      count = count * ema + (1 - ema)
      result.append(Sample(name: item.name, x: item.x, y: mean / count))
    }
    return result
  }
}
