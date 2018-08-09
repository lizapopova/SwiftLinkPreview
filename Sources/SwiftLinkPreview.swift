//
//  SwiftLinkPreview.swift
//  SwiftLinkPreview
//
//  Created by Leonardo Cardoso on 09/06/2016.
//  Copyright © 2016 leocardz.com. All rights reserved.
//
import Foundation
import Fuzi
import os.log

public enum SwiftLinkResponseKey: String {
    case url
    case finalUrl
    case canonicalUrl
    case title
    case description
    case image
    case images
    case icon
}

open class Cancellable: NSObject {
    public private(set) var isCancelled: Bool = false

    open func cancel() {
        isCancelled = true
    }
}

open class SwiftLinkPreview: NSObject {
    
    public typealias Response = [SwiftLinkResponseKey: Any]

    // MARK: - Vars
    static let descMinLength = 30

    public var session: URLSession
    public let workQueue: DispatchQueue
    public let responseQueue: DispatchQueue
    public let cache: Cache

    public static let defaultWorkQueue = DispatchQueue.global(qos: .userInitiated)

    // MARK: - Constructor
    
    //Swift-only init with default parameters
    @nonobjc public init(session: URLSession = URLSession.shared, workQueue: DispatchQueue = SwiftLinkPreview.defaultWorkQueue, responseQueue: DispatchQueue = DispatchQueue.main, cache: Cache = DisabledCache.instance) {
        self.workQueue = workQueue
        self.responseQueue = responseQueue
        self.cache = cache
        self.session = session
    }
    
    //Objective-C init with default parameters
    @objc public override init() {
        let _session = URLSession.shared
        let _workQueue: DispatchQueue = SwiftLinkPreview.defaultWorkQueue
        let _responseQueue: DispatchQueue = DispatchQueue.main
        let _cache: Cache  = DisabledCache.instance
        
        self.workQueue = _workQueue
        self.responseQueue = _responseQueue
        self.cache = _cache
        self.session = _session
    }

    //Objective-C init with paramaters.  nil objects will default.  Timeout values are ignored if InMemoryCache is disabled.
    @objc public init(session: URLSession?, workQueue: DispatchQueue?, responseQueue: DispatchQueue? , disableInMemoryCache: Bool, cacheInvalidationTimeout: TimeInterval, cacheCleanupInterval: TimeInterval) {
        
        let _session = session ?? URLSession.shared
        let _workQueue = workQueue ?? SwiftLinkPreview.defaultWorkQueue
        let _responseQueue = responseQueue ?? DispatchQueue.main
        let _cache: Cache  = disableInMemoryCache ? DisabledCache.instance : InMemoryCache(invalidationTimeout: cacheInvalidationTimeout, cleanupInterval: cacheCleanupInterval)

        self.workQueue = _workQueue
        self.responseQueue = _responseQueue
        self.cache = _cache
        self.session = _session
    }
    
    
    // MARK: - Functions
    // Make preview
    //Swift-only preview function using Swift specific closure types
    @nonobjc @discardableResult open func preview(_ text: String, onSuccess: @escaping (Response) -> Void, onError: @escaping (PreviewError) -> Void) -> Cancellable {
        
        let cancellable = Cancellable()

        self.session = URLSession(configuration: self.session.configuration,
                                  delegate: self, // To handle redirects
            delegateQueue: self.session.delegateQueue)
        
        let successResponseQueue = { (response: Response) in
            if !cancellable.isCancelled {
                self.responseQueue.async {
                    if !cancellable.isCancelled {
                        onSuccess(response)
                    }
                }
            }
        }

        let errorResponseQueue = { (error: PreviewError) in
            if !cancellable.isCancelled {
                self.responseQueue.async {
                    if !cancellable.isCancelled {
                        onError(error)
                    }
                }
            }
        }

        if let url = self.extractURL(text: text) {
            workQueue.async {
                if cancellable.isCancelled {return}

                if let result = self.cache.slp_getCachedResponse(url: url.absoluteString) {
                    successResponseQueue(result)
                } else {

                    self.unshortenURL(url, cancellable: cancellable, completion: { unshortened in
                        if let result = self.cache.slp_getCachedResponse(url: unshortened.absoluteString) {
                            successResponseQueue(result)
                        } else {

                            var result: [SwiftLinkResponseKey: Any] = [:]
                            result[.url] = url
                            result[.finalUrl] = self.extractInURLRedirectionIfNeeded(unshortened)

                            self.extractInfo(response: result, cancellable: cancellable, completion: {

                                result[.title] = $0[.title]
                                result[.description] = $0[.description]
                                result[.image] = $0[.image]
                                result[.images] = $0[.images]
                                result[.icon] = $0[.icon]

                                self.cache.slp_setCachedResponse(url: unshortened.absoluteString, response: result)
                                self.cache.slp_setCachedResponse(url: url.absoluteString, response: result)

                                successResponseQueue(result)
                            }, onError: errorResponseQueue)
                        }
                    }, onError: errorResponseQueue)
                }
            }
        } else {
            onError(.noURLHasBeenFound(text))
        }

        return cancellable
    }

