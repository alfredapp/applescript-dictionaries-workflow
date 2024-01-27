import Foundation

// Helpers
struct ScriptFilter: Codable {
  let cache: Cache
  let items: [Item]

  struct Cache: Codable {
    let seconds: Int
    let loosereload: Bool
  }

  struct Item: Codable {
    let uid: String
    let title: String
    let subtitle: String
    let type: String
    let icon: FileIcon
    let arg: String

    struct FileIcon: Codable {
      let path: String
      let type: String
    }
  }
}

func findDict(inFolder: URL) -> URL? {
  let resourcesFolder = inFolder.appendingPathComponent("Contents/Resources")

  return try? FileManager.default.contentsOfDirectory(
    at: resourcesFolder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
  ).first(where: { $0.pathExtension == "sdef" })
}

// Find apps with Spotlight
let spotQuery = "kMDItemContentTypeTree == 'com.apple.application-bundle'"
let searchQuery = MDQueryCreate(kCFAllocatorDefault, spotQuery as CFString, nil, nil)

MDQueryExecute(searchQuery, CFOptionFlags(kMDQuerySynchronous.rawValue))
let resultCount = MDQueryGetResultCount(searchQuery)

let spotApps: [URL] = (0..<resultCount).compactMap { resultIndex in
  let rawPointer = MDQueryGetResultAtIndex(searchQuery, resultIndex)
  let resultItem = Unmanaged<MDItem>.fromOpaque(rawPointer!).takeUnretainedValue()

  guard let resultPath = MDItemCopyAttribute(resultItem, kMDItemPath) as? String else { return nil }
  return URL(fileURLWithPath: resultPath)
}

// Find apps in special locations
let additions: [URL] = [
  URL(fileURLWithPath: "/System/Library/ScriptingAdditions/StandardAdditions.osax")
]

let customApps: [URL] = {
  guard let workflowData = ProcessInfo.processInfo.environment["alfred_workflow_data"] else { return [] }
  let dataFolder = URL(fileURLWithPath: workflowData)

  guard
    let dataContents = try? FileManager.default.contentsOfDirectory(
      at: dataFolder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
  else { return [] }

  return dataContents.filter { $0.pathExtension == "app" }
}()

// Join all apps
let allApps = spotApps + additions + customApps

// Structure JSON
let cachingItems = ScriptFilter.Cache(seconds: 300, loosereload: true)

let sfItems: [ScriptFilter.Item] = allApps.compactMap { app in
  guard let dict = findDict(inFolder: app)?.path else { return nil }

  return ScriptFilter.Item(
    uid: dict,
    title: app.deletingPathExtension().lastPathComponent,
    subtitle: dict,
    type: "file",
    icon: ScriptFilter.Item.FileIcon(path: app.path, type: "fileicon"),
    arg: dict
  )
}

// Output JSON
let jsonData = try JSONEncoder().encode(ScriptFilter(cache: cachingItems, items: sfItems))
print(String(data: jsonData, encoding: .utf8)!)
