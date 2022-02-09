//
//  PassmasterViewController.h
//  Passmaster
//
//  Created by Ryan Johns on 3/5/13.
//  Copyright (c) 2013 Passmaster. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface ViewController : UIViewController <WKNavigationDelegate, WKUIDelegate>

@property (strong, nonatomic) IBOutlet WKWebView *webView;

- (void)loadOrUpdateWebApp;
- (void)checkLockTime;
- (void)saveLockTime;

@end
