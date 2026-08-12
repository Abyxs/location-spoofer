#import <CoreLocation/CoreLocation.h>
#import <UIKit/UIKit.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <notify.h>
#import "PJJoystickIPC.h"

@interface CLSimulationManager : NSObject
- (void)appendSimulatedLocation:(CLLocation *)location;
- (void)startLocationSimulation;
- (void)stopLocationSimulation;
@end

@interface MapViewController : UIViewController
- (void)pj_toggleJoystick:(UISwitch *)sender;
@end

static const void *PJJoystickSwitchKey = &PJJoystickSwitchKey;
static const void *PJJoystickBarItemKey = &PJJoystickBarItemKey;
static __weak UISwitch *PJSettingsSwitch;
static int PJVisibilityNotifyToken;

static void PJInstallVisibilityObserver(void) {
    if (PJVisibilityNotifyToken != 0) return;
    notify_register_dispatch(PJOverlayHideNotification, &PJVisibilityNotifyToken, dispatch_get_main_queue(), ^(int token) {
        PJSettingsSwitch.on = NO;
    });
}

static void PJInstallJoystickSwitch(MapViewController *controller) {
    UISwitch *toggle = objc_getAssociatedObject(controller, PJJoystickSwitchKey);
    UIBarButtonItem *item = objc_getAssociatedObject(controller, PJJoystickBarItemKey);
    if (!toggle) {
        toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
        toggle.on = PJJoystickEnabled();
        [toggle addTarget:controller action:@selector(pj_toggleJoystick:) forControlEvents:UIControlEventValueChanged];

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.text = @"摇杆";
        label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        label.textColor = UIColor.labelColor;

        UIStackView *control = [[UIStackView alloc] initWithArrangedSubviews:@[label, toggle]];
        control.axis = UILayoutConstraintAxisHorizontal;
        control.alignment = UIStackViewAlignmentCenter;
        control.spacing = 6;
        item = [[UIBarButtonItem alloc] initWithCustomView:control];
        objc_setAssociatedObject(controller, PJJoystickSwitchKey, toggle, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(controller, PJJoystickBarItemKey, item, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    toggle.on = PJJoystickEnabled();
    PJSettingsSwitch = toggle;
    PJInstallVisibilityObserver();
    NSArray<UIBarButtonItem *> *items = controller.navigationItem.rightBarButtonItems ?: @[];
    if (![items containsObject:item]) {
        controller.navigationItem.rightBarButtonItems = [items arrayByAddingObject:item];
    }
}

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
    NSTimeInterval elapsed = next.timestamp.timeIntervalSince1970 - PJLastLocation.timestamp.timeIntervalSince1970;
    double distance = hypot(east.doubleValue, north.doubleValue);
    double speed = elapsed > 0.01 ? distance / elapsed : 0;
    double course = distance > 0.001 ? atan2(east.doubleValue, north.doubleValue) * 180.0 / M_PI : PJLastLocation.course;
    if (course < 0) course += 360.0;
    next = [[CLLocation alloc] initWithCoordinate:next.coordinate
                                         altitude:next.altitude
                               horizontalAccuracy:next.horizontalAccuracy
                                 verticalAccuracy:next.verticalAccuracy
                                           course:course
                                            speed:speed
                                        timestamp:next.timestamp];
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

- (void)startLocationSimulation {
    %orig;
    if (PJJoystickEnabled()) notify_post(PJOverlayShowNotification);
}
%end


%hook MapViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    PJInstallJoystickSwitch(self);
}

%new
- (void)pj_toggleJoystick:(UISwitch *)sender {
    PJSetJoystickEnabled(sender.isOn);
}
%end
