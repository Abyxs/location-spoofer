#import <Foundation/Foundation.h>
#import <notify.h>

static NSString *const PJSharedCommandPath = @"/var/mobile/Library/Preferences/com.paopaolabs.joystick.command.plist";
static NSString *const PJDarwinNotification = @"com.paopaolabs.joystick.command";

static BOOL PJWriteJoystickCommand(double east, double north, BOOL moving) {
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

static NSDictionary *PJReadJoystickCommand(void) {
    NSData *data = [NSData dataWithContentsOfFile:PJSharedCommandPath options:0 error:nil];
    if (!data) return nil;
    return [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:nil];
}
