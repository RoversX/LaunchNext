//
//  OpenMTManager.m
//  OpenMultitouchSupport
//
//  Created by Takuto Nakamura on 2019/07/11.
//  Copyright © 2019 Takuto Nakamura. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <IOKit/IOKitLib.h>

#import "OpenMTManagerInternal.h"
#import "OpenMTListenerInternal.h"
#import "OpenMTTouchInternal.h"
#import "OpenMTEventInternal.h"
#import "OpenMTInternal.h"

@implementation OpenMTDeviceInfo

- (instancetype)initWithDeviceRef:(MTDeviceRef)deviceRef {
    if (self = [super init]) {
        // Get device ID
        uint64_t deviceID;
        OSStatus err = MTDeviceGetDeviceID(deviceRef, &deviceID);
        if (!err) {
            _deviceID = [NSString stringWithFormat:@"%llu", deviceID];
        } else {
            _deviceID = @"Unknown";
        }
        // Determine if built-in
        _isBuiltIn = MTDeviceIsBuiltIn ? MTDeviceIsBuiltIn(deviceRef) : YES;
        // Get family ID for precise device identification
        int familyID = 0;
        MTDeviceGetFamilyID(deviceRef, &familyID);
        // Determine device name based on family ID mapping.
        if (familyID == 98 || familyID == 99 || familyID == 100) {
            // Built-in trackpad (older models)
            _deviceName = @"MacBook Trackpad";
        } else if (familyID == 101) {
            // Retina MacBook Pro trackpad
            _deviceName = @"MacBook Trackpad";
        } else if (familyID == 102) {
            // Retina MacBook with Force Touch trackpad (2015)
            _deviceName = @"MacBook Trackpad";
        } else if (familyID == 103) {
            // Retina MacBook Pro 13" with Force Touch trackpad (2015)
            _deviceName = @"MacBook Trackpad";
        } else if (familyID == 104) {
            // MacBook trackpad variant
            _deviceName = @"MacBook Trackpad";
        } else if (familyID == 105) {
            // MacBook with Touch Bar
            _deviceName = @"Touch Bar";
        } else if (familyID == 109) {
            // M4 Macbook Pro Trackpad
            _deviceName = @"MacBook Trackpad";
        } else if (familyID == 112 || familyID == 113) {
            // Magic Mouse & Magic Mouse 2/3
            _deviceName = @"Magic Mouse";
        } else if (familyID == 128 || familyID == 129 || familyID == 130) {
            // Magic Trackpad, Magic Trackpad 2, Magic Trackpad 3
            _deviceName = @"Magic Trackpad";
        } else {
            // Unknown device - use dimensions to make an educated guess
            int width = 0, height = 0;
            MTDeviceGetSensorSurfaceDimensions(deviceRef, &width, &height);
            // Heuristic: trackpads are typically wider than tall and have reasonable dimensions
            // Touch Bar is very wide and narrow (>1000 width, <100 height)
            // Regular trackpads are usually wider than tall but not extremely so
            if (width > 1000 && height < 100) {
                _deviceName = [NSString stringWithFormat:@"Unknown Touch Bar (FamilyID: %d)", familyID];
            } else if (width > height && width > 50 && height > 20) {
                // Likely a trackpad: wider than tall, reasonable dimensions
                _deviceName = [NSString stringWithFormat:@"Unknown Trackpad (FamilyID: %d)", familyID];
            } else {
                // Probably not a trackpad
                _deviceName = [NSString stringWithFormat:@"Unknown Device (FamilyID: %d)", familyID];
            }
        }
    }
    return self;
}

@end

@interface OpenMTManager()

@property (strong, readwrite) NSMutableArray *listeners;
@property (assign, readwrite) MTDeviceRef device;
@property (strong, readwrite) NSArray<OpenMTDeviceInfo *> *availableDeviceInfos;
@property (strong, readwrite) OpenMTDeviceInfo *currentDeviceInfo;

@end

@implementation OpenMTManager

+ (BOOL)systemSupportsMultitouch {
    return MTDeviceIsAvailable();
}

+ (OpenMTManager *)sharedManager {
    static OpenMTManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = self.new;
    });
    return sharedManager;
}

- (instancetype)init {
    if (self = [super init]) {
        self.listeners = NSMutableArray.new;
        [self enumerateDevices];
        
        [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(willSleep:) name:NSWorkspaceWillSleepNotification object:nil];
        [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(didWakeUp:) name:NSWorkspaceDidWakeNotification object:nil];
    }
    return self;
}


