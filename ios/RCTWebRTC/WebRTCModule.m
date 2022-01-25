//
//  WebRTCModule.m
//
//  Created by one on 2015/9/24.
//  Copyright © 2015 One. All rights reserved.
//

#if !TARGET_OS_OSX
#import <UIKit/UIKit.h>
#endif

#import <React/RCTBridge.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTUtils.h>
#import <WebRTC/WebRTC.h>

#import <WebRTC/RTCDefaultVideoDecoderFactory.h>
#import <WebRTC/RTCDefaultVideoEncoderFactory.h>

#import "WebRTCModule.h"
#import "WebRTCModule+RTCPeerConnection.h"

@interface WebRTCModule () <RTCVideoRenderer>

@end

@implementation WebRTCModule {
    RCTPromiseResolveBlock _resolveBlock;
    RTCVideoTrack *_frameTrack;
    int _quality;
}

+ (BOOL)requiresMainQueueSetup
{
    return NO;
}

- (void)dealloc
{
  [_localTracks removeAllObjects];
  _localTracks = nil;
  [_localStreams removeAllObjects];
  _localStreams = nil;

  for (NSNumber *peerConnectionId in _peerConnections) {
    RTCPeerConnection *peerConnection = _peerConnections[peerConnectionId];
    peerConnection.delegate = nil;
    [peerConnection close];
  }
  [_peerConnections removeAllObjects];

  _peerConnectionFactory = nil;
}

- (instancetype)init
{
  self = [super init];
  if (self) {
    RTCDefaultVideoDecoderFactory *decoderFactory
      = [[RTCDefaultVideoDecoderFactory alloc] init];
    RTCDefaultVideoEncoderFactory *encoderFactory
      = [[RTCDefaultVideoEncoderFactory alloc] init];
    _peerConnectionFactory
      = [[RTCPeerConnectionFactory alloc] initWithEncoderFactory:encoderFactory
                                                  decoderFactory:decoderFactory];

    _peerConnections = [NSMutableDictionary new];
    _localStreams = [NSMutableDictionary new];
    _localTracks = [NSMutableDictionary new];

    dispatch_queue_attr_t attributes =
    dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                            QOS_CLASS_USER_INITIATED, -1);
    _workerQueue = dispatch_queue_create("WebRTCModule.queue", attributes);
  }

  return self;
}

- (RTCMediaStream*)streamForReactTag:(NSString*)reactTag
{
  RTCMediaStream *stream = _localStreams[reactTag];
  if (!stream) {
    for (NSNumber *peerConnectionId in _peerConnections) {
      RTCPeerConnection *peerConnection = _peerConnections[peerConnectionId];
      stream = peerConnection.remoteStreams[reactTag];
        if (stream) {
        break;
      }
    }
  }
  return stream;
}

RCT_EXPORT_MODULE();

- (dispatch_queue_t)methodQueue
{
  return _workerQueue;
}

- (NSArray<NSString *> *)supportedEvents {
  return @[
    kEventPeerConnectionSignalingStateChanged,
    kEventPeerConnectionStateChanged,
    kEventPeerConnectionAddedStream,
    kEventPeerConnectionRemovedStream,
    kEventPeerConnectionOnRenegotiationNeeded,
    kEventPeerConnectionIceConnectionChanged,
    kEventPeerConnectionIceGatheringChanged,
    kEventPeerConnectionGotICECandidate,
    kEventPeerConnectionDidOpenDataChannel,
    kEventDataChannelStateChanged,
    kEventDataChannelReceiveMessage,
    kEventMediaStreamTrackMuteChanged
  ];
}

RCT_REMAP_METHOD(releaseCapturer,
    resolver:(RCTPromiseResolveBlock)resolve
        rejecter:(RCTPromiseRejectBlock)reject)
{
    [_frameTrack removeRenderer:self];
    _frameTrack = nil;
}

RCT_REMAP_METHOD(captureFrame,
    captureFrame:(nonnull NSString *)streamID
    quality:(nonnull int *)quality
    resolver:(RCTPromiseResolveBlock)resolve
        rejecter:(RCTPromiseRejectBlock)reject)
{
    RTCMediaStream *stream = _localStreams[streamID];
    if (!stream) {
        reject( @"StreamId is invalid", @"StreamId is invalid", nil );
        return;
    }

    _resolveBlock = resolve;
    _quality = quality;
    if (!_frameTrack) {
      _frameTrack = stream.videoTracks.firstObject;
      [_frameTrack addRenderer:self];
    }
}

/** The size of the frame. */
- (void)setSize:(CGSize)size
{

}

/** The frame to be displayed. */
- (void)renderFrame:(nullable RTCVideoFrame *)frame
{
    if( !_resolveBlock ) {
        return;
    }
    NSObject *buffer = (id) frame.buffer;
    if( [buffer isKindOfClass:[RTCCVPixelBuffer class] ] ) {
        RTCCVPixelBuffer *pixelBuffer = (RTCCVPixelBuffer *) buffer;
        CVPixelBufferRef bufferRef = pixelBuffer.pixelBuffer;

        CIImage *ciImage = [CIImage imageWithCVPixelBuffer:bufferRef];

        CIContext *temporaryContext = [CIContext contextWithOptions:nil];
        CGImageRef videoImage = [temporaryContext
                createCGImage:ciImage
                     fromRect:CGRectMake(0, 0,
                             CVPixelBufferGetWidth(bufferRef),
                             CVPixelBufferGetHeight(bufferRef))];
        UIImage *uiImage = [UIImage imageWithCGImage:videoImage
                              scale: 1.0
                              orientation: UIImageOrientationRight
                            ];
        float qFloat = _quality;
        NSString *base64 = [UIImageJPEGRepresentation(uiImage, (qFloat / 100)) base64EncodedStringWithOptions:(NSDataBase64EncodingOptions)0];
        _resolveBlock( base64 );
        _resolveBlock = nil;
        CGImageRelease(videoImage);
    }
};

@end
