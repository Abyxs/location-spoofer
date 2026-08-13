#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import <math.h>
#import "PJJoystickIPC.h"

static NSString *const PJEndpoint = @"http://127.0.0.1:8888/joystick";
static NSString *const PJMapPreferencesPath = @"/var/mobile/Library/Preferences/com.paopaolabs.joystick.map.plist";

@interface PJOverlayWindow : UIWindow
@end

@implementation PJOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self.rootViewController.view ? nil : hit;
}
@end

@interface PJController : UIViewController <UIGestureRecognizerDelegate>
@property(nonatomic, strong) UIView *panel;
@property(nonatomic, strong) UIButton *collapsedButton;
@property(nonatomic, strong) UIButton *closeButton;
@property(nonatomic, strong) UIButton *collapseButton;
@property(nonatomic, strong) UIView *base;
@property(nonatomic, strong) UIView *knob;
@property(nonatomic, strong) UILabel *status;
@property(nonatomic, strong) UIButton *speedButton;
@property(nonatomic, strong) UIButton *mapButton;
@property(nonatomic, strong) UIView *mapPanel;
@property(nonatomic, strong) MKMapView *mapView;
@property(nonatomic, strong) MKPointAnnotation *locationAnnotation;
@property(nonatomic, strong) UIButton *recenterButton;
@property(nonatomic, strong) UIButton *minimizeMapButton;
@property(nonatomic, strong) UISegmentedControl *mapModeControl;
@property(nonatomic, strong) UIView *opacityControl;
@property(nonatomic, strong) UISlider *opacitySlider;
@property(nonatomic, strong) UILabel *opacityLabel;
@property(nonatomic) int locationUpdateToken;
@property(nonatomic, strong) CADisplayLink *displayLink;
@property(nonatomic) CGPoint direction;
@property(nonatomic) CGPoint targetDirection;
@property(nonatomic) CGFloat targetMagnitude;
@property(nonatomic) CGFloat smoothedMagnitude;
@property(nonatomic) NSInteger frameCounter;
@property(nonatomic) NSInteger speedIndex;
@property(nonatomic) CGPoint panelDragOrigin;
@property(nonatomic) NSTimeInterval lastTickTimestamp;
@property(nonatomic) NSTimeInterval sendAccumulator;
@property(nonatomic) BOOL collapsedMap;
@end