    /*
     Extract url redirection inside the GET query.
     Like https://www.dji.com/404?url=http%3A%2F%2Fwww.dji.com%2Fmatrice600-pro%2Finfo#specs -> http://www.dji.com/de/matrice600-pro/info#specs
     */
    private func extractInURLRedirectionIfNeeded(_ url: URL) -> URL {
        var url = url
        var absoluteString = url.absoluteString + "&id=12"

        if let range = absoluteString.range(of: "url="),
            let lastChar = absoluteString.last,
            let lastCharIndex = absoluteString.range(of: String(lastChar), options: .backwards, range: nil, locale: nil) {
            absoluteString = String(absoluteString[range.upperBound ..< lastCharIndex.upperBound])

            if let range = absoluteString.range(of: "&"),
                let firstChar = absoluteString.first,
                let firstCharIndex = absoluteString.index(of: firstChar) {
                absoluteString = String(absoluteString[firstCharIndex ..< absoluteString.index(before: range.upperBound)])

                if let decoded = absoluteString.removingPercentEncoding, let newURL = URL(string: decoded) {
                    url = newURL
                }
            }

        }

        return url
    }
    
    //Objective-C wrapper for preview method.  Core incompataility is use of Swift specific enum types in closures.
    //Returns a dictionary of rsults rather than enum for success, and an NSError object on error that encodes the local error description on error
    /*
     Keys for the dictionary are derived from the enum names above.  That enum def is canonical, below is a convenience comment
     url
     finalUrl
     canonicalUrl
     title
     description
     image
     images
     icon
     
     */
    @objc @discardableResult open func previewLink(_ text: String, onSuccess: @escaping (Dictionary<String, Any>) -> Void, onError: @escaping (NSError) -> Void) -> Cancellable {
        
        func success (_ result: Response) -> Void {
            var ResponseData = [String: Any]()
            for item in result {
                ResponseData.updateValue(item.value, forKey: item.key.rawValue)
            }
            onSuccess(ResponseData)
        }
        
        
        func failure (_ theError: PreviewError) -> Void  {
            var errorCode: Int
            errorCode = 1
            
            switch theError {
            case .noURLHasBeenFound:
                errorCode = 1
            case .invalidURL:
                errorCode = 2
            case .cannotBeOpened:
                errorCode = 3
            case .parseError:
                errorCode = 4
            }
            
            onError(NSError(domain: "SwiftLinkPreviewDomain",
                            code: errorCode,
                            userInfo: [NSLocalizedDescriptionKey: theError.description]))
        }
        
        return self.preview(text, onSuccess: success, onError: failure)
    }
}

// Extraction functions
extension SwiftLinkPreview {

    // Extract first URL from text
    open func extractURL(text: String) -> URL? {
        do {
            let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let range = NSRange(location: 0, length: text.utf16.count)
            let matches = detector.matches(in: text, options: [], range: range)

            return matches.compactMap { $0.url }.first
        } catch {
            return nil
        }
    }

    // Unshorten URL by following redirections
    fileprivate func unshortenURL(_ url: URL, cancellable: Cancellable, completion: @escaping (URL) -> Void, onError: @escaping (PreviewError) -> Void) {

        if cancellable.isCancelled {return}

        var task: URLSessionDataTask?
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        task = session.dataTask(with: request, completionHandler: { data, response, error in
            if error != nil {
                self.workQueue.async {
                    if !cancellable.isCancelled {
                        onError(.cannotBeOpened("\(url.absoluteString): \(error.debugDescription)"))
                    }
                }
                task = nil
            } else {
                if let finalResult = response?.url {
                    if (finalResult.absoluteString == url.absoluteString) {
                        self.workQueue.async {
                            if !cancellable.isCancelled {
                                completion(url)
                            }
                        }
                        task = nil
                    } else {
                        task?.cancel()
                        task = nil
                        self.unshortenURL(finalResult, cancellable: cancellable, completion: completion, onError: onError)
                    }
                } else {
                    self.workQueue.async {
                        if !cancellable.isCancelled {
                            completion(url)
                        }
                    }
                    task = nil
                }
            }
        })

        if let task = task {
            task.resume()
        } else {
            self.workQueue.async {
                if !cancellable.isCancelled {
                    onError(.cannotBeOpened(url.absoluteString))
                }
            }
        }
    }

