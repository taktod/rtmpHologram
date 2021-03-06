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
#include <ttLibC/frame/frame.h>
#include <ttLibC/frame/video/bgr.h>
#include <ttLibC/frame/video/yuv420.h>
#include <ttLibC/frame/audio/audio.h>

#include <ttLibC/util/audioUnitUtil.h>
#include <ttLibC/encoder/audioConverterEncoder.h>
#include <ttLibC/encoder/vtCompressSessionH264Encoder.h>

#include <ttLibC/net/client/rtmp.h>

#include <ttLibC/util/stlListUtil.h>
#include <ttLibC/resampler/imageResampler.h>

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

    // 転送するデータサイズ
    UInt32 width;
    UInt32 height;

    // フレーム情報
    ttLibC_Bgr *bgr;
    ttLibC_Yuv420 *yuv;
    
    // 音声キャプチャ用
    UInt32 sample_rate;
    UInt32 channel_num;
    ttLibC_AuRecorder *recorder;
    ttLibC_StlList *frame_list;
    ttLibC_StlList *used_frame_list;

    // エンコーダー
    ttLibC_AcEncoder *aac_encoder;
    ttLibC_VtH264Encoder *h264_encoder;
    
    // rtmp
    ttLibC_RtmpConnection *conn;
    ttLibC_RtmpStream *stream;
} myWorker_t;

static myWorker_t workerData;
static NSObject *imageLock;
static NSObject *sendLock;

@interface MyWorker ()

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
    }
}

- (void) setupStructure
{
    NSLog(@"構造体を初期化しておきます。");
    // 画像データの扱いでglutのスレッドとcaptureのスレッドがぶつからないようにするためのlockオブジェクト
    imageLock = [NSObject alloc];
    
    workerData.win_width  = 640;
    workerData.win_height = 480;
    
    workerData.capture_width  = 0;
    workerData.capture_height = 0;

    workerData.texture = 0;

    workerData.bgra = NULL;
    
    workerData.bgr = NULL;
    workerData.yuv = NULL;
    
    workerData.width  = 480;
    workerData.height = 360;

    workerData.sample_rate = 44100; // 44.1kHz
    workerData.channel_num = 1; // モノラル
    workerData.recorder = NULL;
    workerData.frame_list = ttLibC_StlList_make();
    workerData.used_frame_list = ttLibC_StlList_make();

    workerData.aac_encoder = ttLibC_AcEncoder_make(
                                                   workerData.sample_rate,
                                                   workerData.channel_num,
                                                   96000,
                                                   frameType_aac);
    workerData.h264_encoder = ttLibC_VtH264Encoder_make(
                                                        workerData.width,
                                                        workerData.height);
    
    workerData.conn = NULL;
    workerData.stream = NULL;
}

static bool MyWorker_onStatusEventCallback(void *ptr, ttLibC_Amf0Object *obj) {
    ttLibC_Amf0Object *code = ttLibC_Amf0_getElement(obj, "code");
    if(code != NULL && code->type == amf0Type_String) {
        NSLog(@"code:%s", (const char *)code->object);
        if(strcmp((const char *)code->object, "NetConnection.Connect.Success") == 0) {
            // netStreamを作ってpublishを実施します
            workerData.stream = ttLibC_RtmpStream_make(workerData.conn);
            ttLibC_RtmpStream_addEventListener(
                                               workerData.stream,
                                               MyWorker_onStatusEventCallback,
                                               NULL);
            // testという名前で配信
            ttLibC_RtmpStream_publish(
                                      workerData.stream,
                                      "test");
            return true;
        }
        if(strcmp((const char *)code->object, "NetStream.Publish.Start") == 0) {
            // 配信開始できたら、audioRecorderを開始する
            workerData.recorder = ttLibC_AuRecorder_make(
                                                         workerData.sample_rate,
                                                         workerData.channel_num,
                                                         AuRecorderType_DefaultInput,
                                                         0);
            ttLibC_AuRecorder_start(
                                    workerData.recorder,
                                    MyWorker_makePcmCallback,
                                    NULL);
            return true;
        }
        if(strcmp((const char *)code->object, "NetStream.Unpublish.Success") == 0) {
            // done.
            return true;
        }
    }
    return true;
}

- (void) startRtmp
{
    workerData.conn = ttLibC_RtmpConnection_make();
    ttLibC_RtmpConnection_addEventListener(
                                           workerData.conn,
                                           MyWorker_onStatusEventCallback,
                                           NULL);
    ttLibC_RtmpConnection_connect(
                                  workerData.conn,
                                  "rtmp://localhost/live");
}

