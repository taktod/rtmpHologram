//
//  MyWorker.m
//  rtmpHologram
//
//  Created by taktod on 2016/03/31.
//  Copyright © 2016年 taktod. All rights reserved.
//

#import "MyWorker.h"
#import <GLUT/GLUT.h>
#import <OpenGL/OpenGL.h>
#include <ttLibC/log.h>

// いろいろと利用する構造体
typedef struct {
    // 表示windowのサイズ
    UInt32 win_width;
    UInt32 win_height;
} myWorker_t;

static myWorker_t workerData;

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
//    NSLog(@"何かキャプチャしてます。");
}

- (void) setupStructure
{
    NSLog(@"構造体を初期化しておきます。");
    workerData.win_width = 640;
    workerData.win_height = 480;
}

// glut用の関数いろいろ
static void display() {
    glClear(GL_COLOR_BUFFER_BIT);
    glColor3d(1.0, 1.0, 1.0);
    glBegin(GL_TRIANGLE_FAN);
    glVertex2d(-160, -120);
    glVertex2d( 160, -120);
    glVertex2d( 160,  120);
    glVertex2d(-160,  120);
    glEnd();
    glFlush();
}

static void init() {
    // glの初期化
    glClearColor(0.0, 1.0, 1.0, 1.0);
}

static void resize(int w, int h) {
    glViewport(0, 0, w, h);
    glLoadIdentity();
    // 座標をwindowの真ん中を中心にしておく。
    glOrtho(-w / 2.0, w / 2.0, -h / 2.0, h / 2.0, -1.0, 1.0);
}

static void idle() {
    // 暇なら再描画
    glutPostRedisplay();
}

static void keyboard(unsigned char key, int x, int y) {
    switch(key) {
    case '\x1b': // escを押したらexitで落とす
        exit(0);
        return;
    default:
        break;
    }
}

- (void) setupGlut
{
    NSLog(@"glutを使ってopenglの操作を実施します。");
    // まぁ古いけどね。
    int argc = 0;
    glutInit(&argc, NULL);
    glutInitDisplayMode(GLUT_RGBA);
    glutInitWindowSize(workerData.win_width, workerData.win_height);
    glutCreateWindow("source");
    
    glutDisplayFunc(display);
    glutKeyboardFunc(keyboard);
    glutReshapeFunc(resize);
    glutIdleFunc(idle);

    init();
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
    [self setupStructure];
    [self setupGlut];
    [self setupCamera];
    
    glutMainLoop();
    return YES;
}


@end