    // Extract HTML code and the information contained on it
    fileprivate func extractInfo(response: Response, cancellable: Cancellable, completion: @escaping (Response) -> Void, onError: (PreviewError) -> ()) {

        guard !cancellable.isCancelled, let url = response[.finalUrl] as? URL else { return }

        if url.path.hasImageExt() {
            var result = response

            result[.title] = ""
            result[.description] = ""
            result[.images] = [url.absoluteString]
            result[.image] = url.absoluteString
            result[.canonicalUrl] = url.host ?? ""

            completion(result)
        } else {
            let sourceUrl = url.absoluteString.hasPrefix("http://") || url.absoluteString.hasPrefix("https://") ? url : URL(string: "http://\(url)")
            do {
                guard let sourceUrl = sourceUrl else {
                    if !cancellable.isCancelled { onError(.invalidURL(url.absoluteString)) }
                    return
                }
                let data = try Data(contentsOf: sourceUrl)
                var source: NSString? = nil
                NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: &source, usedLossyConversion: nil)

                if let source = source {
                    if !cancellable.isCancelled {
                        self.parseHtmlString(source as String, response: response, completion: completion)
                    }
                } else {
                    if !cancellable.isCancelled {
                        onError(.parseError(sourceUrl.absoluteString))
                    }
                }
            } catch let error {
                if !cancellable.isCancelled {
                    let details = "\(sourceUrl?.absoluteString ?? String()): \(error.localizedDescription)"
                    onError(.cannotBeOpened(details))
                }
            }
        }
    }


    private func parseHtmlString(_ htmlString: String, response: Response, completion: @escaping (Response) -> Void) {
        completion(self.performPageCrawling(htmlString, response: response))
    }

    // Perform the page crawiling
    private func performPageCrawling(_ htmlCode: String, response: Response) -> Response {
        var result = response
        //TODO: Consider as error if failed to parse?
        if let doc = try? HTMLDocument(string: htmlCode) {
            let metatags = doc.xpath("//meta")
            let links = doc.xpath("//link")
            result = self.crawlForCanonicalUrl(links: links, response: result)
            result = self.crawlForTitle(doc, meta: metatags, response: result)
            result = self.crawlForDescription(doc, meta: metatags, response: result)
            result = self.crawlForImages(doc, meta: metatags, response: result)
            result = self.crawlForIcon(links: links, response: result)
        }
        return result
    }
}

extension SwiftLinkPreview {
    
    // Searches for canonical url in <link> tags and uses its host.
    // If nothing found uses final url host.
    internal func crawlForCanonicalUrl(links: NodeSet, response: Response) -> Response {
        var result = response
        var canonicalHost = (response[.finalUrl] as? URL)?.host
        for link in links {
            if let rel = link["rel"], let href = link["href"] {
                if rel == "canonical", let hrefHost = URL(string: href)?.host {
                    canonicalHost = hrefHost
                    break
                }
            }
        }
        result[.canonicalUrl] = canonicalHost ?? ""
        return result
    }
    
    // Searches for value of the given key in <meta> tags that satisfies the given predicate.
    // Checks are case insensitive. Content with og: and twitter: prefixes is prioritized.
    // If nothing found returns nil.
    internal func crawlMetatags(_ metatags: NodeSet, for key: String,
                                 predicate: ((String) -> Bool)? = nil) -> String? {
        let key = key.lowercased()
        var value: String? = nil
        for metatag in metatags {
            if let content = metatag["content"] {
                let trimmedContent = content.extendedTrim
                if let property = metatag["property"], property == "og:" + key {
                    if predicate?(trimmedContent) ?? true {
                        return trimmedContent
                    }
                }
                if let name = metatag["name"], name == ("twitter:" + key) {
                    if predicate?(trimmedContent) ?? true {
                        return trimmedContent
                    }
                }
                if let name = metatag["name"], name.lowercased() == key {
                    if value == nil && predicate?(trimmedContent) ?? true {
                        value = trimmedContent
                    }
                }
                if let itemprop = metatag["itemprop"], itemprop.lowercased() == key {
                    if value == nil && predicate?(trimmedContent) ?? true {
                        value = trimmedContent
                    }
                }
            }
        }
        return value
    }
    
