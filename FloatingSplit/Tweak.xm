#import <UIKit/UIKit.h>
#import <objc/message.h>

@interface SBApplication : NSObject
@property(nonatomic, readonly) NSString *bundleIdentifier;
@property(nonatomic, readonly) NSString *displayName;
- (id)mainScene;
@end

@interface SBApplicationController : NSObject
+ (instancetype)sharedInstance;
@property(nonatomic, readonly) NSArray<SBApplication *> *allApplications;
- (SBApplication *)applicationWithBundleIdentifier:(NSString *)bundleIdentifier;
@end

@interface FBScene : NSObject
@property(nonatomic, readonly) id contextHostManager;
@end

@interface FBSceneHostManager : NSObject
- (UIView *)hostViewForRequester:(NSString *)requester enableAndOrderFront:(BOOL)orderFront;
- (void)disableHostingForRequester:(NSString *)requester;
@end

static NSString *const PFSRequester = @"com.paopaolabs.floatingsplit";

static id PFSApplicationController(void) {
    Class controllerClass = NSClassFromString(@"SBApplicationController");
    return controllerClass ? ((id (*)(id, SEL))objc_msgSend)(controllerClass, @selector(sharedInstance)) : nil;
}

@interface PFSWindow : UIWindow
@end

@implementation PFSWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self.rootViewController.view ? nil : hit;
}
@end

@interface PFSController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) UIButton *launcher;
@property(nonatomic, strong) UIView *picker;
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) NSArray<SBApplication *> *applications;
@property(nonatomic, strong) UIView *floatingPanel;
@property(nonatomic, strong) UIView *contentView;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UIButton *restoreButton;
@property(nonatomic, strong) UIView *hostView;
@property(nonatomic, strong) FBSceneHostManager *hostManager;
@property(nonatomic) CGPoint dragOrigin;
@property(nonatomic) CGRect resizeOrigin;
@end

@implementation PFSController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    self.launcher = [UIButton buttonWithType:UIButtonTypeSystem];
    self.launcher.frame = CGRectMake(UIScreen.mainScreen.bounds.size.width - 54, 220, 46, 46);
    self.launcher.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.82];
    self.launcher.layer.cornerRadius = 23;
    self.launcher.layer.borderWidth = 1;
    self.launcher.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.2].CGColor;
    self.launcher.tintColor = UIColor.whiteColor;
    self.launcher.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    [self.launcher setTitle:@"分" forState:UIControlStateNormal];
    [self.launcher addTarget:self action:@selector(togglePicker) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.launcher];

    UIPanGestureRecognizer *launcherPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragLauncher:)];
    [self.launcher addGestureRecognizer:launcherPan];
    [self buildPicker];
    [self buildFloatingPanel];
}

- (void)buildPicker {
    self.picker = [[UIView alloc] initWithFrame:CGRectMake(28, 120, 280, 430)];
    self.picker.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.94];
    self.picker.layer.cornerRadius = 12;
    self.picker.layer.borderWidth = 1;
    self.picker.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
    self.picker.clipsToBounds = YES;
    self.picker.hidden = YES;
    [self.view addSubview:self.picker];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(14, 0, 210, 46)];
    title.text = @"选择悬浮应用";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [self.picker addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(236, 7, 36, 32);
    [close setTitle:@"×" forState:UIControlStateNormal];
    close.tintColor = UIColor.whiteColor;
    close.titleLabel.font = [UIFont systemFontOfSize:22];
    [close addTarget:self action:@selector(togglePicker) forControlEvents:UIControlEventTouchUpInside];
    [self.picker addSubview:close];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 46, 280, 384) style:UITableViewStylePlain];
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorColor = [UIColor colorWithWhite:1 alpha:0.10];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.picker addSubview:self.tableView];
}

