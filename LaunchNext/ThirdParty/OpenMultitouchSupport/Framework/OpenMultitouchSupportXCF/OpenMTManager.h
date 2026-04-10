//
//  OpenMTManager.h
//  OpenMultitouchSupport
//
//  Created by Takuto Nakamura on 2019/07/11.
//  Copyright © 2019 Takuto Nakamura. All rights reserved.
//

#ifndef OpenMTManager_h
#define OpenMTManager_h

#import <Foundation/Foundation.h>
#import <OpenMultitouchSupportXCF/OpenMTListener.h>
#import <OpenMultitouchSupportXCF/OpenMTEvent.h>

@interface OpenMTDeviceInfo: NSObject
@property (nonatomic, readonly) NSString *deviceName;
@property (nonatomic, readonly) NSString *deviceID;
@property (nonatomic, readonly) BOOL isBuiltIn;
@end

@interface OpenMTManager: NSObject

+ (BOOL)systemSupportsMultitouch;
+ (OpenMTManager *)sharedManager;

- (NSArray<OpenMTDeviceInfo *> *)availableDevices;
- (void)refreshDevices;
- (BOOL)selectDevice:(OpenMTDeviceInfo *)deviceInfo;
- (BOOL)selectDevices:(NSArray<OpenMTDeviceInfo *> *)deviceInfos;
- (NSArray<OpenMTDeviceInfo *> *)selectedDevices;
- (OpenMTDeviceInfo *)currentDevice;

- (OpenMTListener *)addListenerWithTarget:(id)target selector:(SEL)selector;
- (void)removeListener:(OpenMTListener *)listener;

- (BOOL)isHapticEnabled;
- (BOOL)setHapticEnabled:(BOOL)enabled;

// Advanced haptic feedback methods
- (BOOL)triggerRawHaptic:(SInt32)actuationID unknown1:(UInt32)unknown1 unknown2:(Float32)unknown2 unknown3:(Float32)unknown3;

@end

#endif /* OpenMTManager_h */
