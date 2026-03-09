#ifndef OpenMTInternal_h
#define OpenMTInternal_h

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <stdint.h>
#include <objc/objc.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint position;
    MTPoint velocity;
} MTVector;

// Run mode options for MTDeviceStart
typedef enum {
    MTRunModeVerbose      = 0,
    MTRunModeLessVerbose  = 0x10000000,
//     MTRunModeUNKNOWN      = 0x00000001, // disassembly of MTDeviceStart shows that setting this prevents an instance variable
//                                         // (not sure what) from being cleared and skips the runloop check
//     MTRunModeNoRunLoop    = 0x20000000, // prevents it from being added to a runloop
} MTRunMode;

enum {
    MTTouchStateNotTracking = 0,
    MTTouchStateStartInRange = 1,
    MTTouchStateHoverInRange = 2,
    MTTouchStateMakeTouch = 3,
    MTTouchStateTouching = 4,
    MTTouchStateBreakTouch = 5,
    MTTouchStateLingerInRange = 6,
    MTTouchStateOutOfRange = 7
};

typedef int MTTouchState;

// gives human readable labels for the above; undefined if out of range
char* MTGetPathStageName(MTTouchState pathstage);

typedef struct {
    int frame;
    double timestamp;
    int identifier;
    MTTouchState state;
    int fingerId;
    int handId;
    MTVector normalizedPosition;
    float total; //total of capacitance
    float pressure;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolutePosition;
    int field14;
    int field15;
    float density; //area density of capacitance
} MTTouch;

typedef void *MTDeviceRef;
typedef void (*MTFrameCallbackFunction)(MTDeviceRef device, MTTouch touches[], int numTouches, double timestamp, int frame);
typedef void (*MTPathCallbackFunction)(MTDeviceRef device, long pathID, long state, MTTouch* touch);

// Enhanced callback functions with refcon support
typedef void (*MTFrameCallbackFunctionWithRefcon)(MTDeviceRef device,
                                        MTTouch *touches, size_t numTouches,
                                        double timestamp, size_t frame, void* refCon);
typedef void (*MTPathCallbackFunctionWithRefcon)(MTDeviceRef device, long pathID, MTTouchState stage, MTTouch* touch, void* refCon);

// Image callback function for advanced debugging
typedef void (*MTImageCallbackFunction)(MTDeviceRef, void*, void*, void*);

// Predefined callbacks for testing. uses printf to stdout
extern MTPathCallbackFunction MTPathPrintCallback;
extern MTImageCallbackFunction MTImagePrintCallback;

// Basic device availability and creation
CFTypeID MTDeviceGetTypeID(void);
double MTAbsoluteTimeGetCurrent(void);
bool MTDeviceIsAvailable(void); // true if can create default device
MTDeviceRef MTDeviceCreateDefault(void);
CFArrayRef MTDeviceCreateList(void) __attribute__ ((weak_import));
MTDeviceRef MTDeviceCreateFromDeviceID(uint64_t);
MTDeviceRef MTDeviceCreateFromService(io_service_t);
// Doesn't work -- one source believes that this compares by ptr and not the actual contents of the GUID
MTDeviceRef MTDeviceCreateFromGUID(uuid_t);
void MTDeviceRelease(MTDeviceRef);

// Device control
OSStatus MTDeviceStart(MTDeviceRef, MTRunMode);
OSStatus MTDeviceStop(MTDeviceRef);

// Device status queries
bool MTDeviceIsRunning(MTDeviceRef);
bool MTDeviceIsBuiltIn(MTDeviceRef) __attribute__ ((weak_import));
bool MTDeviceIsOpaqueSurface(MTDeviceRef);
bool MTDeviceIsAlive(MTDeviceRef);
bool MTDeviceIsMTHIDDevice(MTDeviceRef);
bool MTDeviceSupportsForce(MTDeviceRef);
bool MTDeviceSupportsActuation(MTDeviceRef);
bool MTDeviceDriverIsReady(MTDeviceRef);
bool MTDevicePowerControlSupported(MTDeviceRef);

