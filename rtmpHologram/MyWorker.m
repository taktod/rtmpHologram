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
    UInt32 _width;
    UInt32 _height;
}

@property (strong, nonatomic) AVCaptureDeviceInput *videoInput;
@property (strong, nonatomic) AVCaptureVideoDataOutput *videoDataOutput;
@property (strong, nonatomic) AVCaptureSession *session;

@end

@implementation MyWorker

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
    NSLog(@"何かキャプチャしてます。");
}

- (void) setupCamera
{
    NSLog(@"カメラのセットアップします。");
    NSError *error = nil;
    AVCaptureDevice *camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    self.videoInput = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error];
    
    // ビデオデータの出力作成
    NSDictionary *settings = @{
                               (id)kCVPixelBufferPixelFormatTypeKey:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
                               };
    self.videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    self.videoDataOutput.videoSettings = settings;
    [self.videoDataOutput setSampleBufferDelegate:self queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)];
    
    // カメラからの入力を作成
    self.session = [[AVCaptureSession alloc] init];
    [self.session addInput:self.videoInput];
    [self.session addOutput:self.videoDataOutput];
    self.session.sessionPreset = AVCaptureSessionPresetMedium;
    
    AVCaptureConnection *videoConnection = nil;
    [self.session beginConfiguration];
    for(AVCaptureConnection *connection in [self.videoDataOutput connections]) {
        for(AVCaptureInputPort *port in [connection inputPorts]) {
            if([[port mediaType] isEqual:AVMediaTypeVideo]) {
                videoConnection = connection;
            }
        }
    }
    if([videoConnection isVideoOrientationSupported]) {
        [videoConnection setVideoOrientation:AVCaptureVideoOrientationPortrait];
    }
    
    [self.session commitConfiguration];
    [self.session startRunning];
    // 設定はこれでOK
}

- (BOOL) doWork
{
    NSLog(@"start work.");
    [self setupCamera];
    
    while(true) {
        usleep(1000);
    }
    return YES;
}


@end