@implementation PJController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.speedIndex = 0;

    self.panel = [[UIView alloc] initWithFrame:CGRectMake(20, 180, 150, 190)];
    self.panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.82];
    self.panel.layer.cornerRadius = 18;
    self.panel.layer.borderWidth = 1;
    self.panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
    [self.view addSubview:self.panel];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.frame = CGRectMake(116, 7, 28, 24);
    self.closeButton.tintColor = [UIColor colorWithWhite:1 alpha:0.75];
    self.closeButton.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightRegular];
    [self.closeButton setTitle:@"×" forState:UIControlStateNormal];
    [self.closeButton addTarget:self action:@selector(hideJoystick) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.closeButton];

    self.collapseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.collapseButton.frame = CGRectMake(7, 7, 28, 24);
    self.collapseButton.tintColor = [UIColor colorWithWhite:1 alpha:0.75];
    self.collapseButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightRegular];
    [self.collapseButton setTitle:@"−" forState:UIControlStateNormal];
    [self.collapseButton addTarget:self action:@selector(collapseJoystick) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.collapseButton];

    UIView *grip = [[UIView alloc] initWithFrame:CGRectMake(51, 9, 48, 5)];
    grip.backgroundColor = [UIColor colorWithWhite:1 alpha:0.45];
    grip.layer.cornerRadius = 2.5;
    [self.panel addSubview:grip];
    UIPanGestureRecognizer *panelPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPanel:)];
    panelPan.delegate = self;
    [self.panel addGestureRecognizer:panelPan];

    self.base = [[UIView alloc] initWithFrame:CGRectMake(20, 24, 110, 110)];
    self.base.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
    self.base.layer.cornerRadius = 55;
    self.base.layer.borderWidth = 1;
    self.base.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.2].CGColor;
    [self.panel addSubview:self.base];

    self.knob = [[UIView alloc] initWithFrame:CGRectMake(31, 31, 48, 48)];
    self.knob.backgroundColor = [UIColor colorWithRed:0.10 green:0.68 blue:0.40 alpha:1.0];
    self.knob.layer.cornerRadius = 24;
    self.knob.layer.shadowColor = UIColor.blackColor.CGColor;
    self.knob.layer.shadowOpacity = 0.58;
    self.knob.layer.shadowRadius = 6;
    self.knob.layer.shadowOffset = CGSizeMake(0, 5);
    self.knob.layer.borderWidth = 1;
    self.knob.layer.borderColor = [UIColor colorWithRed:0.34 green:0.92 blue:0.63 alpha:0.8].CGColor;
    [self.base addSubview:self.knob];

    UIView *knobHighlight = [[UIView alloc] initWithFrame:CGRectMake(7, 5, 34, 15)];
    knobHighlight.userInteractionEnabled = NO;
    knobHighlight.backgroundColor = [UIColor colorWithWhite:1 alpha:0.18];
    knobHighlight.layer.cornerRadius = 7.5;
    [self.knob addSubview:knobHighlight];

    UIView *knobShade = [[UIView alloc] initWithFrame:CGRectMake(8, 38, 32, 4)];
    knobShade.userInteractionEnabled = NO;
    knobShade.backgroundColor = [UIColor colorWithWhite:0 alpha:0.18];
    knobShade.layer.cornerRadius = 2;
    [self.knob addSubview:knobShade];
    UIPanGestureRecognizer *joystickPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(moveJoystick:)];
    [self.base addGestureRecognizer:joystickPan];

    self.speedButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.speedButton.frame = CGRectMake(15, 145, 72, 32);
    self.speedButton.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    self.speedButton.layer.cornerRadius = 8;
    self.speedButton.tintColor = UIColor.whiteColor;
    self.speedButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [self.speedButton addTarget:self action:@selector(changeSpeed) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.speedButton];

    self.mapButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.mapButton.frame = CGRectMake(93, 145, 42, 32);
    self.mapButton.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    self.mapButton.layer.cornerRadius = 8;
    self.mapButton.tintColor = UIColor.whiteColor;
    self.mapButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [self.mapButton setTitle:@"地图" forState:UIControlStateNormal];
    [self.mapButton addTarget:self action:@selector(showMapPanel) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.mapButton];

    self.status = [[UILabel alloc] initWithFrame:CGRectMake(93, 178, 42, 12)];
    self.status.text = @"停止";
    self.status.textColor = [UIColor colorWithWhite:0.8 alpha:1];
    self.status.textAlignment = NSTextAlignmentCenter;
    self.status.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    self.status.hidden = YES;
    [self.panel addSubview:self.status];
    [self updateSpeedTitle];

    self.collapsedButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.collapsedButton.frame = CGRectMake(20, 180, 48, 48);
    self.collapsedButton.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.36];
    self.collapsedButton.layer.cornerRadius = 24;
    self.collapsedButton.layer.borderWidth = 1;
    self.collapsedButton.layer.borderColor = [UIColor colorWithRed:0.25 green:0.92 blue:0.60 alpha:0.72].CGColor;
    self.collapsedButton.layer.shadowColor = UIColor.blackColor.CGColor;
    self.collapsedButton.layer.shadowOpacity = 0.28;
    self.collapsedButton.layer.shadowRadius = 4;
    self.collapsedButton.layer.shadowOffset = CGSizeMake(0, 3);
    self.collapsedButton.tintColor = [UIColor colorWithWhite:1 alpha:0.9];
    [self.collapsedButton setTitle:@"摇" forState:UIControlStateNormal];
    self.collapsedButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    [self.collapsedButton addTarget:self action:@selector(expandJoystick) forControlEvents:UIControlEventTouchUpInside];
    self.collapsedButton.hidden = YES;
    [self.view addSubview:self.collapsedButton];

    [self buildMapPanel];

}

