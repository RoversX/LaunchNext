//
//  OpenMTEventInternal.h
//  OpenMultitouchSupport
//
//  Created by Takuto Nakamura on 2019/07/11.
//  Copyright © 2019 Takuto Nakamura. All rights reserved.
//

#ifndef OpenMTEventInternal_h
#define OpenMTEventInternal_h

#import "OpenMTEvent.h"

@interface OpenMTEvent()

@property (strong, readwrite) NSArray *touches;
@property (assign, readwrite) int deviceID;
@property (assign, readwrite) int frameID;
@property (assign, readwrite) double timestamp;

@end

#endif /* OpenMTEventInternal_h */
