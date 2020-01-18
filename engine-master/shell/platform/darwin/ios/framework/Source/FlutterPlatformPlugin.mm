// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformPlugin.h"
#include "flutter/fml/logging.h"

#include <AudioToolbox/AudioToolbox.h>
#include <Foundation/Foundation.h>
#include <UIKit/UIApplication.h>
#include <UIKit/UIKit.h>

namespace {

constexpr char kTextPlainFormat[] = "text/plain";
const UInt32 kKeyPressClickSoundId = 1306;

}  // namespaces

namespace flutter {

// TODO(abarth): Move these definitions from system_chrome_impl.cc to here.
const char* const kOrientationUpdateNotificationName =
    "io.flutter.plugin.platform.SystemChromeOrientationNotificationName";
const char* const kOrientationUpdateNotificationKey =
    "io.flutter.plugin.platform.SystemChromeOrientationNotificationKey";
const char* const kOverlayStyleUpdateNotificationName =
    "io.flutter.plugin.platform.SystemChromeOverlayNotificationName";
const char* const kOverlayStyleUpdateNotificationKey =
    "io.flutter.plugin.platform.SystemChromeOverlayNotificationKey";

}  // namespace flutter

using namespace flutter;

@implementation FlutterPlatformPlugin {
  fml::WeakPtr<FlutterEngine> _engine;
}

- (instancetype)init {
  @throw([NSException exceptionWithName:@"FlutterPlatformPlugin must initWithEngine"
                                 reason:nil
                               userInfo:nil]);
}

