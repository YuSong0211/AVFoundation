
#import "THCameraController.h"
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "NSFileManager+THAdditions.h"

NSString *const THThumbnailCreatedNotification = @"THThumbnailCreated";

@interface THCameraController () <AVCaptureFileOutputRecordingDelegate>

@property (strong, nonatomic) dispatch_queue_t videoQueue;//视频队列
@property (strong, nonatomic) AVCaptureSession *captureSession;//捕捉会话
@property (weak, nonatomic) AVCaptureDeviceInput *activeVideoInput;//输入 活跃
@property (strong, nonatomic) AVCaptureStillImageOutput *imageOutput;
@property (strong, nonatomic) AVCaptureMovieFileOutput *movieOutput;
@property (strong, nonatomic) NSURL *outputURL;

@end

@implementation THCameraController

//创建捕捉回话，AVCaptureSession
- (BOOL)setupSession:(NSError **)error {
    
    //创建捕捉会话，AVCaptureSession是捕捉场景的中心枢纽
    self.captureSession = [[AVCaptureSession alloc]init];
    //设置图像的分辨率
    self.captureSession.sessionPreset = AVCaptureSessionPresetHigh;
    //拿到默认视频捕捉设备，ios系统返回后置摄像头
    AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    //讲捕捉设备封装成AVCaptureDeviceInput
    AVCaptureDeviceInput * videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:error];
    
        //判断videoInput是否有效
    if (videoInput) {
           //
        if ([self.captureSession canAddInput:videoInput]) {
         
            //将videoInput添加到captureSession中
            [self.captureSession addInput:videoInput];
            self.activeVideoInput = videoInput;
            
        }
    }else{
    
        return NO;
    }
    
    //选择默认音频捕捉设备 即返回一个内置麦克风
    AVCaptureDevice* audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    //为这个设备创建一个捕捉设备输入
    AVCaptureDeviceInput* audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:error];
    //判断audioInput是否有效
    if (audioInput) {
        //canAddInput :
        if ([self.captureSession canAddInput:audioInput]) {
            [self.captureSession addInput:audioInput];
        }
    }else{
    
        return NO;
    }
    //AVCapturesStillImageOutput 实例 从摄像头捕捉静态图片
    self.imageOutput = [[AVCaptureStillImageOutput alloc]init];
    
    // 配置字典：希望捕捉到时JPEG格式的图片
    self.imageOutput.outputSettings = @{AVVideoCodecKey:AVVideoCodecJPEG};
    
    //输出链接 判断是否可用，可用则添加到输出链接中去
    if ([self.captureSession canAddOutput:self.imageOutput]) {
        
        [self.captureSession addOutput:self.imageOutput];
    }
    
    //创建一个VACaptureMovieFileOutput 实例，视频文件输出   ，用于将Quick Time 电影录制到文件系统
    self.movieOutput = [[AVCaptureMovieFileOutput alloc]init];
    
    //输出链接 判断是否可用，可用则添加到输出链接中去
    if ([self.captureSession canAddOutput:self.movieOutput]) {
        
        [self.captureSession addOutput:self.movieOutput];
    }
    
    self.videoQueue =  dispatch_queue_create("ss.VideoQueue", NULL);
    // Listing 6.4

    return YES;
}
///启动和停止捕捉会话
- (void)startSession {
    // Listing 6.5
    //检查是否处于运动状态
    if (![self.captureSession isRunning]) {
        
        //使用同步调用会损耗一定的时间，则用异步的方式处理
        dispatch_async(self.videoQueue, ^{
            [self.captureSession startRunning];
        });
    }
}

- (void)stopSession {

    // Listing 6.5
    
    if ([self.captureSession isRunning]) {
        dispatch_async(self.videoQueue, ^{
            [self.captureSession stopRunning];
        });
    }

}

#pragma mark - Device Configuration
/// 配置摄像头的支持方法
- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition)position {

    // Listing 6.6
    //获取可用视频设备
    NSArray *devicess = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    //遍历可用摄像设备 并返回positon 参数值
    for (AVCaptureDevice *device in devicess) {
        
        if (device.position == position) {
            
            return device;
        }
    }
    
    
    
    return nil;
}

- (AVCaptureDevice *)activeCamera {

    // Listing 6.6
    //返回当前捕捉会话对应的摄像头的device 属性
    return self.activeVideoInput.device;
    
}

