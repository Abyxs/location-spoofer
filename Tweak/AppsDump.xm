#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>
#import <UIKit/UIKit.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <notify.h>
#import "PJJoystickIPC.h"

@interface CLSimulationManager : NSObject
- (void)appendSimulatedLocation:(CLLocation *)location;
- (void)clearSimulatedLocations;
- (void)flush;
- (void)startLocationSimulation;
- (void)stopLocationSimulation;
@end

@interface UIViewController (PJJoystickToggle)
- (void)pj_toggleJoystick:(UISwitch *)sender;
- (void)setLatitude:(double)latitude;
- (void)setLongitude:(double)longitude;
- (MKMapView *)mapView;
- (MKPointAnnotation *)annotation;
- (void)setAnnotation:(MKPointAnnotation *)annotation;
@end

static const void *PJJoystickSwitchKey = &PJJoystickSwitchKey;
static const void *PJJoystickBarItemKey = &PJJoystickBarItemKey;
static __weak UISwitch *PJSettingsSwitch;
static int PJShowNotifyToken;
static int PJHideNotifyToken;

static void PJInstallVisibilityObserver(void) {
    if (PJShowNotifyToken == 0) {
        notify_register_dispatch(PJOverlayShowNotification, &PJShowNotifyToken, dispatch_get_main_queue(), ^(int token) {
            PJSettingsSwitch.on = YES;
        });
    }
    if (PJHideNotifyToken == 0) {
        notify_register_dispatch(PJOverlayHideNotification, &PJHideNotifyToken, dispatch_get_main_queue(), ^(int token) {
            PJSettingsSwitch.on = NO;
        });
    }
}

static BOOL PJIsAppsDump(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"cn.gblw.AppsDump"];
}

static void PJInstallJoystickSwitch(UIViewController *controller) {
    if (!PJIsAppsDump() || [controller isKindOfClass:UIAlertController.class]) return;
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
    if (toggle.isOn) notify_post(PJOverlayShowNotification);
}

static CLSimulationManager *PJSimulator;
static CLLocation *PJLastLocation;
static __weak UIViewController *PJMapController;
static int PJNotifyToken;

static CLSimulationManager *PJEnsureSimulator(void) {
    if (!PJSimulator) {
        Class simulatorClass = NSClassFromString(@"CLSimulationManager");
        if (simulatorClass) PJSimulator = [[simulatorClass alloc] init];
    }
    return PJSimulator;
}

static CLLocationCoordinate2D PJTransformCoordinate(CLLocationCoordinate2D coordinate, SEL selector) {
    Class transformClass = NSClassFromString(@"wjLocationTransform");
    SEL initializer = @selector(initWithLatitude:andLongitude:);
    if (!transformClass || ![transformClass instancesRespondToSelector:initializer]) return coordinate;
    id transform = ((id (*)(id, SEL, double, double))objc_msgSend)([transformClass alloc], initializer,
                                                                   coordinate.latitude, coordinate.longitude);
    if (!transform || ![transform respondsToSelector:selector]) return coordinate;
    id result = ((id (*)(id, SEL))objc_msgSend)(transform, selector) ?: transform;
    if (![result respondsToSelector:@selector(latitude)] || ![result respondsToSelector:@selector(longitude)]) return coordinate;
    double latitude = ((double (*)(id, SEL))objc_msgSend)(result, @selector(latitude));
    double longitude = ((double (*)(id, SEL))objc_msgSend)(result, @selector(longitude));
    CLLocationCoordinate2D transformed = CLLocationCoordinate2DMake(latitude, longitude);
    return CLLocationCoordinate2DIsValid(transformed) ? transformed : coordinate;
}

static CLLocationCoordinate2D PJMapToSimulationCoordinate(CLLocationCoordinate2D coordinate) {
    return PJTransformCoordinate(coordinate, NSSelectorFromString(@"transformFromGDToGPS"));
}

static CLLocationCoordinate2D PJSimulationToMapCoordinate(CLLocationCoordinate2D coordinate) {
    return PJTransformCoordinate(coordinate, NSSelectorFromString(@"transformFromGPSToGD"));
}

static id PJObjectIvar(id object, const char *name) {
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    return ivar ? object_getIvar(object, ivar) : nil;
}