// Device information getters
io_service_t MTDeviceGetService(MTDeviceRef);
OSStatus MTDeviceGetSensorSurfaceDimensions(MTDeviceRef, int*, int*);
OSStatus MTDeviceGetSensorDimensions(MTDeviceRef, int*, int*);
OSStatus MTDeviceGetFamilyID(MTDeviceRef, int*);
OSStatus MTDeviceGetDeviceID(MTDeviceRef, uint64_t*) __attribute__ ((weak_import));
OSStatus MTDeviceGetVersion(MTDeviceRef, int32_t*);
OSStatus MTDeviceGetDriverType(MTDeviceRef, int*);
OSStatus MTDeviceGetTransportMethod(MTDeviceRef, int*) __attribute__ ((weak_import));
OSStatus MTDeviceGetGUID(MTDeviceRef, uuid_t*);
// Hopper disassembly shows that this searches for the key "Multitouch Serial Number" and returns an empty string if it's
// not present... The built in non-force touch trackpad in my laptop works with this, but my newer "Magic Trackpad 2"
// returns a more useful value with:
//     CFStringRef SN = (CFStringRef)IORegistryEntrySearchCFProperty(MTDeviceGetService(device),
//                                                                   kIOServicePlane,
//                                                                   CFSTR(kIOHIDSerialNumberKey),
//                                                                   kCFAllocatorDefault,
//                                                                   kIORegistryIterateRecursively) ;
OSStatus MTDeviceGetSerialNumber(MTDeviceRef, CFStringRef*);

void MTPrintImageRegionDescriptors(MTDeviceRef);

// Force touch and click control
// for force touch trackpads, allows disabling ability to accept clicks; still responds to touches and gestures, though
// always false for non force touch trackpads
bool MTDeviceGetSystemForceResponseEnabled(MTDeviceRef);
void MTDeviceSetSystemForceResponseEnabled(MTDeviceRef, bool);
// Always true for non force touch trackpads
OSStatus MTDeviceSupportsSilentClick(MTDeviceRef, bool*);

// Pressure value queries
// always 0 for my devices (non force touch laptop and external force touch trackpad), so not sure if useful or return type is correct
int32_t MTDeviceGetMinDigitizerPressureValue(MTDeviceRef);
int32_t MTDeviceGetMaxDigitizerPressureValue(MTDeviceRef);
int32_t MTDeviceGetDigitizerPressureDynamicRange(MTDeviceRef);

// Power control (untested/problematic)
// Can't test with my devices, so prototype is a best guess atm
OSStatus MTDevicePowerSetEnabled(MTDeviceRef, bool);
void MTDevicePowerGetEnabled(MTDeviceRef, bool*);
OSStatus MTDeviceSetUILocked(MTDeviceRef, bool);

// RunLoop management (usually handled automatically by MTDeviceStart)
// Unless you're messing with the flags to MTDeviceStart, the runloop is handled by MTDeviceStart and shouldn't
// be required to be invoked directly
CFRunLoopSourceRef MTDeviceCreateMultitouchRunLoopSource(MTDeviceRef);
OSStatus MTDeviceScheduleOnRunLoop(MTDeviceRef, CFRunLoopRef, CFStringRef);

