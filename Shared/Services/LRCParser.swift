//
//  LRCParser.swift
//  BookPlayer
//
//  Created for synchronized text viewer feature.
//  Copyright © 2024 BookPlayer LLC. All rights reserved.
//

import Foundation

/// Errors that can occur during LRC file parsing
public enum LRCParserError: Error, LocalizedError {
  case invalidFileFormat
  case invalidTimestamp
  case emptyFile
  case readError
  
  public var errorDescription: String? {
    switch self {
    case .invalidFileFormat:
      return "The LRC file format is invalid or malformed."
    case .invalidTimestamp:
      return "The LRC file contains invalid timestamp formats."
    case .emptyFile:
      return "The LRC file is empty."
    case .readError:
      return "Failed to read the LRC file."
    }
  }
}

/// Parser for LRC (Lyric) files
public class LRCParser {
  
  /// Parse an LRC file from a URL
  /// - Parameter url: The file URL of the LRC file
  /// - Returns: An LRCDocument containing the parsed metadata and lines
  /// - Throws: LRCParserError if parsing fails
  public static func parse(from url: URL) throws -> LRCDocument {
    guard let content = try? String(contentsOf: url, encoding: .utf8) else {
      throw LRCParserError.readError
    }
    
    return try parse(content: content)
  }
  
  /// Parse an LRC file from string content
  /// - Parameter content: The LRC file content as a string
  /// - Returns: An LRCDocument containing the parsed metadata and lines
  /// - Throws: LRCParserError if parsing fails
  public static func parse(content: String) throws -> LRCDocument {
    guard !content.isEmpty else {
      throw LRCParserError.emptyFile
    }
    
    var metadata = LRCMetadata()
    var lines: [LRCLine] = []
    
    let contentLines = content.components(separatedBy: .newlines)
    
    for line in contentLines {
      let trimmedLine = line.trimmingCharacters(in: .whitespaces)
      
      // Skip empty lines
      guard !trimmedLine.isEmpty else { continue }
      
      // Parse metadata tags
      if let metadataResult = parseMetadata(line: trimmedLine) {
        metadata = mergeMetadata(existing: metadata, new: metadataResult)
        continue
      }
      
      // Parse timestamp lines
      if let parsedLines = parseTimestampLine(line: trimmedLine) {
        lines.append(contentsOf: parsedLines)
      }
    }
    
    // Sort lines by timestamp
    lines.sort { $0.timestamp < $1.timestamp }
    
    // Apply offset to all timestamps
    if metadata.offset != 0 {
      lines = lines.map { line in
        LRCLine(
          timestamp: max(0, line.timestamp + metadata.offset),
          text: line.text
        )
      }
    }
    
    guard !lines.isEmpty else {
      throw LRCParserError.invalidFileFormat
    }
    
    return LRCDocument(metadata: metadata, lines: lines)
  }
  
  /// Parse metadata tags from a line
  private static func parseMetadata(line: String) -> LRCMetadata? {
    // Metadata format: [tag:value]
    guard line.hasPrefix("["), line.hasSuffix("]") else { return nil }
    
    let content = String(line.dropFirst().dropLast())
    let parts = content.split(separator: ":", maxSplits: 1)
    
    guard parts.count == 2 else { return nil }
    
    let tag = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
    let value = parts[1].trimmingCharacters(in: .whitespaces)
    
    switch tag {
    case "ti", "title":
      return LRCMetadata(title: value)
    case "ar", "artist":
      return LRCMetadata(artist: value)
    case "al", "album":
      return LRCMetadata(album: value)
    case "au", "author":
      return LRCMetadata(author: value)
    case "by", "creator":
      return LRCMetadata(creator: value)
    case "offset":
      if let offsetMs = Int(value) {
        // Offset is in milliseconds, convert to seconds
        return LRCMetadata(offset: Double(offsetMs) / 1000.0)
      }
      return nil
    default:
      return nil
    }
  }
  
  /// Merge metadata from different sources
  private static func mergeMetadata(existing: LRCMetadata, new: LRCMetadata) -> LRCMetadata {
    return LRCMetadata(
      title: new.title ?? existing.title,
      artist: new.artist ?? existing.artist,
      album: new.album ?? existing.album,
      author: new.author ?? existing.author,
      creator: new.creator ?? existing.creator,
      offset: new.offset != 0 ? new.offset : existing.offset
    )
  }
  
  /// Parse a line with timestamp(s) and text
  private static func parseTimestampLine(line: String) -> [LRCLine]? {
    // Multiple timestamps can exist on one line: [00:12.00][00:15.30]Line of text
    var remainingLine = line
    var timestamps: [TimeInterval] = []
    
    // Extract all timestamps
    while remainingLine.hasPrefix("[") {
      guard let closeIndex = remainingLine.firstIndex(of: "]") else { break }
      
      let timestampStr = String(remainingLine[remainingLine.index(after: remainingLine.startIndex)..<closeIndex])
      
      // Check if this is a metadata tag (contains ':' but not time format)
      if timestampStr.contains(":") && !timestampStr.contains(".") && 
         timestampStr.split(separator: ":").count == 2 &&
         !timestampStr.split(separator: ":")[0].allSatisfy({ $0.isNumber }) {
        // This is likely metadata, not a timestamp
        return nil
      }
      
      if let timestamp = parseTimestamp(timestampStr) {
        timestamps.append(timestamp)
      }
      
      remainingLine = String(remainingLine[remainingLine.index(after: closeIndex)...])
    }
    
    guard !timestamps.isEmpty else { return nil }
    
    let text = remainingLine.trimmingCharacters(in: .whitespaces)
    
    // Create an LRCLine for each timestamp
    return timestamps.map { LRCLine(timestamp: $0, text: text) }
  }
  
  /// Parse a timestamp string to TimeInterval
  /// Supports formats: [mm:ss.xx] or [mm:ss] or [mm:ss.xxx]
  private static func parseTimestamp(_ timestamp: String) -> TimeInterval? {
    let components = timestamp.split(separator: ":")
    
    guard components.count == 2 else { return nil }
    
    guard let minutes = Double(components[0]) else { return nil }
    
    // Split seconds and milliseconds
    let secondsParts = components[1].split(separator: ".")
    guard let seconds = Double(secondsParts[0]) else { return nil }
    
    var milliseconds: Double = 0
    if secondsParts.count > 1 {
      let msString = String(secondsParts[1])
      // Handle both .xx (centiseconds) and .xxx (milliseconds) formats
      if let ms = Double(msString) {
        milliseconds = msString.count == 2 ? ms / 100.0 : ms / 1000.0
      }
    }
    
    return (minutes * 60) + seconds + milliseconds
  }
}
