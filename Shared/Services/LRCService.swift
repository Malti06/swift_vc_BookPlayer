//
//  LRCService.swift
//  BookPlayer
//
//  Created for synchronized text viewer feature.
//  Copyright © 2024 BookPlayer LLC. All rights reserved.
//

import Foundation

/// Service for managing LRC files associated with playable items
public class LRCService {
  
  public static let shared = LRCService()
  
  private init() {}
  
  /// Get the URL for storing LRC files
  private func getLRCDirectory() -> URL {
    let documentsURL = DataManager.getProcessedFolderURL()
    let lrcDirectory = documentsURL.appendingPathComponent("lrc", isDirectory: true)
    
    // Create directory if it doesn't exist
    if !FileManager.default.fileExists(atPath: lrcDirectory.path) {
      try? FileManager.default.createDirectory(
        at: lrcDirectory,
        withIntermediateDirectories: true,
        attributes: nil
      )
    }
    
    return lrcDirectory
  }
  
  /// Get the LRC file URL for a given playable item
  /// - Parameter relativePath: The relative path of the playable item
  /// - Returns: The URL where the LRC file should be stored
  public func getLRCFileURL(for relativePath: String) -> URL {
    let fileName = (relativePath as NSString).lastPathComponent
    let lrcFileName = (fileName as NSString).deletingPathExtension + ".lrc"
    return getLRCDirectory().appendingPathComponent(lrcFileName)
  }
  
  /// Check if an LRC file exists for a given playable item
  /// - Parameter relativePath: The relative path of the playable item
  /// - Returns: True if an LRC file exists
  public func hasLRCFile(for relativePath: String) -> Bool {
    let lrcURL = getLRCFileURL(for: relativePath)
    return FileManager.default.fileExists(atPath: lrcURL.path)
  }
  
  /// Import an LRC file for a given playable item
  /// - Parameters:
  ///   - sourceURL: The source URL of the LRC file to import
  ///   - relativePath: The relative path of the playable item
  /// - Throws: Error if the import fails
  public func importLRCFile(from sourceURL: URL, for relativePath: String) throws {
    let destinationURL = getLRCFileURL(for: relativePath)
    
    // Validate the LRC file can be parsed
    _ = try LRCParser.parse(from: sourceURL)
    
    // Copy the file to the LRC directory
    if FileManager.default.fileExists(atPath: destinationURL.path) {
      try FileManager.default.removeItem(at: destinationURL)
    }
    
    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
  }
  
  /// Load and parse the LRC document for a given playable item
  /// - Parameter relativePath: The relative path of the playable item
  /// - Returns: The parsed LRCDocument, or nil if no LRC file exists
  public func loadLRCDocument(for relativePath: String) -> LRCDocument? {
    guard hasLRCFile(for: relativePath) else { return nil }
    
    let lrcURL = getLRCFileURL(for: relativePath)
    
    do {
      return try LRCParser.parse(from: lrcURL)
    } catch {
      print("Failed to parse LRC file at \(lrcURL): \(error)")
      return nil
    }
  }
  
  /// Delete the LRC file for a given playable item
  /// - Parameter relativePath: The relative path of the playable item
  public func deleteLRCFile(for relativePath: String) {
    let lrcURL = getLRCFileURL(for: relativePath)
    
    if FileManager.default.fileExists(atPath: lrcURL.path) {
      try? FileManager.default.removeItem(at: lrcURL)
    }
  }
}