// Enables predefined callbacks for device for path and image callbacks (with various parameters for each bool after
// the first (which is for path callback) that output via printf; presumably for internal debugging purposes
//
// Online example shows this with one bool flag, but Hopper disassembly shows all 6 and shows that the additional
// flags are for enabling image callbacks with various parameters. Preliminary tests never show output from the
// image callbacks so either my devices don't support these or I don't understand them well enough -- likely both
//    MTRegisterPathCallback(MTDeviceRef, MTPathPrintCallback);
//    MTRegisterImageCallbackWithRefcon(MTDeviceRef, MTImagePrintCallback, 0x7ffffffe, 0x2, NULL);
//    MTRegisterImageCallbackWithRefcon(MTDeviceRef, MTImagePrintCallback, 0x2, 0x10, NULL);
//    MTRegisterImageCallbackWithRefcon(MTDeviceRef, MTImagePrintCallback, 0x2, 0x10000, NULL);
//    MTRegisterImageCallbackWithRefcon(MTDeviceRef, MTImagePrintCallback, 0x2, 0x100000, NULL);
//    MTRegisterImageCallbackWithRefcon(MTDeviceRef, MTImagePrintCallback, 0x2, 0x800000, NULL);
void MTEasyInstallPrintCallbacks(MTDeviceRef, bool, bool, bool, bool, bool, bool);

// Callback registration functions
// These return true or false indicating success/failure
void MTRegisterContactFrameCallback(MTDeviceRef, MTFrameCallbackFunction);
void MTUnregisterContactFrameCallback(MTDeviceRef, MTFrameCallbackFunction);
bool MTRegisterContactFrameCallbackWithRefcon(MTDeviceRef, MTFrameCallbackFunctionWithRefcon, void*);

void MTRegisterFullFrameCallback(MTDeviceRef, MTFrameCallbackFunction);
void MTUnregisterFullFrameCallback(MTDeviceRef, MTFrameCallbackFunction);

// Make sure to use the correct unregistration function -- the callback is stored in a different location in the object's
// instance data depending upon the callback type
void MTRegisterPathCallback(MTDeviceRef, MTPathCallbackFunction);
void MTUnregisterPathCallback(MTDeviceRef, MTPathCallbackFunction);
bool MTRegisterPathCallbackWithRefcon(MTDeviceRef, MTPathCallbackFunctionWithRefcon, void*);
bool MTUnregisterPathCallbackWithRefcon(MTDeviceRef, MTPathCallbackFunctionWithRefcon);

// Image callback registration
bool MTRegisterImageCallbackWithRefcon(MTDeviceRef, MTImageCallbackFunction, int32_t, int32_t, void*);
bool MTRegisterImageCallback(MTDeviceRef, MTImageCallbackFunction, int32_t, int32_t);
bool MTUnregisterImageCallback(MTDeviceRef, MTImageCallbackFunction);
// Shorthand for MTRegisterImageCallbackWithRefcon(MTDeviceRef, MTImageCallbackFunction, 0x2, 0x10000, NULL);
bool MTRegisterMultitouchImageCallback(MTDeviceRef, MTImageCallbackFunction);

// Haptic control functions
typedef void *MTActuatorRef;
MTActuatorRef MTDeviceGetMTActuator(MTDeviceRef device);
bool MTActuatorGetSystemActuationsEnabled(MTActuatorRef actuator);
OSStatus MTActuatorSetSystemActuationsEnabled(MTActuatorRef actuator, bool enabled);

// HapticKey-style haptic control (working implementation)
CFTypeRef MTActuatorCreateFromDeviceID(UInt64 deviceID);
IOReturn MTActuatorOpen(CFTypeRef actuatorRef);
IOReturn MTActuatorClose(CFTypeRef actuatorRef);
IOReturn MTActuatorActuate(CFTypeRef actuatorRef, SInt32 actuationID, UInt32 unknown1, Float32 unknown2, Float32 unknown3);
bool MTActuatorIsOpen(CFTypeRef actuatorRef);

// Haptic patterns and intensities
typedef enum {
    MTHapticIntensityWeak = 3,
    MTHapticIntensityMedium = 4,
    MTHapticIntensityStrong = 6
} MTHapticIntensity;

typedef enum {
    MTHapticPatternGeneric = 15,
    MTHapticPatternAlignment = 16,
    MTHapticPatternLevel = 17
} MTHapticPattern;

#ifdef __cplusplus
}
#endif

#endif /* OpenMTInternal_h */
