#import <Foundation/Foundation.h>
#import <notify.h>

static NSString *const PJSharedCommandPath = @"/var/mobile/Library/Preferences/com.paopaolabs.joystick.command.plist";
static NSString *const PJPreferencesPath = @"/var/mobile/Library/Preferences/com.paopaolabs.joystick.preferences.plist";
static const char *PJDarwinNotification = "com.paopaolabs.joystick.command";
static const char *PJOverlayShowNotification = "com.paopaolabs.joystick.show";
static const char *PJOverlayHideNotification = "com.paopaolabs.joystick.hide";

static __attribute__((unused)) BOOL PJJoystickEnabled(void) {
    NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:PJPreferencesPath];
    NSNumber *enabled = preferences[@"enabled"];
    return enabled ? enabled.boolValue : YES;
}

static __attribute__((unused)) BOOL PJSetJoystickEnabled(BOOL enabled) {
    NSDictionary *preferences = @{ @"enabled": @(enabled) };
    BOOL saved = [preferences writeToFile:PJPreferencesPath atomically:YES];
    notify_post(enabled ? PJOverlayShowNotification : PJOverlayHideNotification);
    return saved;
}

static __attribute__((unused)) BOOL PJWriteJoystickCommand(double east, double north, BOOL moving) {
    NSDictionary *command = @{
        @"eastMeters": @(east),
        @"northMeters": @(north),
        @"moving": @(moving),
        @"timestamp": @([NSDate date].timeIntervalSince1970)
    };
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:command format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    if (!data || ![data writeToFile:PJSharedCommandPath options:NSDataWritingAtomic error:&error]) {
        return NO;
    }
    notify_post(PJDarwinNotification);
    return YES;
}

static __attribute__((unused)) NSDictionary *PJReadJoystickCommand(void) {
    NSData *data = [NSData dataWithContentsOfFile:PJSharedCommandPath options:0 error:nil];
    if (!data) return nil;
    return [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:nil];
}