- (void)enumerateDevices {
    NSMutableArray<OpenMTDeviceInfo *> *devices = [NSMutableArray array];
    
    if (MTDeviceCreateList) {
        CFArrayRef deviceList = MTDeviceCreateList();
        if (deviceList) {
            CFIndex count = CFArrayGetCount(deviceList);
            for (CFIndex i = 0; i < count; i++) {
                MTDeviceRef deviceRef = (MTDeviceRef)CFArrayGetValueAtIndex(deviceList, i);
                // No need to retain deviceRef for device info objects
                OpenMTDeviceInfo *deviceInfo = [[OpenMTDeviceInfo alloc] initWithDeviceRef:deviceRef];
                [devices addObject:deviceInfo];
            }
            CFRelease(deviceList);
        }
    }
    
    // Fallback to default device if no devices found
    if (devices.count == 0 && MTDeviceIsAvailable()) {
        MTDeviceRef defaultDevice = MTDeviceCreateDefault();
        if (defaultDevice) {
            OpenMTDeviceInfo *deviceInfo = [[OpenMTDeviceInfo alloc] initWithDeviceRef:defaultDevice];
            [devices addObject:deviceInfo];
            // Don't release defaultDevice here since we store the reference
        }
    }
    
    self.availableDeviceInfos = [devices copy];
    if (devices.count > 0) {
        self.currentDeviceInfo = devices[0];
    }
}

- (void)makeDevice {
    if (self.currentDeviceInfo && self.currentDeviceInfo.deviceID) {
        // Always reacquire a fresh deviceRef for the selected deviceID
        MTDeviceRef foundDevice = NULL;
        if (MTDeviceCreateList) {
            CFArrayRef deviceList = MTDeviceCreateList();
            if (deviceList) {
                CFIndex count = CFArrayGetCount(deviceList);
                for (CFIndex i = 0; i < count; i++) {
                    MTDeviceRef deviceRef = (MTDeviceRef)CFArrayGetValueAtIndex(deviceList, i);
                    uint64_t deviceID = 0;
                    OSStatus err = MTDeviceGetDeviceID(deviceRef, &deviceID);
                    if (!err) {
                        NSString *devID = [NSString stringWithFormat:@"%llu", deviceID];
                        if ([devID isEqualToString:self.currentDeviceInfo.deviceID]) {
                            foundDevice = deviceRef;
                            CFRetain(foundDevice); // Retain for our use
                            break;
                        }
                    }
                }
                CFRelease(deviceList);
            }
        }
        if (!foundDevice && MTDeviceIsAvailable()) {
            MTDeviceRef defaultDevice = MTDeviceCreateDefault();
            if (defaultDevice) {
                uint64_t deviceID = 0;
                OSStatus err = MTDeviceGetDeviceID(defaultDevice, &deviceID);
                if (!err) {
                    NSString *devID = [NSString stringWithFormat:@"%llu", deviceID];
                    if ([devID isEqualToString:self.currentDeviceInfo.deviceID]) {
                        foundDevice = defaultDevice;
                    } else {
                        MTDeviceRelease(defaultDevice);
                        defaultDevice = NULL;
                    }
                } else {
                    MTDeviceRelease(defaultDevice);
                    defaultDevice = NULL;
                }
            }
        }
        // Release previous device if any
        if (self.device) {
            MTDeviceRelease(self.device);
            self.device = NULL;
        }
        self.device = foundDevice;
        if (self.device) {
            /*
            uuid_t guid;
            OSStatus err = MTDeviceGetGUID(self.device, &guid);
            if (!err) {
                uuid_string_t val;
                uuid_unparse(guid, val);
                NSLog(@"GUID: %s", val);
            }
            int type;
            err = MTDeviceGetDriverType(self.device, &type);
            if (!err) NSLog(@"Driver Type: %d", type);
            uint64_t deviceID;
            err = MTDeviceGetDeviceID(self.device, &deviceID);
            if (!err) NSLog(@"DeviceID: %llu", deviceID);
            int familyID;
            err = MTDeviceGetFamilyID(self.device, &familyID);
            if (!err) NSLog(@"FamilyID: %d", familyID);
            int width, height;
            err = MTDeviceGetSensorSurfaceDimensions(self.device, &width, &height);
            if (!err) NSLog(@"Surface Dimensions: %d x %d ", width, height);
            int rows, cols;
            err = MTDeviceGetSensorDimensions(self.device, &rows, &cols);
            if (!err) NSLog(@"Dimensions: %d x %d ", rows, cols);
            bool isOpaque = MTDeviceIsOpaqueSurface(self.device);
            NSLog(isOpaque ? @"Opaque: true" : @"Opaque: false");
             */
            // MTPrintImageRegionDescriptors(self.device); work
        }
    }
}

//- (void)handlePathEvent:(OpenMTTouch *)touch {
//    NSLog(@"%@", touch.description);
//}

