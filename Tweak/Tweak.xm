#import <UIKit/UIKit.h>
#import "PJJoystickIPC.h"

static NSString *const PJEndpoint = @"http://127.0.0.1:8888/joystick";

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
@property(nonatomic, strong) UIButton *toggleButton;
@property(nonatomic, strong) UIButton *closeButton;
@property(nonatomic, strong) UIView *base;
@property(nonatomic, strong) UIView *knob;
@property(nonatomic, strong) UILabel *status;
@property(nonatomic, strong) UIButton *speedButton;
@property(nonatomic, strong) CADisplayLink *displayLink;
@property(nonatomic) CGPoint direction;
@property(nonatomic) NSInteger frameCounter;
@property(nonatomic) NSInteger speedIndex;
@property(nonatomic) CGPoint panelDragOrigin;
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
    self.knob.backgroundColor = [UIColor colorWithRed:0.13 green:0.75 blue:0.48 alpha:0.95];
    self.knob.layer.cornerRadius = 24;
    self.knob.layer.shadowColor = UIColor.blackColor.CGColor;
    self.knob.layer.shadowOpacity = 0.35;
    self.knob.layer.shadowRadius = 5;
    [self.base addSubview:self.knob];
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

    self.status = [[UILabel alloc] initWithFrame:CGRectMake(93, 145, 42, 32)];
    self.status.text = @"停止";
    self.status.textColor = [UIColor colorWithWhite:0.8 alpha:1];
    self.status.textAlignment = NSTextAlignmentCenter;
    self.status.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [self.panel addSubview:self.status];
    [self updateSpeedTitle];

    self.toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleButton.frame = CGRectMake(20, 180, 52, 52);
    self.toggleButton.backgroundColor = [UIColor colorWithRed:0.13 green:0.75 blue:0.48 alpha:0.96];
    self.toggleButton.layer.cornerRadius = 26;
    self.toggleButton.layer.shadowColor = UIColor.blackColor.CGColor;
    self.toggleButton.layer.shadowOpacity = 0.3;
    self.toggleButton.layer.shadowRadius = 5;
    self.toggleButton.tintColor = UIColor.whiteColor;
    [self.toggleButton setTitle:@"摇" forState:UIControlStateNormal];
    self.toggleButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    [self.toggleButton addTarget:self action:@selector(showJoystick) forControlEvents:UIControlEventTouchUpInside];
    self.toggleButton.hidden = YES;
    [self.view addSubview:self.toggleButton];
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
    self.panel.hidden = YES;
    self.toggleButton.hidden = NO;
    self.toggleButton.frame = self.panel.frame;
    self.toggleButton.layer.cornerRadius = self.toggleButton.bounds.size.width / 2.0;
}

- (void)showJoystick {
    self.panel.hidden = NO;
    self.toggleButton.hidden = YES;
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
    self.direction = CGPointMake(dx / radius, -dy / radius);
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        [self stopMoving];
    } else if (!self.displayLink) {
        self.status.text = @"行走";
        self.status.textColor = [UIColor colorWithRed:0.25 green:0.95 blue:0.62 alpha:1];
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}

- (void)tick:(CADisplayLink *)link {
    self.frameCounter += 1;
    if (self.frameCounter % 6 != 0) return;
    static const double speeds[] = {1.4, 2.5, 5.0};
    double step = speeds[self.speedIndex] / 10.0;
    [self sendEast:self.direction.x * step north:self.direction.y * step moving:YES];
}

- (void)stopMoving {
    [self.displayLink invalidate];
    self.displayLink = nil;
    self.frameCounter = 0;
    self.direction = CGPointZero;
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
    NSArray<NSString *> *titles = @[@"步行 1.4", @"快走 2.5", @"跑步 5.0"];
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
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PJInstallOverlay();
    });
}
%end
