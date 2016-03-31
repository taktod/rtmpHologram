//
//  MyWorker.m
//  rtmpHologram
//
//  Created by taktod on 2016/03/31.
//  Copyright © 2016年 taktod. All rights reserved.
//

#import "MyWorker.h"
#include <ttLibC/log.h>

@interface MyWorker () {
    
}

@end

@implementation MyWorker

- (BOOL) doWork
{
    NSLog(@"start work.");
    ERR_PRINT("test");
    return YES;
}


@end