- (void)buildMapPanel {
    self.mapPanel = [[UIView alloc] initWithFrame:CGRectZero];
    self.mapPanel.backgroundColor = UIColor.clearColor;
    self.mapPanel.hidden = YES;
    [self.view addSubview:self.mapPanel];

    self.mapView = [[MKMapView alloc] initWithFrame:CGRectZero];
    self.mapView.alpha = 0.58;
    self.mapView.showsCompass = YES;
    self.mapView.showsScale = YES;
    [self.mapPanel addSubview:self.mapView];

    NSDictionary *mapPreferences = [NSDictionary dictionaryWithContentsOfFile:PJMapPreferencesPath];
    CGFloat savedOpacity = [mapPreferences[@"opacity"] doubleValue];
    if (savedOpacity < 0.2 || savedOpacity > 1.0) savedOpacity = 0.58;
    self.mapView.alpha = savedOpacity;

    self.mapModeControl = [[UISegmentedControl alloc] initWithItems:@[@"半透明", @"仅路线"]];
    self.mapModeControl.selectedSegmentIndex = [mapPreferences[@"mode"] integerValue] == 1 ? 1 : 0;
    self.mapModeControl.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.72];
    self.mapModeControl.selectedSegmentTintColor = [UIColor colorWithWhite:1 alpha:0.24];
    [self.mapModeControl setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor}
                                      forState:UIControlStateNormal];
    [self.mapModeControl addTarget:self action:@selector(changeMapMode:) forControlEvents:UIControlEventValueChanged];
    [self.mapPanel addSubview:self.mapModeControl];

    self.opacityControl = [[UIView alloc] initWithFrame:CGRectZero];
    self.opacityControl.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.78];
    self.opacityControl.layer.cornerRadius = 8;
    [self.mapPanel addSubview:self.opacityControl];

    self.opacityLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.opacityLabel.textColor = UIColor.whiteColor;
    self.opacityLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [self.opacityControl addSubview:self.opacityLabel];

    self.opacitySlider = [[UISlider alloc] initWithFrame:CGRectZero];
    self.opacitySlider.minimumValue = 0.2;
    self.opacitySlider.maximumValue = 1.0;
    self.opacitySlider.value = savedOpacity;
    self.opacitySlider.minimumTrackTintColor = [UIColor colorWithRed:0.25 green:0.92 blue:0.60 alpha:1];
    [self.opacitySlider addTarget:self action:@selector(changeMapOpacity:) forControlEvents:UIControlEventValueChanged];
    [self.opacityControl addSubview:self.opacitySlider];
    [self updateOpacityLabel];

    UIButton *backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    backButton.frame = CGRectMake(14, 12, 64, 36);
    backButton.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.76];
    backButton.layer.cornerRadius = 8;
    backButton.tintColor = UIColor.whiteColor;
    [backButton setTitle:@"摇杆" forState:UIControlStateNormal];
    [backButton addTarget:self action:@selector(hideMapPanel) forControlEvents:UIControlEventTouchUpInside];
    [self.mapPanel addSubview:backButton];

    self.recenterButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.recenterButton.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.78];
    self.recenterButton.layer.cornerRadius = 22;
    self.recenterButton.tintColor = UIColor.whiteColor;
    self.recenterButton.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    [self.recenterButton setTitle:@"◎" forState:UIControlStateNormal];
    [self.recenterButton addTarget:self action:@selector(recenterMap) forControlEvents:UIControlEventTouchUpInside];
    [self.mapPanel addSubview:self.recenterButton];

    self.minimizeMapButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.minimizeMapButton.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.78];
    self.minimizeMapButton.layer.cornerRadius = 22;
    self.minimizeMapButton.tintColor = UIColor.whiteColor;
    self.minimizeMapButton.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
    [self.minimizeMapButton setTitle:@"−" forState:UIControlStateNormal];
    [self.minimizeMapButton addTarget:self action:@selector(minimizeMap) forControlEvents:UIControlEventTouchUpInside];
    [self.mapPanel addSubview:self.minimizeMapButton];

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectZero];
    hint.tag = 2020;
    hint.text = @"长按地图选择位置";
    hint.textAlignment = NSTextAlignmentCenter;
    hint.textColor = UIColor.whiteColor;
    hint.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.70];
    hint.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    hint.layer.cornerRadius = 8;
    hint.clipsToBounds = YES;
    [self.mapPanel addSubview:hint];

    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(selectMapLocation:)];
    press.minimumPressDuration = 0.55;
    [self.mapView addGestureRecognizer:press];

    [self changeMapMode:self.mapModeControl];

    __weak PJController *weakSelf = self;
    notify_register_dispatch(PJLocationUpdateNotification, &_locationUpdateToken, dispatch_get_main_queue(), ^(int token) {
        [weakSelf refreshCurrentLocation:NO];
    });
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.mapPanel.frame = self.view.bounds;
    self.mapView.frame = self.mapPanel.bounds;
    UILabel *hint = (UILabel *)[self.mapPanel viewWithTag:2020];
    CGFloat width = MIN(180, self.view.bounds.size.width - 32);
    CGFloat top = self.view.safeAreaInsets.top + 12;
    self.mapModeControl.frame = CGRectMake((self.view.bounds.size.width - 150) / 2, top, 150, 36);
    hint.frame = CGRectMake((self.view.bounds.size.width - width) / 2, top + 46, width, 36);
    self.recenterButton.frame = CGRectMake(self.view.bounds.size.width - 60, self.view.bounds.size.height - self.view.safeAreaInsets.bottom - 60, 44, 44);
    self.minimizeMapButton.frame = CGRectMake(self.view.bounds.size.width - 60, self.view.bounds.size.height - self.view.safeAreaInsets.bottom - 112, 44, 44);
    self.opacityControl.frame = CGRectMake(16, self.view.bounds.size.height - self.view.safeAreaInsets.bottom - 60, 190, 44);
    self.opacityLabel.frame = CGRectMake(10, 0, 70, 44);
    self.opacitySlider.frame = CGRectMake(76, 7, 104, 30);
}

