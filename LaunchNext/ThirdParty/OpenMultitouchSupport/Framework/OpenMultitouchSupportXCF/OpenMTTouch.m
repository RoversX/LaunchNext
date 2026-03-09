//
//  OpenMTTouch.m
//  OpenMultitouchSupport
//
//  Created by Takuto Nakamura on 2019/07/11.
//  Copyright © 2019 Takuto Nakamura. All rights reserved.
//

#import "OpenMTTouchInternal.h"

@implementation OpenMTTouch

- (id)initWithMTTouch:(MTTouch *)touch {
    if (self = [super init]) {
        _identifier = touch->identifier;
        _state = touch->state;
        _posX = touch->normalizedPosition.position.x;
        _posY = touch->normalizedPosition.position.y;
        _velX = touch->normalizedPosition.velocity.x;
        _velY = touch->normalizedPosition.velocity.y;
        _total = touch->total;
        _pressure = touch->pressure;
        _minorAxis = touch->minorAxis;
        _majorAxis = touch->majorAxis;
        _angle = touch->angle;
        _density = touch->density;
        _timestamp = touch->timestamp;
    }
    return self;
}

- (NSString *)description {
    NSMutableString *str = [[NSMutableString alloc] initWithString:@""];
    [str appendString:[NSString stringWithFormat:@"ID:, %i, ", _identifier]];
    [str appendString:[NSString stringWithFormat:@"State: %lu, ", _state]];
    [str appendString:[NSString stringWithFormat:@"Position: [%f, %f], ", _posX, _posY]];
    [str appendString:[NSString stringWithFormat:@"Velocity: [%f, %f], ", _velX, _velY]];
    [str appendString:[NSString stringWithFormat:@"Total: %f, ", _total]];
    [str appendString:[NSString stringWithFormat:@"Pressure: %f, ", _pressure]];
    [str appendString:[NSString stringWithFormat:@"Minor: %f, ", _minorAxis]];
    [str appendString:[NSString stringWithFormat:@"Major: %f, ", _majorAxis]];
    [str appendString:[NSString stringWithFormat:@"Angle: %f, ", _angle]];
    [str appendString:[NSString stringWithFormat:@"Density: %f, ", _density]];
    [str appendString:[NSString stringWithFormat:@"Timestamp: %lf", _timestamp]];
    return str;
}

@end