//返回当前未激活的摄像头
- (AVCaptureDevice *)inactiveCamera {

    // Listing 6.6
    //通过查找当前激活摄像头的反向摄像头获得，如果设备只有1个摄像头，则返回nil
    AVCaptureDevice *device = nil;
    if (self.cameraCount > 1) {
        
        if ([self activeCamera].position == AVCaptureDevicePositionBack) {
            
            device = [self cameraWithPosition:AVCaptureDevicePositionFront];
        }else{
            device = [self cameraWithPosition:AVCaptureDevicePositionBack];
        }
    }

    
    return device;
}

//判断是否有超过一个摄像头可用
- (BOOL)canSwitchCameras {

    // Listing 6.6
    
    return self.cameraCount > 0;
}
//可用视频捕捉设备的数量
- (NSUInteger)cameraCount {

    // Listing 6.6
    
    return [[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] count];
}

//切换摄像头
- (BOOL)switchCameras {

    // Listing 6.7
    
    //判断是否有多个摄像头
    if (![self canSwitchCameras]) {
        return NO;
    }
    
    //获取当前设备的反向设备
    NSError *error;
    AVCaptureDevice *videoDevice = [self inactiveCamera];
    
    //将输入设备封装成AVCaptureDeviceInput
    AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
    
    //判断videoInput是否为nil
    if (videoInput) {
        //标注原配置变化开始
        [self.captureSession beginConfiguration];
        
        //将捕捉会话中，原本的捕捉输入设备移除
        [self.captureSession removeInput:self.activeVideoInput];
        
        //判断新的设备是否能加入
        if ([self.captureSession canAddInput:videoInput]) {
            
            //能加入成功 ，则讲videoInput 作为新的视频捕捉设备
            [self.captureSession addInput:videoInput];
            
            // 将获得设备改为 videoInput
            self.activeVideoInput = videoInput;
        }else{
        
            //如果新设备，无法加入，则将原本的视频捕捉设备重新加入到捕捉会话中
            [self.captureSession addInput:self.activeVideoInput];
        }
        
        //配置完成后，AVCaptureSession commitConfiguration 会分批的将所有变更整合咋一起、
        [self.captureSession commitConfiguration];
        
        
    }else{
    
        //创建AVCaptureDeviceInput 出现错误，则通知委托来处理该错误
        [self.delegate deviceConfigurationFailedWithError:error];
    }
    return YES;
}

#pragma mark - Focus Methods

- (BOOL)cameraSupportsTapToFocus {
    
    // Listing 6.8
    
    //询问激活中的摄像头是否支持兴趣点对焦
    return [[self activeCamera]isFocusPointOfInterestSupported];
}