- (void)changeMapMode:(UISegmentedControl *)control {
    BOOL routeOnly = control.selectedSegmentIndex == 1;
    self.mapView.overrideUserInterfaceStyle = routeOnly ? UIUserInterfaceStyleDark : UIUserInterfaceStyleUnspecified;
    self.mapView.showsBuildings = !routeOnly;
    self.mapView.layer.compositingFilter = routeOnly ? @"screenBlendMode" : nil;
    [self saveMapState];
}

- (void)changeMapOpacity:(UISlider *)slider {
    self.mapView.alpha = slider.value;
    [self updateOpacityLabel];
}

- (void)updateOpacityLabel {
    self.opacityLabel.text = [NSString stringWithFormat:@"透明度 %ld%%", (long)lrint(self.opacitySlider.value * 100)];
}

- (void)saveMapState {
    MKMapCamera *camera = self.mapView.camera;
    if (!camera || !CLLocationCoordinate2DIsValid(camera.centerCoordinate)) return;
    [@{
        @"latitude": @(camera.centerCoordinate.latitude),
        @"longitude": @(camera.centerCoordinate.longitude),
        @"altitude": @(camera.altitude),
        @"pitch": @(camera.pitch),
        @"heading": @(camera.heading),
        @"opacity": @(self.opacitySlider.value),
        @"mode": @(self.mapModeControl.selectedSegmentIndex)
    } writeToFile:PJMapPreferencesPath atomically:YES];
}

