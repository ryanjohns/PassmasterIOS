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

@implementation ViewController

- (void)viewDidLoad
{
  [super viewDidLoad];

  UIWebView *tempWebView = [[UIWebView alloc] initWithFrame:CGRectZero];
  NSString *userAgent = [tempWebView stringByEvaluatingJavaScriptFromString:@"navigator.userAgent"];
  if ([userAgent rangeOfString:@"PassmasterIOS"].location == NSNotFound) {
    NSString *appVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    userAgent = [userAgent stringByAppendingString:[NSString stringWithFormat:@" PassmasterIOS/%@", appVersion]];
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{ @"UserAgent":userAgent }];
  }

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
    NSString *argument = @"";
    if (components.count > 2) {
      NSRange range;
      range.location = 2;
      range.length = components.count - 2;
      argument = [[[components subarrayWithRange:range] componentsJoinedByString:@":"] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    }
    if ([function isEqualToString:@"copyToClipboard"]) {
      [self copyToClipboard:argument];
    } else if ([function isEqualToString:@"savePasswordForTouchID"]) {
      [self savePasswordForTouchID:argument];
    } else if ([function isEqualToString:@"deletePasswordForTouchID"]) {
      [self deletePasswordForTouchID];
    } else if ([function isEqualToString:@"checkForTouchIDAndPassword"]) {
      [self checkForTouchIDAndPassword];
    } else if ([function isEqualToString:@"authenticateWithTouchID"]) {
      [self authenticateWithTouchID];
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
  if ([[NSDate date] timeIntervalSinceDate:[self lockTime]] >= 0) {
    [self.webView stringByEvaluatingJavaScriptFromString:@"MobileApp.lock()"];
  }
}

- (void)saveLockTime
{
  NSInteger minutes = [[self.webView stringByEvaluatingJavaScriptFromString:@"MobileApp.getTimeoutMinutes()"] integerValue];
  [self setLockTime:[[NSDate alloc] initWithTimeIntervalSinceNow:(minutes * 60)]];
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

- (void)savePasswordForTouchID:(NSString *)password
{
  [self deletePasswordForTouchID];
  if (![self touchIDSupported]) {
    return;
  }
  NSDictionary *keychainValue = @{
    (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    (__bridge id)kSecAttrGeneric: [self getKeychainItemID],
    (__bridge id)kSecValueData: [password dataUsingEncoding:NSUTF8StringEncoding]
  };
  SecItemAdd((__bridge CFDictionaryRef)keychainValue, NULL);
}

- (void)deletePasswordForTouchID
{
  if ([self passwordSaved]) {
    NSDictionary *deleteQuery = @{
      (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
      (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      (__bridge id)kSecAttrGeneric: [self getKeychainItemID]
    };
    SecItemDelete((__bridge CFDictionaryRef)deleteQuery);
  }
}

- (void)authenticateWithTouchID
{
  LAContext *context = [[LAContext alloc] init];
  [context evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics localizedReason:@"Use fingerprint to unlock accounts" reply:^(BOOL success, NSError *error) {
    if (success) {
      OSStatus keychainErr = noErr;
      CFDataRef passwordData = NULL;
      keychainErr = SecItemCopyMatching((__bridge CFDictionaryRef)[self getKeychainQuery], (CFTypeRef *)&passwordData);
      if (keychainErr == noErr) {
        NSString *password = [[NSString alloc] initWithBytes:[(__bridge_transfer NSData *)passwordData bytes] length:[(__bridge NSData *)passwordData length] encoding:NSUTF8StringEncoding];
        dispatch_async(dispatch_get_main_queue(), ^{
          [self.webView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"MobileApp.unlockWithPasswordFromTouchID('%@')", password]];
        });
      } else if (passwordData) {
        CFRelease(passwordData);
      }
    }
  }];
}

- (void)checkForTouchIDAndPassword
{
  if ([self touchIDSupported] && [self passwordSaved]) {
    [self.webView stringByEvaluatingJavaScriptFromString:@"MobileApp.setUnlockWithTouchIDBtnVisibility(true)"];
  } else {
    [self.webView stringByEvaluatingJavaScriptFromString:@"MobileApp.setUnlockWithTouchIDBtnVisibility(false)"];
  }
}

- (BOOL)passwordSaved
{
  OSStatus keychainErr = noErr;
  CFMutableDictionaryRef outDictionary = nil;
  keychainErr = SecItemCopyMatching((__bridge CFDictionaryRef)[self getKeychainQuery], (CFTypeRef *)&outDictionary);
  if (outDictionary) {
    CFRelease(outDictionary);
  }
  return keychainErr == noErr;
}

- (BOOL)touchIDSupported
{
  LAContext *context = [[LAContext alloc] init];
  NSError *error = nil;
  return [context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error];
}

- (NSData *)getKeychainItemID
{
  return [NSData dataWithBytes:keychainItemIdentifier length:strlen((const char *)keychainItemIdentifier)];
}

- (NSDictionary *)getKeychainQuery
{
  return @{
    (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    (__bridge id)kSecReturnData: (__bridge id)kCFBooleanTrue,
    (__bridge id)kSecAttrGeneric: [self getKeychainItemID]
  };
}

@end