// 変換関連
static bool MyWorker_h264EncodeCallback(void *ptr, ttLibC_H264 *h264) {
//    NSLog(@"h264ができてます。");
    @synchronized (sendLock) {
        ttLibC_RtmpStream_addFrame(
                                   workerData.stream,
                                   (ttLibC_Frame *)h264);
    }
    return true;
}

static bool MyWorker_aacEncodeCallback(void *ptr, ttLibC_Audio *aac) {
//    NSLog(@"aacができてます。");
    @synchronized (sendLock) {
        ttLibC_RtmpStream_addFrame(
                                   workerData.stream,
                                   (ttLibC_Frame *)aac);
    }
    return true;
}

static bool MyWorker_makePcmCallback(void *ptr, ttLibC_Audio *audio) {
    if(audio->inherit_super.type != frameType_pcmS16) {
        // pcmS16のみ相手する。
        return false;
    }
    ttLibC_Frame *prev_frame = NULL;
    // 利用ずみframeがある程度ある場合はそれを使う。
    if(workerData.used_frame_list->size > 3) {
        prev_frame = (ttLibC_Frame *)ttLibC_StlList_refFirst(workerData.used_frame_list);
        if(prev_frame != NULL) {
            // 取得できたら、リストから撤去
            ttLibC_StlList_remove(workerData.used_frame_list, prev_frame);
        }
    }
    // 別のところで利用するので、cloneのコピーを作る。
    ttLibC_Frame *cloned_frame = ttLibC_Frame_clone(
                                                    prev_frame,
                                                    (ttLibC_Frame *)audio);
    if(cloned_frame == NULL) {
        return false;
    }
    // 利用可能フレームリストに追加
    ttLibC_StlList_addLast(workerData.frame_list, cloned_frame);
    return true;
}