- (void)handleMultitouchEvent:(OpenMTEvent *)event {
    for (int i = 0; i < (int)self.listeners.count; i++) {
        OpenMTListener *listener = self.listeners[i];
        if (listener.dead) {
            [self removeListener:listener];
            continue;
        }
        if (!listener.listening) {
            continue;
        }
        dispatchResponse(^{
            [listener listenToEvent:event];
        });
    }
}

- (void)startHandlingMultitouchEvents {
    [self makeDevice];
    @try {
        MTRegisterContactFrameCallback(self.device, contactEventHandler); // work
        // MTEasyInstallPrintCallbacks(self.device, YES, NO, NO, NO, NO, NO); // work
        // MTRegisterPathCallback(self.device, pathEventHandler); // work
        // MTRegisterMultitouchImageCallback(self.device, MTImagePrintCallback); // not work
        MTDeviceStart(self.device, 0);
    } @catch (NSException *exception) {
        NSLog(@"Failed Start Handling Multitouch Events");
    }
}

- (void)stopHandlingMultitouchEvents {
    if (!MTDeviceIsRunning(self.device)) { return; }
    @try {
        MTUnregisterContactFrameCallback(self.device, contactEventHandler); // work
        // MTUnregisterPathCallback(self.device, pathEventHandler); // work
        // MTUnregisterImageCallback(self.device, MTImagePrintCallback); // not work
        MTDeviceStop(self.device);
        MTDeviceRelease(self.device);
        self.device = NULL;
    } @catch (NSException *exception) {
        NSLog(@"Failed Stop Handling Multitouch Events");
    }
}

- (void)willSleep:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self stopHandlingMultitouchEvents];
    });
}

- (void)didWakeUp:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self startHandlingMultitouchEvents];
    });
}

// Public Functions
- (NSArray<OpenMTDeviceInfo *> *)availableDevices {
    return self.availableDeviceInfos;
}

- (BOOL)selectDevice:(OpenMTDeviceInfo *)deviceInfo {
    if (![self.availableDeviceInfos containsObject:deviceInfo]) {
        return NO;
    }
    
    // Stop current device if running
    BOOL wasRunning = self.device && MTDeviceIsRunning(self.device);
    if (wasRunning) {
        [self stopHandlingMultitouchEvents];
    }
    
    // Switch to new device
    self.currentDeviceInfo = deviceInfo;
    
    // Restart if it was running
    if (wasRunning) {
        [self startHandlingMultitouchEvents];
    }
    
    return YES;
}

- (OpenMTDeviceInfo *)currentDevice {
    return self.currentDeviceInfo;
}

- (OpenMTListener *)addListenerWithTarget:(id)target selector:(SEL)selector {
    __block OpenMTListener *listener = nil;
    dispatchSync(dispatch_get_main_queue(), ^{
        if (!self.class.systemSupportsMultitouch) { return; }
        listener = [[OpenMTListener alloc] initWithTarget:target selector:selector];
        if (self.listeners.count == 0) {
            [self startHandlingMultitouchEvents];
        }
        [self.listeners addObject:listener];
    });
    return listener;
}

- (void)removeListener:(OpenMTListener *)listener {
    dispatchSync(dispatch_get_main_queue(), ^{
        [self.listeners removeObject:listener];
        if (self.listeners.count == 0) {
            [self stopHandlingMultitouchEvents];
        }
    });
}

- (BOOL)isHapticEnabled {
    if (!self.device) {
        [self makeDevice];
    }
    if (!self.device) {
        return NO;
    }
    
    MTActuatorRef actuator = MTDeviceGetMTActuator(self.device);
    if (!actuator) {
        return NO;
    }
    
    return MTActuatorGetSystemActuationsEnabled(actuator);
}

- (BOOL)setHapticEnabled:(BOOL)enabled {
    if (!self.device) {
        [self makeDevice];
    }
    if (!self.device) {
        return NO;
    }
    
    MTActuatorRef actuator = MTDeviceGetMTActuator(self.device);
    if (!actuator) {
        return NO;
    }
    
    OSStatus result = MTActuatorSetSystemActuationsEnabled(actuator, enabled);
    return result == noErr;
}

