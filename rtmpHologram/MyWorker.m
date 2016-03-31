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
    
    // キャプチャ時のサイズ
    UInt32 capture_width;
    UInt32 capture_height;
    
    // テクスチャ
    GLuint texture;
    // キャプチャしたbgraデータ
    void *bgra;
} myWorker_t;

static myWorker_t workerData;
static NSObject *imageLock;

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
    @synchronized (imageLock) {
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        workerData.capture_width = CVPixelBufferGetWidth(imageBuffer);
        workerData.capture_height = CVPixelBufferGetHeight(imageBuffer);
        if(workerData.bgra == NULL) {
            workerData.bgra = malloc(workerData.capture_width * workerData.capture_height * 4);
        }
        CVPixelBufferLockBaseAddress(imageBuffer, 0);
        uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
        memcpy(workerData.bgra, baseAddress, workerData.capture_width * workerData.capture_height * 4);
        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
        NSLog(@"キャプチャできてる。");
    }
}

- (void) setupStructure
{
    NSLog(@"構造体を初期化しておきます。");
    // 画像データの扱いでglutのスレッドとcaptureのスレッドがぶつからないようにするためのlockオブジェクト
    imageLock = [NSObject alloc];
    
    workerData.win_width = 640;
    workerData.win_height = 480;
    
    workerData.capture_width = 0;
    workerData.capture_height = 0;

    workerData.texture = 0;
    workerData.bgra = NULL;
}

// glut用の関数いろいろ
static void display() {
    @synchronized (imageLock) {
        if(workerData.bgra != NULL) {
            NSLog(@"テクスチャ作ってる。");
            glEnable(GL_TEXTURE_2D);
            glBindTexture(GL_TEXTURE_2D, workerData.texture);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexImage2D(GL_TEXTURE_2D, 0, 4, workerData.capture_width, workerData.capture_height, 0, GL_BGRA, GL_UNSIGNED_BYTE, workerData.bgra);
            glDisable(GL_TEXTURE_2D);
        }
    }
    glClear(GL_COLOR_BUFFER_BIT);
    glColor3d(1.0, 1.0, 1.0);
    glEnable(GL_TEXTURE_2D);
    glBindTexture(GL_TEXTURE_2D, workerData.texture);
    glBegin(GL_TRIANGLE_FAN);
    glTexCoord2f(0.0f, 1.0f);
    glVertex2d(-160, -120);
    glTexCoord2f(1.0f, 1.0f);
    glVertex2d( 160, -120);
    glTexCoord2f(1.0f, 0.0f);
    glVertex2d( 160,  120);
    glTexCoord2f(0.0f, 0.0f);
    glVertex2d(-160,  120);
    glEnd();
    glDisable(GL_TEXTURE_2D);
    glFlush();
}

static void init() {
    // glの初期化
    glClearColor(0.0, 1.0, 1.0, 1.0);
    glEnable(GL_TEXTURE_2D);
    glGenTextures(1, &workerData.texture);
    glDisable(GL_TEXTURE_2D);
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