// glut用の関数いろいろ
static void display() {
    @synchronized (imageLock) {
        if(workerData.bgra != NULL) {
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
/*
    glBegin(GL_TRIANGLE_FAN);
    glTexCoord2f(0.0f, 1.0f);
    glVertex2d(-160, -120);
    glTexCoord2f(1.0f, 1.0f);
    glVertex2d( 160, -120);
    glTexCoord2f(1.0f, 0.0f);
    glVertex2d( 160,  120);
    glTexCoord2f(0.0f, 0.0f);
    glVertex2d(-160,  120);
    glEnd();*/
    glBegin(GL_TRIANGLE_FAN);
    glTexCoord2f(1.0f * 7 / 16, 1.0f);
    glVertex2d(-20, 20);
    glTexCoord2f(1.0f * 9 / 16, 1.0f);
    glVertex2d(20, 20);
    glTexCoord2f(1.0f, 1.0f * 5 / 12);
    glVertex2d(160, 160);
    glTexCoord2f(1.0f, 0.0f);
    glVertex2d(160, 260);
    glTexCoord2f(0.0f, 0.0f);
    glVertex2d(-160, 260);
    glTexCoord2f(0.0f, 1.05f * 5 / 12);
    glVertex2d(-160, 160);
    glEnd();
    
    glBegin(GL_TRIANGLE_FAN);
    glTexCoord2f(1.0f * 7 / 16, 1.0f);
    glVertex2d(20, 20);
    glTexCoord2f(1.0f * 9 / 16, 1.0f);
    glVertex2d(20, -20);
    glTexCoord2f(1.0f, 1.0f * 5 / 12);
    glVertex2d(160, -160);
    glTexCoord2f(1.0f, 0.0f);
    glVertex2d(260, -160);
    glTexCoord2f(0.0f, 0.0f);
    glVertex2d(260, 160);
    glTexCoord2f(0.0f, 1.05f * 5 / 12);
    glVertex2d(160, 160);
    glEnd();
    
    glBegin(GL_TRIANGLE_FAN);
    glTexCoord2f(1.0f * 7 / 16, 1.0f);
    glVertex2d(20, -20);
    glTexCoord2f(1.0f * 9 / 16, 1.0f);
    glVertex2d(-20, -20);
    glTexCoord2f(1.0f, 1.0f * 5 / 12);
    glVertex2d(-160, -160);
    glTexCoord2f(1.0f, 0.0f);
    glVertex2d(-160, -260);
    glTexCoord2f(0.0f, 0.0f);
    glVertex2d(160, -260);
    glTexCoord2f(0.0f, 1.05f * 5 / 12);
    glVertex2d(160, -160);
    glEnd();

    glBegin(GL_TRIANGLE_FAN);
    glTexCoord2f(1.0f * 7 / 16, 1.0f);
    glVertex2d(-20, -20);
    glTexCoord2f(1.0f * 9 / 16, 1.0f);
    glVertex2d(-20, 20);
    glTexCoord2f(1.0f, 1.0f * 5 / 12);
    glVertex2d(-160, 160);
    glTexCoord2f(1.0f, 0.0f);
    glVertex2d(-260, 160);
    glTexCoord2f(0.0f, 0.0f);
    glVertex2d(-260, -160);
    glTexCoord2f(0.0f, 1.05f * 5 / 12);
    glVertex2d(-160, -160);
    glEnd();
    // 表示データの中心をキャプチャ
    glReadPixels(
                 (workerData.win_width - workerData.width) / 2,
                 (workerData.win_height - workerData.height) / 2,
                 workerData.width,
                 workerData.height,
                 GL_BGRA,
                 GL_UNSIGNED_BYTE,
                 workerData.bgr->inherit_super.inherit_super.data);
    glDisable(GL_TEXTURE_2D);
    glFlush();
    
    @synchronized (sendLock) {
        // rtmpの送受信内容を更新する。
        if(!ttLibC_RtmpConnection_update(workerData.conn, 10000)) {
            ttLibC_RtmpStream_close(&workerData.stream);
            ttLibC_RtmpConnection_close(&workerData.conn);
        }
    }
    
    // bgrをyuvにする
    ttLibC_Yuv420 *y = ttLibC_ImageResampler_makeYuv420FromBgr(
                                                               workerData.yuv,
                                                               Yuv420Type_planar,
                                                               workerData.bgr);
    if(y == NULL) {
        return;
    }
    workerData.yuv = y;
    // yuvをh264にする
    ttLibC_VtH264Encoder_encode(
                                workerData.h264_encoder,
                                workerData.yuv,
                                MyWorker_h264EncodeCallback,
                                NULL);
    // 音声について処理しておく。
    ttLibC_Frame *frame = NULL;
    BOOL is_first_frame = YES;
    while(workerData.frame_list->size > 2 && (frame = (ttLibC_Frame *)ttLibC_StlList_refFirst(workerData.frame_list)) != NULL) {
        if(is_first_frame) {
            // 初めのフレームの時間に画像の時間を合わせておく。
            workerData.bgr->inherit_super.inherit_super.pts = frame->pts;
            workerData.bgr->inherit_super.inherit_super.timebase = frame->timebase;
            is_first_frame = NO;
        }
        ttLibC_StlList_remove(workerData.frame_list, frame);
        // pcmデータなので、aacに変換する。
        ttLibC_AcEncoder_encode(
                                workerData.aac_encoder,
                                (ttLibC_PcmS16 *)frame,
                                MyWorker_aacEncodeCallback,
                                NULL);
        ttLibC_StlList_addLast(
                               workerData.used_frame_list,
                               frame);
    }
}

static void init() {
    // 転送に利用する画像用のメモリーを作っておく。
    void *data = malloc(workerData.width * workerData.height * 4);
    workerData.bgr = ttLibC_Bgr_make(
                                     NULL,
                                     BgrType_bgra,
                                     workerData.width,
                                     workerData.height,
                                     workerData.width * 4,
                                     data,
                                     workerData.width * workerData.height * 4,
                                     true,
                                     0,
                                     1000);
    // glの初期化
    glClearColor(0.0, 0.0, 0.0, 1.0);
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

    [self startRtmp];

    glutMainLoop();
    return YES;
}

static bool MyWorker_closeFrameCallback(void *ptr, void *item) {
    ttLibC_Frame_close((ttLibC_Frame **)&item);
    return true;
}

- (void) dealloc {
    ttLibC_RtmpStream_close(&workerData.stream);
    ttLibC_RtmpConnection_close(&workerData.conn);
    
    ttLibC_AuRecorder_stop(workerData.recorder);
    ttLibC_AuRecorder_close(&workerData.recorder);
    
    ttLibC_VtH264Encoder_close(&workerData.h264_encoder);
    ttLibC_AcEncoder_close(&workerData.aac_encoder);

    ttLibC_StlList_forEach(workerData.frame_list, MyWorker_closeFrameCallback, NULL);
    ttLibC_StlList_close(&workerData.frame_list);
    ttLibC_StlList_forEach(workerData.used_frame_list, MyWorker_closeFrameCallback, NULL);
    ttLibC_StlList_close(&workerData.used_frame_list);

    if(workerData.bgr != NULL) {
        free(workerData.bgr->inherit_super.inherit_super.data);
    }
    ttLibC_Bgr_close(&workerData.bgr);
    ttLibC_Yuv420_close(&workerData.yuv);
    if(workerData.bgra != NULL) {
        free(workerData.bgra);
        workerData.bgra = NULL;
    }
}

@end
