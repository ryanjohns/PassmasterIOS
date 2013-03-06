//
//  PassmasterViewController.m
//  Passmaster
//
//  Created by Ryan Johns on 3/5/13.
//  Copyright (c) 2013 Passmaster. All rights reserved.
//

#import "PassmasterViewController.h"

@interface PassmasterViewController ()

@end

@implementation PassmasterViewController

- (void)viewDidLoad
{
  [super viewDidLoad];
  // Do any additional setup after loading the view, typically from a nib.
  [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"http://passmaster.local/"]]];
}

- (void)didReceiveMemoryWarning
{
  [super didReceiveMemoryWarning];
  // Dispose of any resources that can be recreated.
}

@end
