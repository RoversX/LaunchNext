//
//  OpenMTTouchInternal.h
//  OpenMultitouchSupport
//
//  Created by Takuto Nakamura on 2019/07/11.
//  Copyright © 2019 Takuto Nakamura. All rights reserved.
//

#ifndef OpenMTTouchInternal_h
#define OpenMTTouchInternal_h

#import "OpenMTTouch.h"
#import "OpenMTInternal.h"

@interface OpenMTTouch()

- (id)initWithMTTouch:(MTTouch *)touch;

@property (assign, readwrite) int identifier;
@property (assign, readwrite) OpenMTState state;
@property (assign, readwrite) float posX, posY;
@property (assign, readwrite) float velX, velY;
@property (assign, readwrite) float total;
@property (assign, readwrite) float pressure;
@property (assign, readwrite) float minorAxis, majorAxis;
@property (assign, readwrite) float angle;
@property (assign, readwrite) float density;
@property (assign, readwrite) double timestamp;

@end

#endif /* OpenMTTouchInternal_h */
