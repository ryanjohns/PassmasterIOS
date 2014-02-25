//
//  PassmasterViewController.m
//  Passmaster
//
//  Created by Ryan Johns on 3/5/13.
//  Copyright (c) 2013 Passmaster. All rights reserved.
//

#import "ViewController.h"

NSString *const PassmasterScheme = @"https";
NSString *const PassmasterHost = @"passmaster.io";
NSString *const PassmasterJsScheme = @"passmasterjs";
NSString *const PassmasterJsAlertOverride =
@"window.alert = function(message) {"
  "var iframe = document.createElement('IFRAME');"
  "iframe.setAttribute('src', '%@:alert:' + encodeURIComponent(message));"
  "iframe.setAttribute('width', '1px');"
  "iframe.setAttribute('height', '1px');"
  "document.documentElement.appendChild(iframe);"
  "iframe.parentNode.removeChild(iframe);"
  "iframe = null;"
"};";
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
  [self.webView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:PassmasterJsAlertOverride, PassmasterJsScheme]];
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
    if ([function isEqualToString:@"alert"]) {
      [self alert:argument];
    } else if ([function isEqualToString:@"copyToClipboard"]) {
      [self copyToClipboard:argument];
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

- (void)alert:(NSString *)message
{
  UIAlertView *theAlert = [[UIAlertView alloc] initWithTitle:@"Passmaster" message:message delegate:nil cancelButtonTitle:nil otherButtonTitles:@"OK", nil];
  [theAlert show];
}

- (void)copyToClipboard:(NSString *)text
{
  UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
  pasteboard.string = text;

  [self alert:@"Copied to Clipboard"];
}

@end
