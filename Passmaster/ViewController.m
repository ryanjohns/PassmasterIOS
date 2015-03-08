//
//  PassmasterViewController.m
//  Passmaster
//
//  Created by Ryan Johns on 3/5/13.
//  Copyright (c) 2013 Passmaster. All rights reserved.
//

#import "ViewController.h"
#import <LocalAuthentication/LocalAuthentication.h>
#import <Security/Security.h>
#import <sys/stat.h>
#import <mach-o/dyld.h>

static const UInt8 keychainItemIdentifier[] = "io.passmaster.Keychain\0";
NSString *const PassmasterScheme = @"https";
NSString *const PassmasterHost = @"passmaster.io";
NSString *const PassmasterJsScheme = @"passmasterjs";
NSString *const PassmasterErrorHTML =
@"<html>"
"<head>"
  "<style type='text/css'>"
    "body { background-color: #8b99ab; color: #fff; text-align: center; font-family: arial, sans-serif; }"
  "</style>"
"</head>"
"<body>"
  "<div>"
    "<h2>Passmaster</h2>"
    "<h4>We're sorry, but something went wrong.</h4>"
    "<h4>%@</h4>"
  "</div>"
"</body>"
"</html>";

@interface ViewController ()

@property (nonatomic, assign) BOOL isJailbroken;
@property (nonatomic, assign) uint32_t lockTime;

@end

@implementation ViewController

- (void)viewDidLoad
{
  [super viewDidLoad];

  self.lockTime = 0;

  UIWebView *tempWebView = [[UIWebView alloc] initWithFrame:CGRectZero];
  NSString *userAgent = [tempWebView stringByEvaluatingJavaScriptFromString:@"navigator.userAgent"];
  if ([userAgent rangeOfString:@"PassmasterIOS"].location == NSNotFound) {
    NSString *appVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    userAgent = [userAgent stringByAppendingString:[NSString stringWithFormat:@" PassmasterIOS/%@", appVersion]];
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{ @"UserAgent":userAgent }];
  }

#if TARGET_IPHONE_SIMULATOR
  self.isJailbroken = NO;
#else
  struct stat s;
  self.isJailbroken = (stat("/bin/sh", &s) == 0) ? YES : NO;
  for (uint32_t count = _dyld_image_count(), i = 0; i < count && !self.isJailbroken; i++) {
    if (strstr(_dyld_get_image_name(i), "MobileSubstrate")) {
      self.isJailbroken = YES;
    }
  }
#endif

  // this will delete all keychain items if jailbroken or touch ID not supported
  [self touchIDSupported];

  [self loadPassmaster];
}

- (void)didReceiveMemoryWarning
{
  [super didReceiveMemoryWarning];
}

#pragma mark - UIWebViewDelegate methods