static void PJSyncAppsDumpMap(CLLocationCoordinate2D coordinate) {
    UIViewController *controller = PJMapController;
    if (!controller || !CLLocationCoordinate2DIsValid(coordinate)) return;

    if ([controller respondsToSelector:@selector(setLatitude:)]) {
        ((void (*)(id, SEL, double))objc_msgSend)(controller, @selector(setLatitude:), coordinate.latitude);
    }
    if ([controller respondsToSelector:@selector(setLongitude:)]) {
        ((void (*)(id, SEL, double))objc_msgSend)(controller, @selector(setLongitude:), coordinate.longitude);
    }

    MKMapView *mapView = nil;
    if ([controller respondsToSelector:@selector(mapView)]) {
        mapView = ((id (*)(id, SEL))objc_msgSend)(controller, @selector(mapView));
    }
    if (!mapView) mapView = PJObjectIvar(controller, "_mapView");
    if (![mapView isKindOfClass:MKMapView.class]) return;

    MKPointAnnotation *annotation = nil;
    if ([controller respondsToSelector:@selector(annotation)]) {
        annotation = ((id (*)(id, SEL))objc_msgSend)(controller, @selector(annotation));
    }
    if (!annotation) annotation = PJObjectIvar(controller, "_annotation");
    if (![annotation isKindOfClass:MKPointAnnotation.class]) {
        annotation = [MKPointAnnotation new];
        if ([controller respondsToSelector:@selector(setAnnotation:)]) {
            ((void (*)(id, SEL, id))objc_msgSend)(controller, @selector(setAnnotation:), annotation);
        }
    }
    annotation.coordinate = coordinate;
    if (![mapView.annotations containsObject:annotation]) [mapView addAnnotation:annotation];
    [mapView setCenterCoordinate:coordinate animated:NO];
}

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
    if (!timestamp) return;
    if (fabs(timestamp.doubleValue - NSDate.date.timeIntervalSince1970) > 2.0) return;
    if ([command[@"action"] isEqualToString:@"set"]) {
        NSNumber *latitude = command[@"latitude"];
        NSNumber *longitude = command[@"longitude"];
        if (!latitude || !longitude) return;
        CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(latitude.doubleValue, longitude.doubleValue);
        if (!CLLocationCoordinate2DIsValid(coordinate)) return;
        PJSyncAppsDumpMap(coordinate);
        CLLocationCoordinate2D simulatedCoordinate = PJMapToSimulationCoordinate(coordinate);
        CLLocation *previous = PJLastLocation;
        CLLocation *selected = [[CLLocation alloc] initWithCoordinate:simulatedCoordinate
                                                             altitude:previous ? previous.altitude : 0
                                                   horizontalAccuracy:previous ? MAX(1.0, previous.horizontalAccuracy) : 5.0
                                                     verticalAccuracy:previous ? MAX(1.0, previous.verticalAccuracy) : 5.0
                                                               course:-1
                                                                speed:0
                                                            timestamp:[NSDate date]];
        PJLastLocation = selected;
        PJWriteCurrentLocation(coordinate.latitude, coordinate.longitude);
        simulator = PJEnsureSimulator();
        if (!simulator) return;
        [simulator stopLocationSimulation];
        [simulator clearSimulatedLocations];
        [simulator appendSimulatedLocation:selected];
        [simulator flush];
        [simulator startLocationSimulation];
        return;
    }
    if (!simulator || !PJLastLocation) return;
    if (!east || !north || !moving) return;
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
    PJSyncAppsDumpMap(PJSimulationToMapCoordinate(next.coordinate));
    [simulator appendSimulatedLocation:next];
    [simulator flush];
}

static void PJEnsureCommandObserver(void) {
    if (PJNotifyToken != 0) return;
    notify_register_dispatch(PJDarwinNotification, &PJNotifyToken, dispatch_get_main_queue(), ^(int token) {
        PJConsumeCommand();
    });
}

static void PJInstallAppsDumpObserver(CLSimulationManager *simulator) {
    if (simulator) PJSimulator = simulator;
    PJEnsureCommandObserver();
}

%hook CLSimulationManager
- (id)init {
    id result = %orig;
    if (result) PJInstallAppsDumpObserver((CLSimulationManager *)result);
    return result;
}

- (void)appendSimulatedLocation:(CLLocation *)location {
    if (location) {
        PJLastLocation = location;
        CLLocationCoordinate2D mapCoordinate = PJSimulationToMapCoordinate(location.coordinate);
        PJWriteCurrentLocation(mapCoordinate.latitude, mapCoordinate.longitude);
    }
    %orig;
}

- (void)startLocationSimulation {
    %orig;
    if (PJJoystickEnabled()) notify_post(PJOverlayShowNotification);
}
%end


%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    PJEnsureCommandObserver();
    if ([NSStringFromClass(self.class) isEqualToString:@"MapViewController"]) {
        PJMapController = self;
        NSDictionary *location = PJReadCurrentLocation();
        NSNumber *latitude = location[@"latitude"];
        NSNumber *longitude = location[@"longitude"];
        if (latitude && longitude) {
            PJSyncAppsDumpMap(CLLocationCoordinate2DMake(latitude.doubleValue, longitude.doubleValue));
        }
    }
    Ivar simulatorIvar = class_getInstanceVariable(self.class, "_simulator");
    if (simulatorIvar) {
        id simulator = object_getIvar(self, simulatorIvar);
        if ([simulator isKindOfClass:NSClassFromString(@"CLSimulationManager")]) {
            PJInstallAppsDumpObserver((CLSimulationManager *)simulator);
        }
    }
    PJInstallJoystickSwitch(self);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PJInstallJoystickSwitch(self);
    });
}

%new
- (void)pj_toggleJoystick:(UISwitch *)sender {
    PJSetJoystickEnabled(sender.isOn);
}
%end
