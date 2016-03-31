//
//  MyWorker.h
//  rtmpHologram
//
//  Created by taktod on 2016/03/31.
//  Copyright © 2016年 taktod. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface MyWorker : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>

- (BOOL) doWork;
@end