- (void)focusAtPoint:(CGPoint)point {
    
    // Listing 6.8
    AVCaptureDevice * device = [self activeCamera];
    //是否支持兴趣点对焦 & 是否自动对焦模式
    if (device.isFocusPointOfInterestSupported && [device isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
        
        NSError * error;
        //锁定设备准备配置，如果获得了锁
        if ([device lockForConfiguration:&error]) {
            
            //将focusPointOfInterest 属性设置CGPoint
            device.focusPointOfInterest = point;
            //focus设置
            device.focusMode = AVCaptureFocusModeAutoFocus;
            
          //释放改锁定
            [device unlockForConfiguration];
        }else{
        
            //错误，侧返回给错误处理代理
            [self.delegate deviceConfigurationFailedWithError:error];
        }
    }
    
}

#pragma mark - Exposure Methods
//点击曝光
- (BOOL)cameraSupportsTapToExpose {
 
    // Listing 6.9
    //是否支持曝光
    return [[self activeCamera] isExposurePointOfInterestSupported];
}

static const NSString* THCameraAjustingExposureContext;
- (void)exposeAtPoint:(CGPoint)point {

    // Listing 6.9
    AVCaptureDevice *device = [self activeCamera];
    
    AVCaptureExposureMode exposureMode = AVCaptureExposureModeContinuousAutoExposure;
    //判断是否支持 AVCaptureExposeModeContinuousAutoExposure模式
    if (device.isExposurePointOfInterestSupported && [device isExposureModeSupported:exposureMode]) {
        
        [device isExposureModeSupported:exposureMode];
        
        NSError * error;
        
        //锁定设备准备配置
        if ([device lockForConfiguration:&error]) {
             //配置期望值
            device.exposurePointOfInterest = point;
            device.exposureMode = exposureMode;
            
            //判断设备是否支持锁定曝光的模式
            if ([device isExposureModeSupported:AVCaptureExposureModeLocked]) {
                
                //支持，
                [device addObserver:self forKeyPath:@"adjustingExposure" options:NSKeyValueObservingOptionNew context:&THCameraAjustingExposureContext];
            }
            
            //释放该锁定
            [device unlockForConfiguration];
        }else{
        
            [self.delegate deviceConfigurationFailedWithError:error];
        }
    }
    
    

}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {

    // Listing 6.9
    //判断context （上下文）是否为THCamerAdjustingExpoosureContext
    if (context == &THCameraAjustingExposureContext) {
        //获取device
        AVCaptureDevice *device = (AVCaptureDevice *)object;
        //判断设备是否不再调整曝光等级，确定设备的exposurMode 是否可以设置为AVCaptureExposureModeLocked
        if (!device.isAdjustingExposure && [device isExposureModeSupported:AVCaptureExposureModeLocked]) {
            
            //移除作为adjustingExposure的self 就不会得到后续的变更通知
            [object removeObserver:self forKeyPath:@"adjustingExposure" context:&THCameraAjustingExposureContext];;
            
            //移除方式调回主队列
            dispatch_async(dispatch_get_main_queue(), ^{
                NSError * error;
                if ([device lockForConfiguration:&error]) {
                    
                    //修改exposureMode
                    device.exposureMode = AVCaptureExposureModeLocked;
                    
                    //释放该锁定
                    [device unlockForConfiguration];
                    
                }else{
                
                    [self.delegate deviceConfigurationFailedWithError:error];
                }
            });
        }
    }else{
    
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }

}

///restFosesAndExposureModes的方法实现

//重新设置对焦&曝光
- (void)resetFocusAndExposureModes {

    // Listing 6.10
    
    AVCaptureDevice * device = [self activeCamera];
    
    AVCaptureFocusMode fousMode = AVCaptureFocusModeAutoFocus;
    
    //获取对焦兴趣点 和连续自动对焦模式 是否被支持
    BOOL canResetFocus = [device isFocusPointOfInterestSupported]&& [device isFocusModeSupported:fousMode];
    
    AVCaptureExposureMode exposureMode = AVCaptureExposureModeAutoExpose;
    
    //确认曝光度可以被重设
    BOOL canResetExposure = [device isFocusPointOfInterestSupported] && [device isExposureModeSupported:exposureMode];
    //捕捉设备 空间左上角（0.0）
    CGPoint centPoint = CGPointMake(0.5f, 0.5f);
    NSError *error;
    
    //锁定设备，
    if ([device lockForConfiguration:&error]) {
        
        // 焦点可点 则修改
        if (canResetFocus) {
            device.focusMode = fousMode;
            device.focusPointOfInterest = centPoint;
        }
        
        //曝光度可设，则设置为期望的曝光模式
        if (canResetExposure) {
            device.exposureMode = exposureMode;
            device.exposurePointOfInterest = centPoint;
            
            //释放锁定
            [device unlockForConfiguration];
        }
    }else{
    
        [self.delegate deviceConfigurationFailedWithError:error];
    }
    

}



#pragma mark - Flash and Torch Modes 点击对焦方法实现

//判断是否有闪光灯
- (BOOL)cameraHasFlash {

    // Listing 6.11
    
    return [[self activeCamera]hasFlash];
}
//闪光灯模式
- (AVCaptureFlashMode)flashMode {

    // Listing 6.11
    
    return [[self activeCamera]flashMode];
}

//是否支持电筒
- (BOOL)cameraHasTorch {
    
    // Listing 6.11
    
    return [[self activeCamera]hasTorch];
}
//手电筒模式
- (AVCaptureTorchMode)torchMode {
    
    // Listing 6.11
    
    return [[self activeCamera]torchMode];
}
- (void)setFlashMode:(AVCaptureFlashMode)flashMode {

    // Listing 6.11

}


//设置是否打开手电筒
- (void)setTorchMode:(AVCaptureTorchMode)torchMode {

    AVCaptureDevice *device = [self activeCamera];
    if ([device isTorchModeSupported:torchMode]) {
        
        NSError * error;
        if ([device lockForConfiguration:&error]) {
            device.torchMode = torchMode;
            [device unlockForConfiguration];
        }else{
         
            [self.delegate deviceConfigurationFailedWithError:error];
        
        }
    }
    // Listing 6.11
    
}


#pragma mark - Image Capture Methods //捕捉静态图片
/*
 AVCaptureStillImageOutput 是AVCaptureOutput的子类。用于捕捉图片
 */

- (void)captureStillImage {

    // Listing 6.12
    //获取连接
    AVCaptureConnection * connection = [self.imageOutput connectionWithMediaType:AVMediaTypeVideo];
    
    //程序只支持纵向，但是如果用户横向拍照时，需要调整结果照片的方向
    //判断是否支持设置视频方向
    if (connection.isVideoOrientationSupported) {
        
        //获取方向值
        connection.videoOrientation = [self currentVideoOrientation];
    }
    //定义一个handler 块，会返回1个图片的NSData数据
    id handle = ^(CMSampleBufferRef sampleBuffer,NSError *error){
        
        if (sampleBuffer != NULL) {
            NSData * imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:sampleBuffer];
            UIImage *image = [[UIImage alloc]initWithData:imageData];
            //重点：捕捉图片成功后，将图片传递出去
            [self writeImageToAssetsLibrary:image];
        }else{
        
            NSLog(@"NULL sampleBuffer:%@",[error localizedDescription]);
        }
        
    };
    
    // 捕捉静态图片
    [self.imageOutput captureStillImageAsynchronouslyFromConnection:connection completionHandler:handle];

}

