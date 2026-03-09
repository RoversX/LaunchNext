//
//  OpenMTEvent.h
//  OpenMultitouchSupport
//
//  Created by Takuto Nakamura on 2019/07/11.
//  Copyright © 2019 Takuto Nakamura. All rights reserved.
//

#ifndef OpenMTEvent_h
#define OpenMTEvent_h

#import <Foundation/Foundation.h>

@interface OpenMTEvent: NSObject

@property (strong, readonly) NSArray *touches;
@property (assign, readonly) int deviceID;
@property (assign, readonly) int frameID;
@property (assign, readonly) double timestamp;

@end

typedef void (^OpenMTEventCallback)(OpenMTEvent *event);

#endif /* OpenMTEvent_h */