- (BOOL)restoreMapState {
    NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:PJMapPreferencesPath];
    NSNumber *latitude = preferences[@"latitude"];
    NSNumber *longitude = preferences[@"longitude"];
    NSNumber *altitude = preferences[@"altitude"];
    if (!latitude || !longitude || !altitude) return NO;
    CLLocationCoordinate2D center = CLLocationCoordinate2DMake(latitude.doubleValue, longitude.doubleValue);
    if (!CLLocationCoordinate2DIsValid(center) || altitude.doubleValue <= 0) return NO;
    MKMapCamera *camera = [MKMapCamera cameraLookingAtCenterCoordinate:center
                                                     fromDistance:altitude.doubleValue
                                                            pitch:[preferences[@"pitch"] doubleValue]
                                                          heading:[preferences[@"heading"] doubleValue]];
    [self.mapView setCamera:camera animated:NO];
    return YES;
}

- (void)showMapPanel {
    [self stopMoving];
    self.panel.hidden = YES;
    self.collapsedButton.hidden = YES;
    self.mapPanel.hidden = NO;
    BOOL restored = [self restoreMapState];
    [self refreshCurrentLocation:!restored];
}

- (void)recenterMap {
    NSDictionary *location = PJReadCurrentLocation();
    NSNumber *latitude = location[@"latitude"];
    NSNumber *longitude = location[@"longitude"];
    if (!latitude || !longitude) return;
    CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(latitude.doubleValue, longitude.doubleValue);
    if (!CLLocationCoordinate2DIsValid(coordinate)) return;
    [self updateLocationAnnotation:coordinate];
    [self.mapView setCenterCoordinate:coordinate animated:YES];
}

- (void)refreshCurrentLocation:(BOOL)centerMap {
    NSDictionary *location = PJReadCurrentLocation();
    NSNumber *latitude = location[@"latitude"];
    NSNumber *longitude = location[@"longitude"];
    if (!latitude || !longitude) return;
    CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(latitude.doubleValue, longitude.doubleValue);
    if (!CLLocationCoordinate2DIsValid(coordinate)) return;
    if (!self.locationAnnotation) {
        self.locationAnnotation = [MKPointAnnotation new];
        self.locationAnnotation.title = @"虚拟位置";
        [self.mapView addAnnotation:self.locationAnnotation];
    }
    self.locationAnnotation.coordinate = coordinate;
    if (centerMap) [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(coordinate, 1200, 1200) animated:YES];
}

- (void)hideMapPanel {
    [self saveMapState];
    self.collapsedMap = NO;
    self.mapPanel.hidden = YES;
    self.panel.hidden = NO;
}

- (void)minimizeMap {
    [self saveMapState];
    self.collapsedMap = YES;
    self.mapPanel.hidden = YES;
    self.panel.hidden = YES;
    CGPoint origin = self.panel.frame.origin;
    self.collapsedButton.frame = CGRectMake(origin.x, origin.y, 48, 48);
    self.collapsedButton.hidden = NO;
}

- (void)selectMapLocation:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    CGPoint point = [gesture locationInView:self.mapView];
    CLLocationCoordinate2D coordinate = [self.mapView convertPoint:point toCoordinateFromView:self.mapView];
    if (!CLLocationCoordinate2DIsValid(coordinate)) return;
    [self updateLocationAnnotation:coordinate];
    PJWriteAbsoluteLocation(coordinate.latitude, coordinate.longitude);
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];
}

- (void)updateLocationAnnotation:(CLLocationCoordinate2D)coordinate {
    if (!self.locationAnnotation) {
        self.locationAnnotation = [MKPointAnnotation new];
        self.locationAnnotation.title = @"虚拟位置";
        [self.mapView addAnnotation:self.locationAnnotation];
    }
    self.locationAnnotation.coordinate = coordinate;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    UIEdgeInsets insets = self.view.safeAreaInsets;
    CGRect frame = self.panel.frame;
    frame.origin.y = MAX(insets.top + 12, frame.origin.y);
    self.panel.frame = frame;
}

