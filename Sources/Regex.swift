//
//  Regex.swift
//  SwiftLinkPreview
//
//  Created by Leonardo Cardoso on 09/06/2016.
//  Copyright © 2016 leocardz.com. All rights reserved.
//
import Foundation

// MARK: - Regular expressions
class Regex {
    
    static let imageTagPattern = "<img(.+?)src=\"([^\"](.+?))\"(.+?)[/]?>"
    static let rawTagPattern = "<[^>]+>"
    
    // Match all occurrencies
    static func pregMatchAll(_ string: String, regex: String, index: Int = 0) -> [String] {
        
        do{
            
            let rx = try NSRegularExpression(pattern: regex, options: [.caseInsensitive])

            var matches: [NSTextCheckingResult] = []

            let limit = 300000

            if string.count > limit {
                string.split(by: limit).forEach {
                    matches.append(contentsOf: rx.matches(in: string, options: [], range: NSMakeRange(0, $0.count)))
                }
            } else {
                matches.append(contentsOf: rx.matches(in: string, options: [], range: NSMakeRange(0, string.count)))
            }
            
            return !matches.isEmpty ? Regex.stringMatches(matches, text: string, index: index) : []
            
        } catch {
            
            return []
            
        }
        
    }
    
    // Extract matches from string
    static func stringMatches(_ results: [NSTextCheckingResult], text: String, index: Int = 0) -> [String] {

        return results.map {
            let range = $0.range(at: index)
            if text.count > range.location + range.length {
                return (text as NSString).substring(with: range)
            } else {
                return ""
            }
        }
        
    }
    
}
