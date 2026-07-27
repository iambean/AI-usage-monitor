import Foundation

struct StatusLineInput: Decodable {
  let rateLimits: RateLimits?

  enum CodingKeys: String, CodingKey {
    case rateLimits = "rate_limits"
  }
}

struct UsageSnapshot: Encodable {
  let rateLimits: RateLimits

  enum CodingKeys: String, CodingKey {
    case rateLimits = "rate_limits"
  }
}

struct RateLimits: Codable {
  let fiveHour: Window?
  let sevenDay: Window?

  enum CodingKeys: String, CodingKey {
    case fiveHour = "five_hour"
    case sevenDay = "seven_day"
  }
}

struct Window: Codable {
  let usedPercentage: Double
  let resetsAt: Timestamp?

  enum CodingKeys: String, CodingKey {
    case usedPercentage = "used_percentage"
    case resetsAt = "resets_at"
  }
}

enum Timestamp: Codable {
  case number(Double)
  case string(String)

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else {
      self = .string(try container.decode(String.self))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .number(let value):
      try container.encode(value)
    case .string(let value):
      try container.encode(value)
    }
  }
}

let inputData = FileHandle.standardInput.readDataToEndOfFile()
guard !inputData.isEmpty,
  let input = try? JSONDecoder().decode(StatusLineInput.self, from: inputData),
  let limits = input.rateLimits
else {
  exit(0)
}

let directory = FileManager.default.urls(
  for: .applicationSupportDirectory,
  in: .userDomainMask
)[0].appendingPathComponent("AI Usage Monitor", isDirectory: true)
let cacheURL = directory.appendingPathComponent("claude-usage.json")
try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
if let snapshot = try? JSONEncoder().encode(UsageSnapshot(rateLimits: limits)) {
  try? snapshot.write(to: cacheURL, options: .atomic)
}

var parts: [String] = []
if let fiveHour = limits.fiveHour {
  parts.append("5h \(Int((100 - fiveHour.usedPercentage).rounded()))%")
}
if let sevenDay = limits.sevenDay {
  parts.append("周期 \(Int((100 - sevenDay.usedPercentage).rounded()))%")
}
if !parts.isEmpty {
  print("Claude " + parts.joined(separator: " · "))
}