//获取方向值
- (AVCaptureVideoOrientation)currentVideoOrientation {
    
    // Listing 6.12
    // Listing 6.13
    AVCaptureVideoOrientation orientation;
    //获取UIDvice 的orientation
    switch ([UIDevice currentDevice].orientation) {
        case UIDeviceOrientationPortrait:
            orientation = AVCaptureVideoOrientationPortrait;
            break;
        case UIDeviceOrientationLandscapeRight:
            orientation = AVCaptureVideoOrientationLandscapeRight;
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            orientation = AVCaptureVideoOrientationPortraitUpsideDown;
            break;
            
        default:
            orientation = AVCaptureVideoOrientationLandscapeRight;
            break;
    }
    
    
    return 0;
}
/*
 Assets Library 框架
 用来让开发者通过代码式访问iOS photo
 注意：会访问到相册，需要修改plist 权限。否则会导致项目崩溃
 */

- (void)writeImageToAssetsLibrary:(UIImage *)image {

    // Listing 6.13
    //创建ALAsesetsLibrary 实例
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc]init];
    //参数1：图片（参数CGImageRef 所以image.CGImage ）
    //:方向参数转为NSUInterger
    //写入成功、失败处理
    [library writeImageToSavedPhotosAlbum:image.CGImage orientation:(NSUInteger)image.imageOrientation completionBlock:^(NSURL *assetURL, NSError *error) {
        //成功后，发送捕捉图片通知。用于绘制程序的左下角的缩略图
        if (!error) {
            
            [self postThumbnailNotifification:image];
        }else{
        
            //失败打印错误信息
            id message = [error localizedDescription];
            NSLog(@"%@",message);
        }
    }];
    
}
//发送缩略图
- (void)postThumbnailNotifification:(UIImage *)image {

    // Listing 6.13
    //回到这队列
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc postNotificationName:THThumbnailCreatedNotification object:image];
    
}

#pragma mark - Video Capture Methods  捕捉视频
//判断是否录制状态
- (BOOL)isRecording {

    // Listing 6.14
    
    return self.movieOutput.isRecording;
}
//开始录制
- (void)startRecording {

    // Listing 6.14
    if (![self isRecording]) {
        //获取当前捕捉链接信息，用于捕捉视频数据配置一些核心的属性
        AVCaptureConnection *videoConnection = [self.movieOutput connectionWithMediaType:AVMediaTypeVideo];
        
        //判断是个支持设置videoOrientation属性
        if ([videoConnection isVideoOrientationSupported]) {
            //支持侧修改当前视频方向
            videoConnection.videoOrientation = [self currentVideoOrientation];
        }
        
        //判断是否支持视频稳定 可以显著提高视频的质量，只会再录制视频文件涉及
        if ([videoConnection isVideoStabilizationSupported]) {
            
            videoConnection.enablesVideoStabilizationWhenAvailable = YES;
        }
        
        AVCaptureDevice * device = [self activeCamera];
        
        //摄像头可以进行平滑对焦模式操作，即减慢摄像头镜头对焦速度。当用户易懂噢拍摄时摄像头会尝试快速自动对焦
        if (device.isSmoothAutoFocusEnabled) {
            
            NSError * error;
            if ([device lockForConfiguration:&error]) {
                
                device.smoothAutoFocusEnabled = YES;
                [device unlockForConfiguration];
            }else{
            
                [self.delegate deviceConfigurationFailedWithError:error];
            }
        }
        
        //查找写入捕捉视频唯一的文件系统URL
        self.outputURL = [self uniqueURL];
        
        //在捕捉输出上调用方法 参数1：录制保存路径 参数2： 代理
        [self.movieOutput startRecordingToOutputFileURL:self.outputURL recordingDelegate:self];
    }

}