- (void)hideJoystick {
    [self stopMoving];
    PJSetJoystickEnabled(NO);
    self.view.window.hidden = YES;
}

- (void)collapseJoystick {
    [self stopMoving];
    self.collapsedMap = NO;
    CGPoint origin = self.panel.frame.origin;
    self.panel.hidden = YES;
    self.collapsedButton.hidden = NO;
    self.collapsedButton.frame = CGRectMake(origin.x, origin.y, 48, 48);
    self.collapsedButton.layer.cornerRadius = 24;
}

- (void)expandJoystick {
    self.collapsedButton.hidden = YES;
    if (self.collapsedMap) {
        self.mapPanel.hidden = NO;
        BOOL restored = [self restoreMapState];
        [self refreshCurrentLocation:!restored];
        return;
    }
    self.panel.hidden = NO;
}

- (void)dragPanel:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) self.panelDragOrigin = self.panel.frame.origin;
    CGPoint delta = [gesture translationInView:self.view];
    CGRect bounds = self.view.bounds;
    UIEdgeInsets insets = self.view.safeAreaInsets;
    CGFloat x = MIN(MAX(8, self.panelDragOrigin.x + delta.x), bounds.size.width - self.panel.bounds.size.width - 8);
    CGFloat y = MIN(MAX(insets.top + 8, self.panelDragOrigin.y + delta.y), bounds.size.height - self.panel.bounds.size.height - insets.bottom - 8);
    CGRect frame = self.panel.frame;
    frame.origin = CGPointMake(x, y);
    self.panel.frame = frame;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return ![touch.view isDescendantOfView:self.base] && ![touch.view isDescendantOfView:self.speedButton];
}

