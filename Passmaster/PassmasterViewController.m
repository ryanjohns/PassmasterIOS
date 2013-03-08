//
//  PassmasterViewController.m
//  Passmaster
//
//  Created by Ryan Johns on 3/5/13.
//  Copyright (c) 2013 Passmaster. All rights reserved.
//

#import "PassmasterViewController.h"

NSString *const PassmasterURL = @"https://passmaster.io/";
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

@implementation PassmasterViewController

- (void)viewDidLoad
{
  [super viewDidLoad];
  [self loadPassmaster];
}

- (void)didReceiveMemoryWarning
{
  [super didReceiveMemoryWarning];
}

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

- (void)loadPassmaster
{
  [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:PassmasterURL]]];
}

- (void)loadOrUpdateWebApp
{
  NSString *isLoaded = [self.webView stringByEvaluatingJavaScriptFromString:@"MobileApp.appLoaded()"];
  if ([isLoaded isEqual: @"YES"]) {
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

@end