- (void)buildFloatingPanel {
    self.floatingPanel = [[UIView alloc] initWithFrame:CGRectMake(20, 100, 330, 520)];
    self.floatingPanel.backgroundColor = UIColor.blackColor;
    self.floatingPanel.layer.cornerRadius = 12;
    self.floatingPanel.layer.borderWidth = 1;
    self.floatingPanel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.24].CGColor;
    self.floatingPanel.clipsToBounds = YES;
    self.floatingPanel.hidden = YES;
    [self.view addSubview:self.floatingPanel];

    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 330, 42)];
    bar.tag = 1001;
    bar.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.96];
    [self.floatingPanel addSubview:bar];
    [bar addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPanel:)]];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, 210, 42)];
    self.titleLabel.textColor = UIColor.whiteColor;
    self.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [bar addSubview:self.titleLabel];

    NSArray *titles = @[@"−", @"×"];
    NSArray *actions = @[NSStringFromSelector(@selector(minimizePanel)), NSStringFromSelector(@selector(closePanel))];
    for (NSInteger index = 0; index < 2; index++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.frame = CGRectMake(242 + index * 44, 0, 44, 42);
        [button setTitle:titles[index] forState:UIControlStateNormal];
        button.tintColor = UIColor.whiteColor;
        button.titleLabel.font = [UIFont systemFontOfSize:20];
        [button addTarget:self action:NSSelectorFromString(actions[index]) forControlEvents:UIControlEventTouchUpInside];
        [bar addSubview:button];
    }

    self.contentView = [[UIView alloc] initWithFrame:CGRectMake(0, 42, 330, 478)];
    self.contentView.backgroundColor = UIColor.blackColor;
    [self.floatingPanel addSubview:self.contentView];

    UIView *resizeHandle = [[UIView alloc] initWithFrame:CGRectMake(306, 496, 24, 24)];
    resizeHandle.tag = 1002;
    resizeHandle.backgroundColor = [UIColor colorWithWhite:1 alpha:0.30];
    resizeHandle.layer.cornerRadius = 12;
    [resizeHandle addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(resizePanel:)]];
    [self.floatingPanel addSubview:resizeHandle];

    self.restoreButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.restoreButton.frame = CGRectMake(12, 280, 52, 52);
    self.restoreButton.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.84];
    self.restoreButton.layer.cornerRadius = 26;
    self.restoreButton.tintColor = UIColor.whiteColor;
    self.restoreButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    [self.restoreButton setTitle:@"窗" forState:UIControlStateNormal];
    [self.restoreButton addTarget:self action:@selector(restorePanel) forControlEvents:UIControlEventTouchUpInside];
    self.restoreButton.hidden = YES;
    [self.view addSubview:self.restoreButton];
}

- (void)togglePicker {
    self.picker.hidden = !self.picker.hidden;
    if (!self.picker.hidden) {
        NSString *springBoardID = NSBundle.mainBundle.bundleIdentifier;
        NSPredicate *filter = [NSPredicate predicateWithBlock:^BOOL(SBApplication *app, NSDictionary *bindings) {
            return app.bundleIdentifier.length > 0 && ![app.bundleIdentifier isEqualToString:springBoardID] && app.displayName.length > 0;
        }];
        NSArray *allApplications = ((id (*)(id, SEL))objc_msgSend)(PFSApplicationController(), @selector(allApplications));
        self.applications = [[allApplications filteredArrayUsingPredicate:filter]
                             sortedArrayUsingComparator:^NSComparisonResult(SBApplication *a, SBApplication *b) {
            return [a.displayName localizedCompare:b.displayName];
        }];
        [self.tableView reloadData];
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.applications.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"App"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"App"];
    SBApplication *app = self.applications[indexPath.row];
    cell.backgroundColor = UIColor.clearColor;
    cell.textLabel.text = app.displayName;
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.detailTextLabel.text = app.bundleIdentifier;
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.65 alpha:1];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    SBApplication *app = self.applications[indexPath.row];
    self.picker.hidden = YES;
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    id workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, NSSelectorFromString(@"defaultWorkspace"));
    SEL opener = NSSelectorFromString(@"openApplicationWithBundleID:");
    if ([workspace respondsToSelector:opener]) {
        ((BOOL (*)(id, SEL, id))objc_msgSend)(workspace, opener, app.bundleIdentifier);
    }
    [self attachApplication:app retry:0];
}

