//
//  WebRTCModule+RTCMediaStream.m
//
//  Created by one on 2015/9/24.
//  Copyright © 2015 One. All rights reserved.
//

#import <objc/runtime.h>

#import <WebRTC/RTCCameraVideoCapturer.h>
#import <WebRTC/RTCVideoTrack.h>
#import <WebRTC/RTCMediaConstraints.h>

#import "RTCMediaStreamTrack+React.h"
#import "WebRTCModule+RTCPeerConnection.h"

#import "ScreenCapturer.h"
#import "ScreenCaptureController.h"
#import "VideoCaptureController.h"

@implementation WebRTCModule (RTCMediaStream)

/**
 * {@link https://www.w3.org/TR/mediacapture-streams/#navigatorusermediaerrorcallback}
 */
typedef void (^NavigatorUserMediaErrorCallback)(NSString *errorType, NSString *errorMessage);

/**
 * {@link https://www.w3.org/TR/mediacapture-streams/#navigatorusermediasuccesscallback}
 */
typedef void (^NavigatorUserMediaSuccessCallback)(RTCMediaStream *mediaStream);

/**
 * Initializes a new {@link RTCAudioTrack} which satisfies specific constraints,
 * adds it to a specific {@link RTCMediaStream}, and reports success to a
 * specific callback. Implements the audio-specific counterpart of the
 * {@code getUserMedia()} algorithm.
 *
 * @param constraints The {@code MediaStreamConstraints} which the new
 * {@code RTCAudioTrack} instance is to satisfy.
 * @param successCallback The {@link NavigatorUserMediaSuccessCallback} to which
 * success is to be reported.
 * @param errorCallback The {@link NavigatorUserMediaErrorCallback} to which
 * failure is to be reported.
 * @param mediaStream The {@link RTCMediaStream} which is being initialized as
 * part of the execution of the {@code getUserMedia()} algorithm, to which a
 * new {@code RTCAudioTrack} is to be added, and which is to be reported to
 * {@code successCallback} upon success.
 */
- (void)getUserAudio:(NSDictionary *)constraints
     successCallback:(NavigatorUserMediaSuccessCallback)successCallback
       errorCallback:(NavigatorUserMediaErrorCallback)errorCallback
         mediaStream:(RTCMediaStream *)mediaStream {
  NSString *trackId = [[NSUUID UUID] UUIDString];
  RTCAudioTrack *audioTrack
    = [self.peerConnectionFactory audioTrackWithTrackId:trackId];

  [mediaStream addAudioTrack:audioTrack];

#if !TARGET_IPHONE_SIMULATOR
  RTCCameraVideoCapturer *videoCapturer = [[RTCCameraVideoCapturer alloc] initWithDelegate:videoSource];
  VideoCaptureController *videoCaptureController
        = [[VideoCaptureController alloc] initWithCapturer:videoCapturer
                                            andConstraints:constraints[@"video"]];
  videoTrack.captureController = videoCaptureController;
  [videoCaptureController startCapture];
#endif

  return videoTrack;
}

- (RTCVideoTrack *)createScreenCaptureVideoTrack {
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_OSX
    return nil;
#endif

    RTCVideoSource *videoSource = [self.peerConnectionFactory videoSourceForScreenCast:YES];

    NSString *trackUUID = [[NSUUID UUID] UUIDString];
    RTCVideoTrack *videoTrack = [self.peerConnectionFactory videoTrackWithSource:videoSource trackId:trackUUID];

    ScreenCapturer *screenCapturer = [[ScreenCapturer alloc] initWithDelegate:videoSource];
    ScreenCaptureController *screenCaptureController = [[ScreenCaptureController alloc] initWithCapturer:screenCapturer];
    videoTrack.captureController = screenCaptureController;
    [screenCaptureController startCapture];

    return videoTrack;
}