- (CMTime)recordedDuration {
    return self.movieOutput.recordedDuration;
}
//   写入视频唯一系统URL
- (NSURL *)uniqueURL {

    NSFileManager * fileManager = [NSFileManager defaultManager];
    
    //temporaryDriectoryWithTemplateString 可以将文件写入创建唯一命名目录；
    NSString * dirPath = [fileManager temporaryDirectoryWithTemplateString:@"kamera.xx"];

    if (dirPath) {
        NSString * filePath = [dirPath stringByAppendingPathComponent:@"kamera_movie.mov"];
        
        return [NSURL fileURLWithPath:filePath];
    }
    // Listing 6.14
    
    return nil;
}
//停止录制
- (void)stopRecording {

    //是否正在录制
    if ([self isRecording]) {
        [self.movieOutput stopRecording];
    }
    // Listing 6.14
}

#pragma mark - AVCaptureFileOutputRecordingDelegate

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL
      fromConnections:(NSArray *)connections
                error:(NSError *)error {

    //错误
    if (error) {
        
        [self.delegate mediaCaptureFailedWithError:error];
    }else{
    
        //写入
        [self writeVideoToAssetsLibrary:[self.outputURL copy]];
    }
    
    self.outputURL = nil;
    // Listing 6.15

}
//写入捕捉到的视频
- (void)writeVideoToAssetsLibrary:(NSURL *)videoURL {

    //ALAsetsLibrary 实例 提供写入视频接口
    ALAssetsLibrary* library = [[ALAssetsLibrary alloc]init];
    //写资源库写入前，检查视频是否可以被写入 （写入钱尽量养成判断的习惯）

    if ([library videoAtPathIsCompatibleWithSavedPhotosAlbum:videoURL]) {
        
        //创建block块
        ALAssetsLibraryWriteVideoCompletionBlock completionBlock;
        completionBlock  = ^(NSURL *assetURL,NSError * error)
        {
        
            if (error) {
                
                [self.delegate assetLibraryWriteFailedWithError:error];
            }else{
            
                //用于界面展示视频缩略图
                [self generateThumbnailForVideoAtURL:videoURL];
            }
        };
        
        //执行实际写入资源库的动作
        
        [library writeVideoAtPathToSavedPhotosAlbum:videoURL completionBlock:completionBlock];
    }
    // Listing 6.15
    
}

//获取视频左下角缩略图
- (void)generateThumbnailForVideoAtURL:(NSURL *)videoURL {

    //在videoQueue
    dispatch_async(self.videoQueue, ^{
       
        //建立新的AVAsset & AVAssetImageGenerator
        AVAsset *asset = [AVAsset assetWithURL:videoURL];
        
        AVAssetImageGenerator *imageGenerator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
        
        //设置maximumSize 宽为100 高为0 根据视频的宽度比来计算图片的高度
        imageGenerator.maximumSize = CGSizeMake(100.0f, 0.0f);
        
        //捕捉视频缩略图会考虑视频的变化（如视频的方向变化），如果不设置，缩略图的方向可能出错
        imageGenerator.appliesPreferredTrackTransform = YES;
        
        //获取CGImageRef图片 注意需要自己管理他的创建和释放
        CGImageRef imageRef = [imageGenerator copyCGImageAtTime:kCMTimeZero actualTime:NULL error:nil];
        
        //将图片转化为UIImage
        
        UIImage *image = [UIImage imageWithCIImage:(__bridge CIImage * _Nonnull)(imageRef)];
        //释放cgimageRef imageRef 防止内存泄漏
        CGImageRelease(imageRef);
        //回到主线程
        dispatch_async(dispatch_get_main_queue(), ^{
            //发送通知传递最新的image
            [self postThumbnailNotifification:image];
        });
        
    });
    // Listing 6.15
    
}


@end

