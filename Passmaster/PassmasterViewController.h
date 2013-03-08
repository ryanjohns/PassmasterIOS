//
//  PassmasterViewController.h
//  Passmaster
//
//  Created by Ryan Johns on 3/5/13.
//  Copyright (c) 2013 Passmaster. All rights reserved.
//

#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSString *const PassmasterURL;
FOUNDATION_EXPORT NSString *const PassmasterErrorHTML;

@interface PassmasterViewController : UIViewController <UIWebViewDelegate>

@property (weak, nonatomic) IBOutlet UIWebView *webView;

- (void)loadPassmaster;
- (void)loadOrUpdateWebApp;

@end
