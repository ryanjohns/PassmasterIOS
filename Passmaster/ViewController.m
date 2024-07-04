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
  "<script>"
    "function loadPassmaster() {"
      "var iframe = document.createElement('IFRAME');"
      "iframe.setAttribute('src', 'passmasterjs:loadPassmaster:');"
      "iframe.setAttribute('width', '1px');"
      "iframe.setAttribute('height', '1px');"
      "document.documentElement.appendChild(iframe);"
      "iframe.parentNode.removeChild(iframe);"
      "iframe = null;"
    "}"
  "</script>"
"</head>"
"<body>"
  "<div>"
    "<h2>Passmaster</h2>"
    "<h4>We're sorry, but something went wrong.</h4>"
    "<h4>%@</h4>"
    "<button onclick='loadPassmaster();'>Try again</button>"
  "</div>"
"</body>"
"</html>";

@interface ViewController ()

@property (nonatomic, assign) uint32_t lockTime;
@property (strong, nonatomic) NSString * passmasterUrl;

@end

@implementation ViewController

- (void)viewDidLoad
{
  [super viewDidLoad];

  self.lockTime = 0;
  self.passmasterUrl = [NSString stringWithFormat:@"%@://%@/", PassmasterScheme, PassmasterHost];

  NSString *appVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
  NSString *applicationNameForUserAgent = [NSString stringWithFormat:@"PassmasterIOS/%@", appVersion];
  WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
  config.applicationNameForUserAgent = applicationNameForUserAgent;
  config.limitsNavigationsToAppBoundDomains = YES;

  self.webView = [[WKWebView alloc] initWithFrame:self.view.frame configuration:config];
  self.webView.navigationDelegate = self;
  self.webView.UIDelegate = self;
  self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;

  [self.view addSubview:self.webView];

  // this will delete all keychain items if touch ID not supported
  [self touchIDSupported];

  [self loadPassmaster];
}

- (void)didReceiveMemoryWarning
{
  [super didReceiveMemoryWarning];
}

#pragma mark - WKNavigationDelegate methods

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
  [self.webView setHidden:NO];
  if ([self.webView.URL isEqual:[NSURL URLWithString:self.passmasterUrl]]) {
    [self.webView createWebArchiveDataWithCompletionHandler:^(NSData * data, NSError * error) {
      if (!error) {
        [[NSUserDefaults standardUserDefaults] setObject:data forKey:@"passmaster_webarchive"];
      }
    }];
    [self.webView evaluateJavaScript:@"MobileApp.clickUnlockWithTouchID()" completionHandler:nil];
  }
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
  [self webViewNavigationFailedWithError:error];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
  [self webViewNavigationFailedWithError:error];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
  NSURL *url = navigationAction.request.URL;
  if ([[url scheme] isEqualToString:PassmasterJsScheme]) {
    NSArray *components = [[url absoluteString] componentsSeparatedByString:@":"];
    NSString *function = [components objectAtIndex:1];
    NSMutableArray *arguments = [NSMutableArray array];
    if (components.count > 2) {
      NSRange range;
      range.location = 2;
      range.length = components.count - 2;
      for (NSString *arg in [components subarrayWithRange:range]) {
        [arguments addObject:[arg stringByRemovingPercentEncoding]];
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
    } else if ([function isEqualToString:@"loadPassmaster"]) {
      [self loadPassmaster];
    }
    decisionHandler(WKNavigationActionPolicyCancel);
    return;
  } else if (navigationAction.navigationType == WKNavigationTypeLinkActivated && ![url.absoluteString isEqualToString:self.passmasterUrl]) {
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    decisionHandler(WKNavigationActionPolicyCancel);
    return;
  }
  decisionHandler(WKNavigationActionPolicyAllow);
}

#pragma mark - WKUIDelegate methods

- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler
{
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
    completionHandler();
  }]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completionHandler
{
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
    completionHandler(NO);
  }]];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
    completionHandler(YES);
  }]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt defaultText:(NSString *)defaultText initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSString * _Nullable))completionHandler
{
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:prompt preferredStyle:UIAlertControllerStyleAlert];
  [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
    textField.secureTextEntry = NO;
    textField.text = defaultText;
  }];
  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
    completionHandler(nil);
  }]];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
    completionHandler([alert.textFields.firstObject text]);
  }]];
  [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Public helpers

- (void)loadOrUpdateWebApp
{
  [self.webView evaluateJavaScript:@"MobileApp.appLoaded()" completionHandler:^(NSString * _Nullable result, NSError * _Nullable error) {
    if (error == nil && [result isEqualToString:@"YES"]) {
      [self.webView evaluateJavaScript:@"MobileApp.clickUnlockWithTouchID()" completionHandler:nil];
    } else {
      [self loadPassmaster];
    }
  }];
}

- (void)checkLockTime
{
  if (self.lockTime > 0 && self.lockTime < [[NSDate date] timeIntervalSince1970]) {
    [self.webView evaluateJavaScript:@"MobileApp.lock()" completionHandler:nil];
  }
}

- (void)saveLockTime
{
  [self.webView evaluateJavaScript:@"MobileApp.getTimeoutMinutes()" completionHandler:^(NSString * _Nullable result, NSError * _Nullable error) {
    if (error == nil) {
      NSInteger minutes = [result integerValue];
      if (minutes == 0) {
        self.lockTime = 0;
      } else {
        self.lockTime = [[NSDate dateWithTimeIntervalSinceNow:(minutes * 60)] timeIntervalSince1970];
      }
    }
  }];
}

#pragma mark - Private helpers

- (void)loadPassmaster
{
  NSURL *url = [NSURL URLWithString:self.passmasterUrl];
  [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)webViewNavigationFailedWithError:(NSError *)error
{
  NSData *webArchive = [[NSUserDefaults standardUserDefaults] dataForKey:@"passmaster_webarchive"];
  if (webArchive) {
    [self.webView loadData:webArchive MIMEType:@"application/x-webarchive" characterEncodingName:@"UTF-8" baseURL:[NSURL URLWithString:self.passmasterUrl]];
  } else {
    NSString *errorString = [NSString stringWithFormat:PassmasterErrorHTML, error.localizedDescription];
    [self.webView loadHTMLString:errorString baseURL:nil];
  }
}

- (void)copyToClipboard:(NSString *)text
{
  UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
  NSDate *expiresAt = [NSDate dateWithTimeIntervalSinceNow:90];
  NSArray *pasteboardItems = @[@{UIPasteboardTypeListString[0]: text}];
  NSDictionary *pasteboardOptions = @{UIPasteboardOptionLocalOnly: @YES, UIPasteboardOptionExpirationDate: expiresAt};
  [pasteboard setItems:pasteboardItems options:pasteboardOptions];
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
  [context evaluatePolicy:LAPolicyDeviceOwnerAuthentication localizedReason:@"Unlock Your Accounts" reply:^(BOOL success, NSError *error) {
    if (success) {
      OSStatus keychainErr = noErr;
      CFDataRef passwordData = NULL;
      keychainErr = SecItemCopyMatching((__bridge CFDictionaryRef)[self getKeychainQuery:userId], (CFTypeRef *)&passwordData);
      if (keychainErr == noErr) {
        NSString *password = [[NSString alloc] initWithBytes:[(__bridge_transfer NSData *)passwordData bytes] length:[(__bridge NSData *)passwordData length] encoding:NSUTF8StringEncoding];
        dispatch_async(dispatch_get_main_queue(), ^{
          [self.webView evaluateJavaScript:[NSString stringWithFormat:@"MobileApp.unlockWithPasswordFromTouchID('%@')", password] completionHandler:nil];
        });
      } else if (passwordData) {
        CFRelease(passwordData);
      }
    } else if (error.code == LAErrorUserCancel || error.code == LAErrorPasscodeNotSet) {
      dispatch_async(dispatch_get_main_queue(), ^{
        [self.webView evaluateJavaScript:@"MobileApp.userFallbackForTouchID()" completionHandler:nil];
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
  [self.webView evaluateJavaScript:[NSString stringWithFormat:@"MobileApp.setTouchIDUsability(%@, %@, %@)", (isSupported ? @"true" : @"false"), (hasPassword ? @"true" : @"false"), ([self faceIDSupported] ? @"true" : @"false")] completionHandler:nil];
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
  if ([context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error]) {
    return YES;
  } else {
    [self deleteAllPasswordsForTouchID];
    return NO;
  }
}

- (BOOL)faceIDSupported
{
  LAContext *context = [[LAContext alloc] init];
  NSError *error = nil;
  if ([context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error] && context.biometryType == LABiometryTypeFaceID) {
    return YES;
  }
  return NO;
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
