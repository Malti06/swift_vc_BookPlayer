//
//  LRCLine.swift
//  BookPlayer
//
//  Created for synchronized text viewer feature.
//  Copyright © 2024 BookPlayer LLC. All rights reserved.
//

import Foundation

/// Represents a single line in an LRC file with timestamp and text content
public struct LRCLine: Identifiable, Equatable {
  public let id: UUID
  public let timestamp: TimeInterval
  public let text: String
  
  public init(timestamp: TimeInterval, text: String) {
    self.id = UUID()
    self.timestamp = timestamp
    self.text = text
  }
  
  public static func == (lhs: LRCLine, rhs: LRCLine) -> Bool {
    return lhs.timestamp == rhs.timestamp && lhs.text == rhs.text
  }
}

/// Represents metadata from an LRC file
public struct LRCMetadata {
  public let title: String?
  public let artist: String?
  public let album: String?
  public let author: String?
  public let creator: String?
  public let offset: TimeInterval
  
  public init(
    title: String? = nil,
    artist: String? = nil,
    album: String? = nil,
    author: String? = nil,
    creator: String? = nil,
    offset: TimeInterval = 0
  ) {
    self.title = title
    self.artist = artist
    self.album = album
    self.author = author
    self.creator = creator
    self.offset = offset
  }
}

/// Complete LRC file representation
public struct LRCDocument {
  public let metadata: LRCMetadata
  public let lines: [LRCLine]
  
  public init(metadata: LRCMetadata, lines: [LRCLine]) {
    self.metadata = metadata
    self.lines = lines
  }
  
  /// Get the current line index for a given timestamp
  public func getLineIndex(for timestamp: TimeInterval) -> Int? {
    guard !lines.isEmpty else { return nil }
    
    // Find the last line where timestamp >= line.timestamp
    for (index, line) in lines.enumerated().reversed() {
      if timestamp >= line.timestamp {
        return index
      }
    }
    
    return nil
  }
  
  /// Get the current line for a given timestamp
  public func getLine(for timestamp: TimeInterval) -> LRCLine? {
    guard let index = getLineIndex(for: timestamp) else { return nil }
    return lines[index]
  }
}