    // Searches for text in the given tags of HTMLDocument.
    // The result is nonempty by default. In general, text length should be more or equal than the given minLength.
    // Unwanted content is ignored, such as inside <noscript>, containing <script> and <style>.
    // If nothing found returns nil.
    func crawlForText(_ doc: HTMLDocument, tags: [String], minLength: Int = 1) -> String? {
        var xpath = ""
        for (index, tag) in tags.enumerated() {
            if (index != 0) {
                xpath.append(" | ")
            }
            xpath.append("//\(tag)[not(ancestor::noscript) and not(descendant::script) and not(descendant::style)]")
        }
        let firstMatch = doc.xpath(xpath).first(where: { $0.stringValue.extendedTrim.count >= minLength })
        return firstMatch?.stringValue.extendedTrim
    }

    // Consequentially searches for nonempty title in <meta>, <title>, <h1>, <h2> tags.
    // If nothing found uses canonical url(host).
    internal func crawlForTitle(_ doc: HTMLDocument, meta metatags: NodeSet, response: Response) -> Response {
        var result = response
        if let titleFromMeta = self.crawlMetatags(metatags, for:"title"), !titleFromMeta.isEmpty {
            result[.title] = titleFromMeta
        } else if let titleFromTag = doc.title?.extendedTrim, !titleFromTag.isEmpty {
            result[.title] = titleFromTag
        } else if let titleFromH1 = self.crawlForText(doc, tags: ["h1"]) {
            result[.title] = titleFromH1
        } else if let titleFromH2 = self.crawlForText(doc, tags: ["h2"]) {
            result[.title] = titleFromH2
        } else {
            result[.title] = response[.canonicalUrl] as? String ?? ""
        }
        return result
    }

    // Consequentially searches for description in <meta>, <p>, <h3>-<h6>, <div> tags.
    // If nothing found uses an empty string.
    internal func crawlForDescription(_ doc: HTMLDocument, meta metatags: NodeSet, response: Response) -> Response {
        var result = response
        if let descFromMeta = self.crawlMetatags(metatags, for: "description") {
            result[.description] = descFromMeta
        } else if let descFromP = self.crawlForText(doc, tags: ["p"], minLength: SwiftLinkPreview.descMinLength) {
            result[.description] = descFromP
        } else if let descFromH = self.crawlForText(doc, tags: ["h3", "h4", "h5", "h6"], minLength: SwiftLinkPreview.descMinLength) {
            result[.description] = descFromH
        } else if let descFromDiv = self.crawlForText(doc, tags: ["div"], minLength: SwiftLinkPreview.descMinLength) {
            result[.description] = descFromDiv
        } else {
            result[.description] = ""
        }
        return result
    }
    
    // Searches for icon in links.
    internal func crawlForIcon(links: NodeSet, response: Response) -> Response {
        var result = response
        for link in links {
            if let rel = link["rel"], let href = link["href"] {
                if rel.contains("icon") || rel.contains("shortcut") || rel.contains("apple-touch") {
                    result[.icon] = self.absolutePath(href, response: response)
                    break
                }
            }
        }
        return result
    }
    
    internal func crawlForImages(_ doc: HTMLDocument, meta metatags: NodeSet, response: Response) -> Response {
        func isImagePath(string: String) -> Bool {
            let absolutePath = self.absolutePath(string, response: response)
            guard let url = URL(string: absolutePath) else {
                return false
            }
            return url.path.hasImageExt() || url.path.hasNoExt()
        }
        
        var result = response
        var imagePaths: [String] = []
        if let imagePathFromMeta = self.crawlMetatags(metatags, for: "image", predicate: isImagePath) {
            let absolutePath = self.absolutePath(imagePathFromMeta, response: response)
            imagePaths.append(absolutePath)
        }
        let images = doc.xpath("//img[not(ancestor::noscript)]")
        for image in images {
            if let src = image["src"], isImagePath(string: src) {
                let absolutePath = self.absolutePath(src, response: response)
                imagePaths.append(absolutePath)
            }
        }
        result[.images] = imagePaths
        result[.image] = imagePaths.first ?? ""
        return result
    }

    // Makes absolute path from relative if needed.
    fileprivate func absolutePath(_ path: String, response: Response) -> String {
        if let url = URL(string: path), url.scheme == nil {
            // Path is relative.
            if let finalUrl = response[.finalUrl] as? URL, let absoluteUrl = URL(string: path, relativeTo: finalUrl) {
                return absoluteUrl.absoluteString
            }
        }
        return path
    }
}

extension SwiftLinkPreview: URLSessionDataDelegate {

    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest,
                           completionHandler: @escaping (URLRequest?) -> Void) {
        var request = request
        request.httpMethod = "GET"
        completionHandler(request)
    }
}