RCT_EXPORT_METHOD(getDisplayMedia:(RCTPromiseResolveBlock)resolve
                         rejecter:(RCTPromiseRejectBlock)reject) {
    RTCVideoTrack *videoTrack = [self createScreenCaptureVideoTrack];

    if (videoTrack == nil) {
        reject(@"DOMException", @"AbortError", nil);
        return;
    }

    NSString *mediaStreamId = [[NSUUID UUID] UUIDString];
    RTCMediaStream *mediaStream
      = [self.peerConnectionFactory mediaStreamWithStreamId:mediaStreamId];
    [mediaStream addVideoTrack:videoTrack];

    NSString *trackId = videoTrack.trackId;
    self.localTracks[trackId] = videoTrack;

    NSDictionary *trackInfo = @{
                                @"enabled": @(videoTrack.isEnabled),
                                @"id": videoTrack.trackId,
                                @"kind": videoTrack.kind,
                                @"label": videoTrack.trackId,
                                @"readyState": @"live",
                                @"remote": @(NO)
                                };

    self.localStreams[mediaStreamId] = mediaStream;
    resolve(@{ @"streamId": mediaStreamId, @"track": trackInfo });
}

/**
  * Implements {@code getUserMedia}. Note that at this point constraints have
  * been normalized and permissions have been granted. The constraints only
  * contain keys for which permissions have already been granted, that is,
  * if audio permission was not granted, there will be no "audio" key in
  * the constraints dictionary.
  */
RCT_EXPORT_METHOD(getUserMedia:(NSDictionary *)constraints
               successCallback:(RCTResponseSenderBlock)successCallback
                 errorCallback:(RCTResponseSenderBlock)errorCallback) {
  // Initialize RTCMediaStream with a unique label in order to allow multiple
  // RTCMediaStream instances initialized by multiple getUserMedia calls to be
  // added to 1 RTCPeerConnection instance. As suggested by
  // https://www.w3.org/TR/mediacapture-streams/#mediastream to be a good
  // practice, use a UUID (conforming to RFC4122).
  NSString *mediaStreamId = [[NSUUID UUID] UUIDString];
  RTCMediaStream *mediaStream
    = [self.peerConnectionFactory mediaStreamWithStreamId:mediaStreamId];

  if (constraints[@"audio"]) {
      audioTrack = [self createAudioTrack:constraints];
  }
  if (constraints[@"video"]) {
      videoTrack = [self createVideoTrack:constraints];
  }

  if (audioTrack == nil && videoTrack == nil) {
    // Fail with DOMException with name AbortError as per:
    // https://www.w3.org/TR/mediacapture-streams/#dom-mediadevices-getusermedia
    errorCallback(@[ @"DOMException", @"AbortError" ]);
    return;
  }

  NSString *mediaStreamId = [[NSUUID UUID] UUIDString];
  RTCMediaStream *mediaStream
    = [self.peerConnectionFactory mediaStreamWithStreamId:mediaStreamId];
  NSMutableArray *tracks = [NSMutableArray array];
  NSMutableArray *tmp = [NSMutableArray array];
  if (audioTrack)
      [tmp addObject:audioTrack];
  if (videoTrack)
      [tmp addObject:videoTrack];

  for (RTCMediaStreamTrack *track in tmp) {
    if ([track.kind isEqualToString:@"audio"]) {
      [mediaStream addAudioTrack:(RTCAudioTrack *)track];
    } else if([track.kind isEqualToString:@"video"]) {
      [mediaStream addVideoTrack:(RTCVideoTrack *)track];
    }

    NSString *trackId = track.trackId;

    self.localTracks[trackId] = track;
    
    NSDictionary *settings = @{};
    if ([track.kind isEqualToString:@"video"]) {
        RTCVideoTrack *videoTrack = (RTCVideoTrack *)track;
        VideoCaptureController *vcc = (VideoCaptureController *)videoTrack.captureController;
        AVCaptureDeviceFormat *format = vcc.selectedFormat;
        CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
        settings = @{
            @"height": @(dimensions.height),
            @"width": @(dimensions.width),
            @"frameRate": @(3)
        };
    }

    [tracks addObject:@{
                        @"enabled": @(track.isEnabled),
                        @"id": trackId,
                        @"kind": track.kind,
                        @"label": trackId,
                        @"readyState": @"live",
                        @"remote": @(NO),
                        @"settings": settings
                        }];


  }

  RTCVideoSource *videoSource = [self.peerConnectionFactory videoSource];

#pragma mark - Other stream related APIs

RCT_EXPORT_METHOD(enumerateDevices:(RCTResponseSenderBlock)callback)
{
    NSMutableArray *devices = [NSMutableArray array];
    AVCaptureDeviceDiscoverySession *videoevicesSession
        = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[ AVCaptureDeviceTypeBuiltInWideAngleCamera ]
                                                                 mediaType:AVMediaTypeVideo
                                                                  position:AVCaptureDevicePositionUnspecified];
    for (AVCaptureDevice *device in videoevicesSession.devices) {
        NSString *position = @"unknown";
        if (device.position == AVCaptureDevicePositionBack) {
            position = @"environment";
        } else if (device.position == AVCaptureDevicePositionFront) {
            position = @"front";
        }
        NSString *label = @"Unknown video device";
        if (device.localizedName != nil) {
            label = device.localizedName;
        }
        [devices addObject:@{
                             @"facing": position,
                             @"deviceId": device.uniqueID,
                             @"groupId": @"",
                             @"label": label,
                             @"kind": @"videoinput",
                             }];
    }
    AVCaptureDeviceDiscoverySession *audioDevicesSession
        = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[ AVCaptureDeviceTypeBuiltInMicrophone ]
                                                                 mediaType:AVMediaTypeAudio
                                                                  position:AVCaptureDevicePositionUnspecified];
    for (AVCaptureDevice *device in audioDevicesSession.devices) {
        NSString *label = @"Unknown audio device";
        if (device.localizedName != nil) {
            label = device.localizedName;
        }
        [devices addObject:@{
                             @"deviceId": device.uniqueID,
                             @"groupId": @"",
                             @"label": label,
                             @"kind": @"audioinput",
                             }];
    }
    callback(@[devices]);
}

