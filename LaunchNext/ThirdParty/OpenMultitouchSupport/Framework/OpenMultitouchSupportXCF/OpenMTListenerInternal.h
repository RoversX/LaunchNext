//
//  OpenMTListenerInternal.h
//  OpenMultitouchSupport
//
//  Created by Takuto Nakamura on 2019/07/11.
//  Copyright © 2019 Takuto Nakamura. All rights reserved.
//

#ifndef OpenMTListenerInternal_h
#define OpenMTListenerInternal_h

#import "OpenMTListener.h"
#import "OpenMTEventInternal.h"

@interface OpenMTListener()

- (instancetype)initWithTarget:(id)target selector:(SEL)selector;
- (void)listenToEvent:(OpenMTEvent *)event;
- (BOOL)dead;

@end

#endif /* OpenMTListenerInternal_h */
