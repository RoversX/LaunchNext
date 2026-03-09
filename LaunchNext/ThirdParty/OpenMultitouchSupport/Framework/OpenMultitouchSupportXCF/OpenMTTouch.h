//
//  OpenMTTouch.h
//  OpenMultitouchSupport
//
//  Created by Takuto Nakamura on 2019/07/11.
//  Copyright © 2019 Takuto Nakamura. All rights reserved.
//

#ifndef OpenMTTouch_h
#define OpenMTTouch_h

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, OpenMTState) {
    OpenMTStateNotTouching = 0,
    OpenMTStateStarting,
    OpenMTStateHovering,
    OpenMTStateMaking,
    OpenMTStateTouching,
    OpenMTStateBreaking,
    OpenMTStateLingering,
    OpenMTStateLeaving
};

@interface OpenMTTouch: NSObject

@property (assign, readonly) int identifier;
@property (assign, readonly) OpenMTState state;
@property (assign, readonly) float posX, posY;
@property (assign, readonly) float velX, velY;
@property (assign, readonly) float total;
@property (assign, readonly) float pressure;
@property (assign, readonly) float minorAxis, majorAxis;
@property (assign, readonly) float angle;
@property (assign, readonly) float density;
@property (assign, readonly) double timestamp;

@end

#endif /* OpenMTTouch_h */