RCT_EXPORT_METHOD(mediaStreamCreate:(nonnull NSString *)streamID)
{
    RTCMediaStream *mediaStream = [self.peerConnectionFactory mediaStreamWithStreamId:streamID];
    self.localStreams[streamID] = mediaStream;
}

RCT_EXPORT_METHOD(mediaStreamAddTrack:(nonnull NSString *)streamID : (nonnull NSString *)trackID)
{
    RTCMediaStream *mediaStream = self.localStreams[streamID];
    RTCMediaStreamTrack *track = [self trackForId:trackID];

    if (mediaStream && track) {
        if ([track.kind isEqualToString:@"audio"]) {
            [mediaStream addAudioTrack:(RTCAudioTrack *)track];
        } else if([track.kind isEqualToString:@"video"]) {
            [mediaStream addVideoTrack:(RTCVideoTrack *)track];
        }
    }
}

RCT_EXPORT_METHOD(mediaStreamRemoveTrack:(nonnull NSString *)streamID : (nonnull NSString *)trackID)
{
    RTCMediaStream *mediaStream = self.localStreams[streamID];
    RTCMediaStreamTrack *track = [self trackForId:trackID];

    if (mediaStream && track) {
        if ([track.kind isEqualToString:@"audio"]) {
            [mediaStream removeAudioTrack:(RTCAudioTrack *)track];
        } else if([track.kind isEqualToString:@"video"]) {
            [mediaStream removeVideoTrack:(RTCVideoTrack *)track];
        }
    }
}

RCT_EXPORT_METHOD(mediaStreamRelease:(nonnull NSString *)streamID)
{
  RTCMediaStream *stream = self.localStreams[streamID];
  if (stream) {
    [self.localStreams removeObjectForKey:streamID];
  }
}

RCT_EXPORT_METHOD(mediaStreamTrackRelease:(nonnull NSString *)trackID)
{
    RTCMediaStreamTrack *track = self.localTracks[trackID];
    if (track) {
        track.isEnabled = NO;
        [track.captureController stopCapture];
        [self.localTracks removeObjectForKey:trackID];
    }
}

RCT_EXPORT_METHOD(mediaStreamTrackSetEnabled:(nonnull NSString *)trackID : (BOOL)enabled)
{
  RTCMediaStreamTrack *track = [self trackForId:trackID];
  if (track) {
    track.isEnabled = enabled;
    if (track.captureController) {  // It could be a remote track!
      if (enabled) {
        [track.captureController startCapture];
      } else {
        [track.captureController stopCapture];
      }
    }
  }
}

