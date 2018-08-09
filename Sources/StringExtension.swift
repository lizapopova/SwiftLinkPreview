//
//  StringExtension.swift
//  SwiftLinkPreview
//
//  Created by Leonardo Cardoso on 09/06/2016.
//  Copyright © 2016 leocardz.com. All rights reserved.
//
import Foundation

#if os(iOS) || os(watchOS) || os(tvOS)
    
    import UIKit
    
#elseif os(OSX)
    
    import Cocoa
    
#endif

extension String {
    
    // Trim
    var trim: String {
        return self.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
    
    // Remove extra white spaces
    var extendedTrim: String {
        let components = self.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        return components.filter { !$0.isEmpty }.joined(separator: " ").trim
    }
    
    func hasImageExt() -> Bool {
        let imageExts = [".gif", ".jpg", ".jpeg", ".png", ".bmp"]
        return imageExts.contains(where: { self.lowercased().hasSuffix($0) })
    }
    
    func hasNoExt() -> Bool {
        return self.range(of: ".") == nil
    }
}
