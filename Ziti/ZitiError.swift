//
//  ZitiError.swift
//  ZitiPacketTunnel
//
//  Created by David Hart on 3/2/19.
//  Copyright © 2019 David Hart. All rights reserved.
//

import Foundation

class ZitiError : LocalizedError, CustomNSError {
    public static var errorDomain:String = "ZitiError"
    public static let URLError = -1000
    public static let AuthRequired = 401
    public static let NoSuchFile = 260
    
    public var errorDescription:String?
    public var errorCode:Int = -1
    public var errorUserInfo:[String:Any] = [:]
    
    init(_ errorDescription:String, errorCode:Int=Int(-1)) {
        NSLog("\(errorCode) \(errorDescription)")
        self.errorDescription = errorDescription
        self.errorCode = errorCode
    }
}
