#import <CoreLocation/CoreLocation.h>
#import <math.h>
#import <objc/message.h>
#import <notify.h>
#import "PJJoystickIPC.h"

@interface CLSimulationManager : NSObject
- (void)appendSimulatedLocation:(CLLocation *)location;
- (void)startLocationSimulation;
- (void)stopLocationSimulation;
@end

static __weak CLSimulationManager *PJSimulator;
static CLLocation *PJLastLocation;
static int PJNotifyToken;

static CLLocation *PJApplyOffset(CLLocation *location, double northMeters, double eastMeters) {
    if (!location) return nil;
    CLLocationCoordinate2D coordinate = location.coordinate;
    double radians = coordinate.latitude * M_PI / 180.0;
    double latitude = coordinate.latitude + northMeters / 6378137.0 * 180.0 / M_PI;
    latitude = MAX(-85.0, MIN(85.0, latitude));
    double midRadians = (radians + latitude * M_PI / 180.0) / 2.0;
    double scale = MAX(0.01, fabs(cos(midRadians)));
    double longitude = coordinate.longitude + eastMeters / (6378137.0 * scale) * 180.0 / M_PI;
    longitude = fmod(longitude + 540.0, 360.0) - 180.0;
    CLLocationCoordinate2D moved = CLLocationCoordinate2DMake(latitude, longitude);
    return [[CLLocation alloc] initWithCoordinate:moved
                                          altitude:location.altitude
                                horizontalAccuracy:MAX(1.0, location.horizontalAccuracy)
                                  verticalAccuracy:MAX(1.0, location.verticalAccuracy)
                                         timestamp:[NSDate date]];
}

static void PJConsumeCommand(void) {
    CLSimulationManager *simulator = PJSimulator;
    NSDictionary *command = PJReadJoystickCommand();
    NSNumber *east = command[@"eastMeters"];
    NSNumber *north = command[@"northMeters"];
    NSNumber *moving = command[@"moving"];
    NSNumber *timestamp = command[@"timestamp"];
    if (!simulator || !east || !north || !moving || !timestamp) return;
    if (fabs(timestamp.doubleValue - NSDate.date.timeIntervalSince1970) > 2.0) return;
    if (!PJLastLocation) return;
    if (!moving.boolValue) return;
    CLLocation *next = PJApplyOffset(PJLastLocation, north.doubleValue, east.doubleValue);
    if (!next) return;
    PJLastLocation = next;
    [simulator appendSimulatedLocation:next];
}

static void PJInstallAppsDumpObserver(CLSimulationManager *simulator) {
    PJSimulator = simulator;
    if (PJNotifyToken != 0) return;
    notify_register_dispatch(PJDarwinNotification, &PJNotifyToken, dispatch_get_main_queue(), ^(int token) {
        PJConsumeCommand();
    });
}

%hook CLSimulationManager
- (id)init {
    id result = %orig;
    if (result) PJInstallAppsDumpObserver((CLSimulationManager *)result);
    return result;
}

- (void)appendSimulatedLocation:(CLLocation *)location {
    if (location) PJLastLocation = location;
    %orig;
}
%end
