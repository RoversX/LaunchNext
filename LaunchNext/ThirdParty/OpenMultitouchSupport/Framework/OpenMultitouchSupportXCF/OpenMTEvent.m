//
//  OpenMTEvent.m
//  OpenMultitouchSupport
//
//  Created by Takuto Nakamura on 2019/07/11.
//  Copyright © 2019 Takuto Nakamura. All rights reserved.
//

#import "OpenMTEventInternal.h"

@implementation OpenMTEvent

- (NSString *)description {
    NSMutableString *str = [[NSMutableString alloc] initWithString:@""];
    [str appendString:[NSString stringWithFormat:@"Touches: %@, ", _touches.description]];
    [str appendString:[NSString stringWithFormat:@"Device ID: %@, ", _deviceID]];
    [str appendString:[NSString stringWithFormat:@"Frame ID: %i, ", _frameID]];
    [str appendString:[NSString stringWithFormat:@"Timestamp: %f", _timestamp]];
    return str;
}

@end
