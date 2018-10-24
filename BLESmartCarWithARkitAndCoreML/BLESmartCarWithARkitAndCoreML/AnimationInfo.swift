//
//  AnimationInfo.swift
//  BLESmartCarWithARkitAndCoreML
//
//  Created by Andy W on 24/10/2018.
//  Copyright © 2018 Andy W. All rights reserved.
//

import Foundation
import SceneKit

struct AnimationInfo {
    var startTime: TimeInterval
    var duration: TimeInterval
    var initialModelPosition: simd_float3
    var finalModelPosition: simd_float3
    var initialModelOrientation: simd_quatf
    var finalModelOrientation: simd_quatf
}
