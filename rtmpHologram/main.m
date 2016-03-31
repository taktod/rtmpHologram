//
//  main.m
//  rtmpHologram
//
//  Created by taktod on 2016/03/31.
//  Copyright © 2016年 taktod. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MyWorker.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // insert code here...
        [[MyWorker alloc] doWork];
    }
    return 0;
}