- (void)webViewDidStartLoad:(UIWebView *)webView
{
  [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
  [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
  [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
  NSString *errorString = [NSString stringWithFormat:PassmasterErrorHTML, error.localizedDescription];
  [self.webView loadHTMLString:errorString baseURL:nil];
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
  NSURL *url = [request URL];
  if ([[url scheme] isEqualToString:PassmasterJsScheme]) {
    NSArray *components = [[url absoluteString] componentsSeparatedByString:@":"];
    NSString *function = [components objectAtIndex:1];
    NSMutableArray *arguments = [NSMutableArray array];
    if (components.count > 2) {
      NSRange range;
      range.location = 2;
      range.length = components.count - 2;
      for (NSString *arg in [components subarrayWithRange:range]) {
        [arguments addObject:[arg stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
      }
    }
    if ([function isEqualToString:@"copyToClipboard"]) {
      [self copyToClipboard:arguments[0]];
    } else if ([function isEqualToString:@"savePasswordForTouchID"]) {
      [self savePasswordForTouchID:arguments[0] password:arguments[1] enabled:arguments[2]];
    } else if ([function isEqualToString:@"deletePasswordForTouchID"]) {
      if ([self passwordSaved:arguments[0]]) {
        [self deletePasswordForTouchID:arguments[0]];
      }
    } else if ([function isEqualToString:@"checkForTouchIDUsability"]) {
      [self checkForTouchIDUsability:arguments[0] enabled:arguments[1]];
    } else if ([function isEqualToString:@"authenticateWithTouchID"]) {
      [self authenticateWithTouchID:arguments[0]];
    }
    return NO;
  } else if (navigationType == UIWebViewNavigationTypeLinkClicked && ![[url host] isEqualToString:PassmasterHost]) {
    [[UIApplication sharedApplication] openURL:url];
    return NO;
  }
  return YES;
}

#pragma mark - Public helpers

- (void)loadOrUpdateWebApp
{
  NSString *isLoaded = [self.webView stringByEvaluatingJavaScriptFromString:@"MobileApp.appLoaded()"];
  if ([isLoaded isEqualToString:@"YES"]) {
    [self.webView stringByEvaluatingJavaScriptFromString:@"MobileApp.updateAppCache()"];
  } else {
    [self loadPassmaster];
  }
}

- (void)checkLockTime
{
  if (self.lockTime > 0 && self.lockTime < [[NSDate date] timeIntervalSince1970]) {
    [self.webView stringByEvaluatingJavaScriptFromString:@"MobileApp.lock()"];
  }
}

- (void)saveLockTime
{
  NSInteger minutes = [[self.webView stringByEvaluatingJavaScriptFromString:@"MobileApp.getTimeoutMinutes()"] integerValue];
  if (minutes == 0) {
    self.lockTime = 0;
  } else {
    self.lockTime = [[NSDate dateWithTimeIntervalSinceNow:(minutes * 60)] timeIntervalSince1970];
  }
}

#pragma mark - Private helpers

- (void)loadPassmaster
{
  NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@/", PassmasterScheme, PassmasterHost]];
  [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)copyToClipboard:(NSString *)text
{
  UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
  pasteboard.string = text;
}

- (void)savePasswordForTouchID:(NSString *)userId password:(NSString *)password enabled:(NSString *)enabled
{
  if (![self touchIDSupported]) {
    return;
  }
  if ([self passwordSaved:userId]) {
    [self deletePasswordForTouchID:userId];
  }
  if (![enabled isEqualToString:@"true"]) {
    return;
  }
  NSDictionary *keychainValue = @{
    (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    (__bridge id)kSecAttrGeneric: [self getKeychainItemID],
    (__bridge id)kSecAttrAccount: [userId dataUsingEncoding:NSUTF8StringEncoding],
    (__bridge id)kSecValueData: [password dataUsingEncoding:NSUTF8StringEncoding]
  };
  SecItemAdd((__bridge CFDictionaryRef)keychainValue, NULL);
}

- (void)deletePasswordForTouchID:(NSString *)userId
{
  NSDictionary *deleteQuery = @{
    (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    (__bridge id)kSecAttrGeneric: [self getKeychainItemID],
    (__bridge id)kSecAttrAccount: [userId dataUsingEncoding:NSUTF8StringEncoding]
  };
  SecItemDelete((__bridge CFDictionaryRef)deleteQuery);
}

- (void)deleteAllPasswordsForTouchID {
  NSDictionary *deleteQuery = @{
    (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    (__bridge id)kSecAttrGeneric: [self getKeychainItemID]
  };
  SecItemDelete((__bridge CFDictionaryRef)deleteQuery);
}

- (void)authenticateWithTouchID:(NSString *)userId
{
  LAContext *context = [[LAContext alloc] init];
  [context evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics localizedReason:@"Authentication is required to unlock your accounts." reply:^(BOOL success, NSError *error) {
    if (success) {
      OSStatus keychainErr = noErr;
      CFDataRef passwordData = NULL;
      keychainErr = SecItemCopyMatching((__bridge CFDictionaryRef)[self getKeychainQuery:userId], (CFTypeRef *)&passwordData);
      if (keychainErr == noErr) {
        NSString *password = [[NSString alloc] initWithBytes:[(__bridge_transfer NSData *)passwordData bytes] length:[(__bridge NSData *)passwordData length] encoding:NSUTF8StringEncoding];
        dispatch_async(dispatch_get_main_queue(), ^{
          [self.webView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"MobileApp.unlockWithPasswordFromTouchID('%@')", password]];
        });
      } else if (passwordData) {
        CFRelease(passwordData);
      }
    } else if (error.code == LAErrorUserFallback) {
      dispatch_async(dispatch_get_main_queue(), ^{
        [self.webView stringByEvaluatingJavaScriptFromString:@"MobileApp.userFallbackForTouchID()"];
      });
    }
  }];
}

- (void)checkForTouchIDUsability:(NSString *)userId enabled:(NSString *)enabled
{
  BOOL isSupported = [self touchIDSupported];
  BOOL hasPassword = [self passwordSaved:userId];
  BOOL userEnabled = [enabled isEqualToString:@"true"];
  if (isSupported && hasPassword && !userEnabled) {
    [self deletePasswordForTouchID:userId];
    hasPassword = NO;
  }
  [self.webView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"MobileApp.setTouchIDUsability(%@, %@)", (isSupported ? @"true" : @"false"), (hasPassword ? @"true" : @"false")]];
}

- (BOOL)passwordSaved:(NSString *)userId
{
  OSStatus keychainErr = noErr;
  CFMutableDictionaryRef outDictionary = nil;
  keychainErr = SecItemCopyMatching((__bridge CFDictionaryRef)[self getKeychainQuery:userId], (CFTypeRef *)&outDictionary);
  if (outDictionary) {
    CFRelease(outDictionary);
  }
  return keychainErr == noErr;
}

- (BOOL)touchIDSupported
{
  LAContext *context = [[LAContext alloc] init];
  NSError *error = nil;
  if (!self.isJailbroken && [context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error]) {
    return YES;
  } else {
    [self deleteAllPasswordsForTouchID];
    return NO;
  }
}

- (NSData *)getKeychainItemID
{
  return [NSData dataWithBytes:keychainItemIdentifier length:strlen((const char *)keychainItemIdentifier)];
}

- (NSDictionary *)getKeychainQuery:(NSString *)userId
{
  return @{
    (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    (__bridge id)kSecReturnData: (__bridge id)kCFBooleanTrue,
    (__bridge id)kSecAttrGeneric: [self getKeychainItemID],
    (__bridge id)kSecAttrAccount: [userId dataUsingEncoding:NSUTF8StringEncoding]
  };
}

@end