- (instancetype)initWithEngine:(fml::WeakPtr<FlutterEngine>)engine {
  FML_DCHECK(engine) << "engine must be set";
  self = [super init];

  if (self) {
    _engine = engine;
  }

  return self;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  NSString* method = call.method;
  id args = call.arguments;
  if ([method isEqualToString:@"SystemSound.play"]) {
    [self playSystemSound:args];
    result(nil);
  } else if ([method isEqualToString:@"HapticFeedback.vibrate"]) {
    [self vibrateHapticFeedback:args];
    result(nil);
  } else if ([method isEqualToString:@"SystemChrome.setPreferredOrientations"]) {
    [self setSystemChromePreferredOrientations:args];
    result(nil);
  } else if ([method isEqualToString:@"SystemChrome.setApplicationSwitcherDescription"]) {
    [self setSystemChromeApplicationSwitcherDescription:args];
    result(nil);
  } else if ([method isEqualToString:@"SystemChrome.setEnabledSystemUIOverlays"]) {
    [self setSystemChromeEnabledSystemUIOverlays:args];
    result(nil);
  } else if ([method isEqualToString:@"SystemChrome.restoreSystemUIOverlays"]) {
    [self restoreSystemChromeSystemUIOverlays];
    result(nil);
  } else if ([method isEqualToString:@"SystemChrome.setSystemUIOverlayStyle"]) {
    [self setSystemChromeSystemUIOverlayStyle:args];
    result(nil);
  } else if ([method isEqualToString:@"SystemNavigator.pop"]) {
    NSNumber* isAnimated = args;
    [self popSystemNavigator:isAnimated.boolValue];
    result(nil);
  } else if ([method isEqualToString:@"Clipboard.getData"]) {
    result([self getClipboardData:args]);
  } else if ([method isEqualToString:@"Clipboard.setData"]) {
    [self setClipboardData:args];
    result(nil);
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (void)playSystemSound:(NSString*)soundType {
  if ([soundType isEqualToString:@"SystemSoundType.click"]) {
    // All feedback types are specific to Android and are treated as equal on
    // iOS.
    AudioServicesPlaySystemSound(kKeyPressClickSoundId);
  }
}

- (void)vibrateHapticFeedback:(NSString*)feedbackType {
  if (!feedbackType) {
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
    return;
  }

  if (@available(iOS 10, *)) {
    if ([@"HapticFeedbackType.lightImpact" isEqualToString:feedbackType]) {
      [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    } else if ([@"HapticFeedbackType.mediumImpact" isEqualToString:feedbackType]) {
      [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium]
          impactOccurred];
    } else if ([@"HapticFeedbackType.heavyImpact" isEqualToString:feedbackType]) {
      [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy] impactOccurred];
    } else if ([@"HapticFeedbackType.selectionClick" isEqualToString:feedbackType]) {
      [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
    }
  }
}

- (void)setSystemChromePreferredOrientations:(NSArray*)orientations {
  UIInterfaceOrientationMask mask = 0;

  if (orientations.count == 0) {
    mask |= UIInterfaceOrientationMaskAll;
  } else {
    for (NSString* orientation in orientations) {
      if ([orientation isEqualToString:@"DeviceOrientation.portraitUp"])
        mask |= UIInterfaceOrientationMaskPortrait;
      else if ([orientation isEqualToString:@"DeviceOrientation.portraitDown"])
        mask |= UIInterfaceOrientationMaskPortraitUpsideDown;
      else if ([orientation isEqualToString:@"DeviceOrientation.landscapeLeft"])
        mask |= UIInterfaceOrientationMaskLandscapeLeft;
      else if ([orientation isEqualToString:@"DeviceOrientation.landscapeRight"])
        mask |= UIInterfaceOrientationMaskLandscapeRight;
    }
  }

  if (!mask)
    return;
  [[NSNotificationCenter defaultCenter]
      postNotificationName:@(kOrientationUpdateNotificationName)
                    object:nil
                  userInfo:@{@(kOrientationUpdateNotificationKey) : @(mask)}];
}

- (void)setSystemChromeApplicationSwitcherDescription:(NSDictionary*)object {
  // No counterpart on iOS but is a benign operation. So no asserts.
}

- (void)setSystemChromeEnabledSystemUIOverlays:(NSArray*)overlays {
  // Checks if the top status bar should be visible. This platform ignores all
  // other overlays

  // We opt out of view controller based status bar visibility since we want
  // to be able to modify this on the fly. The key used is
  // UIViewControllerBasedStatusBarAppearance
  [UIApplication sharedApplication].statusBarHidden =
      ![overlays containsObject:@"SystemUiOverlay.top"];
}

- (void)restoreSystemChromeSystemUIOverlays {
  // Nothing to do on iOS.
}

- (void)setSystemChromeSystemUIOverlayStyle:(NSDictionary*)message {
  NSString* style = message[@"statusBarBrightness"];
  if (style == (id)[NSNull null])
    return;

  UIStatusBarStyle statusBarStyle;
  if ([style isEqualToString:@"Brightness.dark"])
    statusBarStyle = UIStatusBarStyleLightContent;
  else if ([style isEqualToString:@"Brightness.light"])
    statusBarStyle = UIStatusBarStyleDefault;
  else
    return;

  NSNumber* infoValue = [[NSBundle mainBundle]
      objectForInfoDictionaryKey:@"UIViewControllerBasedStatusBarAppearance"];
  Boolean delegateToViewController = (infoValue == nil || [infoValue boolValue]);

  if (delegateToViewController) {
    // This notification is respected by the iOS embedder
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@(kOverlayStyleUpdateNotificationName)
                      object:nil
                    userInfo:@{@(kOverlayStyleUpdateNotificationKey) : @(statusBarStyle)}];
  } else {
    // Note: -[UIApplication setStatusBarStyle] is deprecated in iOS9
    // in favor of delegating to the view controller
    [[UIApplication sharedApplication] setStatusBarStyle:statusBarStyle];
  }
}

- (void)popSystemNavigator:(BOOL)isAnimated {
  // Apple's human user guidelines say not to terminate iOS applications. However, if the
  // root view of the app is a navigation controller, it is instructed to back up a level
  // in the navigation hierarchy.
  // It's also possible in an Add2App scenario that the FlutterViewController was presented
  // outside the context of a UINavigationController, and still wants to be popped.
  UIViewController* viewController = [UIApplication sharedApplication].keyWindow.rootViewController;
  if ([viewController isKindOfClass:[UINavigationController class]]) {
    [((UINavigationController*)viewController) popViewControllerAnimated:isAnimated];
  } else {
    auto engineViewController = static_cast<UIViewController*>([_engine.get() viewController]);
    if (engineViewController != viewController) {
      [engineViewController dismissViewControllerAnimated:isAnimated completion:nil];
    }
  }
}

- (NSDictionary*)getClipboardData:(NSString*)format {
  UIPasteboard* pasteboard = [UIPasteboard generalPasteboard];
  if (!format || [format isEqualToString:@(kTextPlainFormat)]) {
    NSString* stringInPasteboard = pasteboard.string;
    // The pasteboard may contain an item but it may not be a string (an image for instance).
    return stringInPasteboard == nil ? nil : @{@"text" : stringInPasteboard};
  }
  return nil;
}

- (void)setClipboardData:(NSDictionary*)data {
  UIPasteboard* pasteboard = [UIPasteboard generalPasteboard];
  if (data[@"text"]) {
    pasteboard.string = data[@"text"];
  } else {
    pasteboard.string = @"null";
  }
}

@end