RCT_EXPORT_METHOD(mediaStreamTrackSwitchCamera:(nonnull NSString *)trackID)
{
  RTCMediaStreamTrack *track = self.localTracks[trackID];
  if (track) {
    RTCVideoTrack *videoTrack = (RTCVideoTrack *)track;
    [(VideoCaptureController *)videoTrack.captureController switchCamera];
  }
}

#pragma mark - Helpers

- (RTCMediaStreamTrack*)trackForId:(NSString*)trackId
{
  RTCMediaStreamTrack *track = self.localTracks[trackId];
  if (!track) {
    for (NSNumber *peerConnectionId in self.peerConnections) {
      RTCPeerConnection *peerConnection = self.peerConnections[peerConnectionId];
      track = peerConnection.remoteTracks[trackId];
      if (track) {
        break;
      }
    }
  }
  return track;
}

/**
 * Obtains local media content of a specific type. Requests access for the
 * specified {@code mediaType} if necessary. In other words, implements a media
 * type-specific iteration of the {@code getUserMedia()} algorithm.
 *
 * @param mediaType Either {@link AVMediaTypAudio} or {@link AVMediaTypeVideo}
 * which specifies the type of the local media content to obtain.
 * @param constraints The {@code MediaStreamConstraints} which are to be
 * satisfied by the obtained local media content.
 * @param successCallback The {@link NavigatorUserMediaSuccessCallback} to which
 * success is to be reported.
 * @param errorCallback The {@link NavigatorUserMediaErrorCallback} to which
 * failure is to be reported.
 * @param mediaStream The {@link RTCMediaStream} which is to collect the
 * obtained local media content of the specified {@code mediaType}.
 */
- (void)requestAccessForMediaType:(NSString *)mediaType
                      constraints:(NSDictionary *)constraints
                  successCallback:(NavigatorUserMediaSuccessCallback)successCallback
                    errorCallback:(NavigatorUserMediaErrorCallback)errorCallback
                      mediaStream:(RTCMediaStream *)mediaStream {
  // According to step 6.2.1 of the getUserMedia() algorithm, if there is no
  // source, fail "with a new DOMException object whose name attribute has the
  // value NotFoundError."
  // XXX The following approach does not work for audio in Simulator. That is
  // because audio capture is done using AVAudioSession which does not use
  // AVCaptureDevice there. Anyway, Simulator will not (visually) request access
  // for audio.
  if (mediaType == AVMediaTypeVideo
      && [AVCaptureDevice devicesWithMediaType:mediaType].count == 0) {
    // Since successCallback and errorCallback are asynchronously invoked
    // elsewhere, make sure that the invocation here is consistent.
    dispatch_async(dispatch_get_main_queue(), ^ {
      errorCallback(@"DOMException", @"NotFoundError");
    });
    return;
  }

  [AVCaptureDevice
    requestAccessForMediaType:mediaType
    completionHandler:^ (BOOL granted) {
      dispatch_async(dispatch_get_main_queue(), ^ {
        if (granted) {
          NavigatorUserMediaSuccessCallback scb
            = ^ (RTCMediaStream *mediaStream) {
              [self getUserMedia:constraints
                 successCallback:successCallback
                   errorCallback:errorCallback
                     mediaStream:mediaStream];
            };

          if (mediaType == AVMediaTypeAudio) {
            [self getUserAudio:constraints
               successCallback:scb
                 errorCallback:errorCallback
                   mediaStream:mediaStream];
          } else if (mediaType == AVMediaTypeVideo) {
            [self getUserVideo:constraints
               successCallback:scb
                 errorCallback:errorCallback
                   mediaStream:mediaStream];
          }
        } else {
          // According to step 10 Permission Failure of the getUserMedia()
          // algorithm, if the user has denied permission, fail "with a new
          // DOMException object whose name attribute has the value
          // NotAllowedError."
          errorCallback(@"DOMException", @"NotAllowedError");
        }
      });
    }];
}

@end