- (void)moveJoystick:(UIPanGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self.base];
    CGPoint center = CGPointMake(CGRectGetMidX(self.base.bounds), CGRectGetMidY(self.base.bounds));
    CGFloat dx = point.x - center.x;
    CGFloat dy = point.y - center.y;
    CGFloat radius = 31;
    CGFloat length = hypot(dx, dy);
    if (length > radius) {
        dx = dx / length * radius;
        dy = dy / length * radius;
    }
    self.knob.center = CGPointMake(center.x + dx, center.y + dy);
    CGFloat magnitude = MIN(1.0, length / radius);
    if (magnitude < 0.08) magnitude = 0;
    CGFloat clampedLength = hypot(dx, dy);
    self.targetDirection = clampedLength > 0.001
        ? CGPointMake(dx / clampedLength, -dy / clampedLength)
        : CGPointZero;
    self.targetMagnitude = magnitude;
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        self.targetMagnitude = 0;
        [UIView animateWithDuration:0.12 animations:^{
            self.knob.center = center;
        }];
        if (!self.displayLink) [self stopMoving];
    } else if (!self.displayLink) {
        self.status.text = @"行走";
        self.status.textColor = [UIColor colorWithRed:0.25 green:0.95 blue:0.62 alpha:1];
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        self.lastTickTimestamp = 0;
        self.sendAccumulator = 0;
        [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}

- (void)tick:(CADisplayLink *)link {
    NSTimeInterval timestamp = link.timestamp;
    if (self.lastTickTimestamp <= 0) {
        self.lastTickTimestamp = timestamp;
        return;
    }
    NSTimeInterval delta = MIN(0.1, MAX(0.001, timestamp - self.lastTickTimestamp));
    self.lastTickTimestamp = timestamp;

    // Smooth direction and pressure so small finger corrections do not become jumps.
    CGFloat blend = 1.0 - exp(-delta / 0.08);
    self.direction = CGPointMake(
        self.direction.x + (self.targetDirection.x - self.direction.x) * blend,
        self.direction.y + (self.targetDirection.y - self.direction.y) * blend
    );
    self.smoothedMagnitude += (self.targetMagnitude - self.smoothedMagnitude) * blend;
    if (self.targetMagnitude <= 0 && self.smoothedMagnitude < 0.015) {
        [self stopMoving];
        return;
    }
    self.sendAccumulator += delta;
    if (self.sendAccumulator < 0.05) return;
    NSTimeInterval sendDelta = self.sendAccumulator;
    self.sendAccumulator = 0;

    static const double speeds[] = {1.4, 2.5, 5.0};
    double distance = speeds[self.speedIndex] * sendDelta * self.smoothedMagnitude;
    if (distance < 0.001) return;
    [self sendEast:self.direction.x * distance north:self.direction.y * distance moving:YES];
}

- (void)stopMoving {
    [self.displayLink invalidate];
    self.displayLink = nil;
    self.frameCounter = 0;
    self.direction = CGPointZero;
    self.targetDirection = CGPointZero;
    self.targetMagnitude = 0;
    self.smoothedMagnitude = 0;
    self.lastTickTimestamp = 0;
    self.sendAccumulator = 0;
    self.knob.center = CGPointMake(CGRectGetMidX(self.base.bounds), CGRectGetMidY(self.base.bounds));
    self.status.text = @"停止";
    self.status.textColor = [UIColor colorWithWhite:0.8 alpha:1];
    [self sendEast:0 north:0 moving:NO];
}

- (void)changeSpeed {
    self.speedIndex = (self.speedIndex + 1) % 3;
    [self updateSpeedTitle];
}

- (void)updateSpeedTitle {
    NSArray<NSString *> *titles = @[@"步行", @"快走", @"跑步"];
    [self.speedButton setTitle:titles[self.speedIndex] forState:UIControlStateNormal];
}

- (void)sendEast:(double)east north:(double)north moving:(BOOL)moving {
	if (PJWriteJoystickCommand(east, north, moving)) {
		if (!moving) return;
		self.status.text = @"行走";
		self.status.textColor = [UIColor colorWithRed:0.25 green:0.95 blue:0.62 alpha:1];
		return;
	}
	/* Keep the local-proxy path usable on devices without AppsDump3. */
    NSURL *url = [NSURL URLWithString:PJEndpoint];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 0.7;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{
        @"eastMeters": @(east), @"northMeters": @(north), @"moving": @(moving)
    } options:0 error:nil];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(__unused NSData *data, NSURLResponse *response, __unused NSError *error) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if (moving && http.statusCode != 200) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.status.text = @"未连接";
                self.status.textColor = [UIColor colorWithRed:1 green:0.45 blue:0.4 alpha:1];
            });
        }
    }] resume];
}

@end

static PJOverlayWindow *PJWindow;

static void PJShowOverlay(void) {
    if (!PJWindow) return;
    PJWindow.hidden = NO;
}

static void PJRegisterVisibilityObservers(void) {
    static int showToken = 0;
    static int hideToken = 0;
    if (showToken == 0) {
        notify_register_dispatch(PJOverlayShowNotification, &showToken, dispatch_get_main_queue(), ^(int unused) {
            PJShowOverlay();
        });
    }
    if (hideToken == 0) {
        notify_register_dispatch(PJOverlayHideNotification, &hideToken, dispatch_get_main_queue(), ^(int unused) {
            PJWindow.hidden = YES;
        });
    }
}

static void PJInstallOverlay(void) {
    if (PJWindow) return;
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if ([candidate isKindOfClass:UIWindowScene.class] && candidate.activationState != UISceneActivationStateUnattached) {
            scene = (UIWindowScene *)candidate;
            break;
        }
    }
    if (!scene) return;
    PJWindow = [[PJOverlayWindow alloc] initWithWindowScene:scene];
    PJWindow.frame = scene.coordinateSpace.bounds;
    PJWindow.windowLevel = UIWindowLevelAlert + 100;
    PJWindow.backgroundColor = UIColor.clearColor;
    PJWindow.rootViewController = [PJController new];
    PJWindow.hidden = NO;
    PJRegisterVisibilityObservers();
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PJInstallOverlay();
    });
}
%end