- (void)attachApplication:(SBApplication *)app retry:(NSInteger)retry {
    FBScene *scene = [app mainScene];
    FBSceneHostManager *manager = scene.contextHostManager;
    UIView *host = [manager hostViewForRequester:PFSRequester enableAndOrderFront:YES];
    if (!host && retry < 15) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SBApplication *refreshed = ((id (*)(id, SEL, id))objc_msgSend)(PFSApplicationController(),
                                                                           @selector(applicationWithBundleIdentifier:),
                                                                           app.bundleIdentifier);
            [self attachApplication:refreshed retry:retry + 1];
        });
        return;
    }
    if (!host) return;
    [self.hostView removeFromSuperview];
    [self.hostManager disableHostingForRequester:PFSRequester];
    self.hostManager = manager;
    self.hostView = host;
    host.frame = self.contentView.bounds;
    host.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.contentView addSubview:host];
    self.titleLabel.text = app.displayName;
    self.floatingPanel.hidden = NO;
    self.restoreButton.hidden = YES;
}

- (void)dragLauncher:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) self.dragOrigin = self.launcher.center;
    CGPoint delta = [gesture translationInView:self.view];
    self.launcher.center = CGPointMake(self.dragOrigin.x + delta.x, self.dragOrigin.y + delta.y);
}

- (void)dragPanel:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) self.dragOrigin = self.floatingPanel.frame.origin;
    CGPoint delta = [gesture translationInView:self.view];
    CGRect frame = self.floatingPanel.frame;
    frame.origin = CGPointMake(self.dragOrigin.x + delta.x, self.dragOrigin.y + delta.y);
    self.floatingPanel.frame = frame;
}

- (void)resizePanel:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) self.resizeOrigin = self.floatingPanel.frame;
    CGPoint delta = [gesture translationInView:self.view];
    CGRect frame = self.resizeOrigin;
    frame.size.width = MIN(self.view.bounds.size.width - frame.origin.x, MAX(240, frame.size.width + delta.x));
    frame.size.height = MIN(self.view.bounds.size.height - frame.origin.y, MAX(320, frame.size.height + delta.y));
    self.floatingPanel.frame = frame;
    UIView *bar = [self.floatingPanel viewWithTag:1001];
    bar.frame = CGRectMake(0, 0, frame.size.width, 42);
    self.titleLabel.frame = CGRectMake(12, 0, MAX(80, frame.size.width - 120), 42);
    NSArray *buttons = [bar.subviews filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id view, NSDictionary *bindings) {
        return [view isKindOfClass:UIButton.class];
    }]];
    [buttons enumerateObjectsUsingBlock:^(UIButton *button, NSUInteger index, BOOL *stop) {
        button.frame = CGRectMake(frame.size.width - 88 + index * 44, 0, 44, 42);
    }];
    self.contentView.frame = CGRectMake(0, 42, frame.size.width, frame.size.height - 42);
    [self.floatingPanel viewWithTag:1002].frame = CGRectMake(frame.size.width - 24, frame.size.height - 24, 24, 24);
}

- (void)minimizePanel {
    self.floatingPanel.hidden = YES;
    self.restoreButton.hidden = NO;
}

- (void)restorePanel {
    self.floatingPanel.hidden = NO;
    self.restoreButton.hidden = YES;
}

- (void)closePanel {
    [self.hostView removeFromSuperview];
    [self.hostManager disableHostingForRequester:PFSRequester];
    self.hostView = nil;
    self.hostManager = nil;
    self.floatingPanel.hidden = YES;
    self.restoreButton.hidden = YES;
}

@end

static PFSWindow *PFSOverlayWindow;

static void PFSInstallOverlay(void) {
    if (PFSOverlayWindow) return;
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if ([candidate isKindOfClass:UIWindowScene.class] && candidate.activationState != UISceneActivationStateUnattached) {
            scene = (UIWindowScene *)candidate;
            break;
        }
    }
    if (!scene) return;
    PFSOverlayWindow = [[PFSWindow alloc] initWithWindowScene:scene];
    PFSOverlayWindow.frame = scene.coordinateSpace.bounds;
    PFSOverlayWindow.windowLevel = UIWindowLevelAlert + 80;
    PFSOverlayWindow.backgroundColor = UIColor.clearColor;
    PFSOverlayWindow.rootViewController = [PFSController new];
    PFSOverlayWindow.hidden = NO;
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        PFSInstallOverlay();
    });
}
%end