- (UInt64)findBuiltInTrackpadDeviceID {
    // Use IOKit to find the built-in trackpad (HapticKey approach)
    io_iterator_t iterator = IO_OBJECT_NULL;
    const CFMutableDictionaryRef matchingRef = IOServiceMatching("AppleMultitouchDevice");
    const kern_return_t result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingRef, &iterator);
    
    if (result != KERN_SUCCESS) {
        NSLog(@"❌ Failed to get matching services: 0x%x", result);
        return 0;
    }
    
    UInt64 foundDeviceID = 0;
    io_service_t service = IO_OBJECT_NULL;
    
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        CFMutableDictionaryRef propertiesRef = NULL;
        const kern_return_t propResult = IORegistryEntryCreateCFProperties(service, &propertiesRef, CFAllocatorGetDefault(), 0);
        
        if (propResult != KERN_SUCCESS) {
            IOObjectRelease(service);
            continue;
        }
        
        NSDictionary *properties = (__bridge_transfer NSDictionary *)propertiesRef;
        NSLog(@"🔍 Found multitouch device: %@", properties[@"Product"]);
        
        // Look for actuation-supported, built-in device (trackpad)
        NSNumber *actuationSupported = properties[@"ActuationSupported"];
        NSNumber *mtBuiltIn = properties[@"MT Built-In"];
        
        if (actuationSupported.boolValue && mtBuiltIn.boolValue) {
            NSNumber *multitouchID = properties[@"Multitouch ID"];
            foundDeviceID = multitouchID.unsignedLongLongValue;
            NSLog(@"✅ Found built-in trackpad: %@ (ID: 0x%llx)", properties[@"Product"], foundDeviceID);
            IOObjectRelease(service);
            break;
        } else {
            NSLog(@"⏭️ Skipping device %@ (ActuationSupported: %@, Built-In: %@)", 
                  properties[@"Product"], actuationSupported, mtBuiltIn);
        }
        
        IOObjectRelease(service);
    }
    
    IOObjectRelease(iterator);
    return foundDeviceID;
}
// actuation IDs range from 1-6 going weakest to strongest
// unknown 2 controls the sharpness. Test: activation id 1 with unknown2=10
// unknown 3 is used as onset/offset in other cases. onset=0 offset=2. Can be negative
- (BOOL)triggerRawHaptic:(SInt32)actuationID unknown1:(UInt32)unknown1 unknown2:(Float32)unknown2 unknown3:(Float32)unknown3 {
    NSLog(@"🔧 Raw haptic trigger - ID: %d, unknown1: %u, unknown2: %f, unknown3: %f", actuationID, unknown1, unknown2, unknown3);
    
    // Find the built-in trackpad device using IOKit (HapticKey approach)
    UInt64 multitouchDeviceID = [self findBuiltInTrackpadDeviceID];
    if (multitouchDeviceID == 0) {
        NSLog(@"❌ Failed to find built-in trackpad device");
        return NO;
    }
    
    // Create actuator from device ID (HapticKey approach)
    CFTypeRef actuatorRef = MTActuatorCreateFromDeviceID(multitouchDeviceID);
    if (!actuatorRef) {
        NSLog(@"❌ Failed to create MTActuator from device ID");
        return NO;
    }
    
    // Open the actuator (HapticKey approach)
    IOReturn openResult = MTActuatorOpen(actuatorRef);
    if (openResult != kIOReturnSuccess) {
        NSLog(@"❌ Failed to open MTActuator: 0x%x", openResult);
        CFRelease(actuatorRef);
        return NO;
    }
    
    // Single actuate call with raw parameters
    NSLog(@"🎯 Actuating with raw parameters");
    IOReturn result = MTActuatorActuate(actuatorRef, actuationID, unknown1, unknown2, unknown3);
    NSLog(@"🎯 Actuate result: 0x%x (0 = success)", result);
    
    // Close and release
    MTActuatorClose(actuatorRef);
    CFRelease(actuatorRef);
    
    BOOL success = (result == kIOReturnSuccess);
    NSLog(@"🎯 Raw haptic result: %s", success ? "SUCCESS" : "FAILED");
    return success;
}
// Utility Tools C Language
static void dispatchSync(dispatch_queue_t queue, dispatch_block_t block) {
    if (!strcmp(dispatch_queue_get_label(queue), dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL))) {
        block();
        return;
    }
    dispatch_sync(queue, block);
}

static void dispatchResponse(dispatch_block_t block) {
    static dispatch_queue_t responseQueue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        responseQueue = dispatch_queue_create("com.kyome.openmt", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_sync(responseQueue, block);
}

static void contactEventHandler(MTDeviceRef eventDevice, MTTouch eventTouches[], int numTouches, double timestamp, int frame) {
    NSMutableArray *touches = [NSMutableArray array];
    
    for (int i = 0; i < numTouches; i++) {
        OpenMTTouch *touch = [[OpenMTTouch alloc] initWithMTTouch:&eventTouches[i]];
        [touches addObject:touch];
    }
    
    OpenMTEvent *event = OpenMTEvent.new;
    event.touches = touches;
    event.deviceID = *(int *)eventDevice;
    event.frameID = frame;
    event.timestamp = timestamp;
    
    [OpenMTManager.sharedManager handleMultitouchEvent:event];
}

@end
