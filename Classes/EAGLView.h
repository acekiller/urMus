//
//  EAGLView.h
//  urMus
//
//  Created by Georg Essl on 6/20/09.
//  Copyright Georg Essl 2009. All rights reserved. See LICENSE.txt for license details.
//

#import <UIKit/UIKit.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES1/gl.h>
#import <OpenGLES/ES1/glext.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import "CaptureSessionManager.h"
#include <string>

#undef SANDWICH_SUPPORT

#ifdef SANDWICH_SUPPORT
#import "UdpServerSocket.h"
#import "SandwichTypes.h"
#import "SandwichUpdateListener.h"
#endif

/*
This class wraps the CAEAGLLayer from CoreAnimation into a convenient UIView subclass.
The view content is basically an EAGL surface you render your OpenGL scene into.
Note that setting the view non-opaque will only work if the EAGL surface has an alpha channel.
*/

//#define USEUDP
#ifdef USEUDP
#import "AsyncUdpSocket.h"
#else
#import "TCPServer.h"
#import <Foundation/NSNetServices.h>
#endif
#import <Foundation/Foundation.h>

#define MAX_FINGERS 10

@interface urNetServiceDiscovery : NSObject <NSNetServiceBrowserDelegate>
{
@public
    NSMutableArray *remoteIPs;
	NSNetService *netService;
	NSMutableArray *_services;
	NSNetServiceBrowser *_netServiceBrowser;    
}
@end

#ifdef SANDWICH_SUPPORT
#ifdef USEUDP
@interface EAGLView : UIView <UIAccelerometerDelegate,CLLocationManagerDelegate,SandwichUpdateDelegate, AsyncUdpSocketDelegate,CaptureSessionManagerDelegate, NSNetServiceDelegate, NSNetServiceBrowserDelegate>
#else
@interface EAGLView : UIView <UIAccelerometerDelegate,CLLocationManagerDelegate,SandwichUpdateDelegate, TCPServerDelegate,CaptureSessionManagerDelegate, NSNetServiceDelegate, NSNetServiceBrowserDelegate>
#endif
#else
#ifdef USEUDP
@interface EAGLView : UIView <UIAccelerometerDelegate,CLLocationManagerDelegate, AsyncUdpSocketDelegate,CaptureSessionManagerDelegate, NSNetServiceDelegate, NSNetServiceBrowserDelegate>
#else
@interface EAGLView : UIView <UIAccelerometerDelegate,CLLocationManagerDelegate, TCPServerDelegate,CaptureSessionManagerDelegate, NSNetServiceDelegate, NSNetServiceBrowserDelegate>
#endif
#endif
{
@public
	NSNetService *netService;
    NSMutableArray *remoteIPs;
	CaptureSessionManager *captureManager;
@private
    /* The pixel dimensions of the backbuffer */
    GLint backingWidth;
    GLint backingHeight;
    
    EAGLContext *context;
    
    /* OpenGL names for the renderbuffer and framebuffers used to render to this view */
    GLuint viewRenderbuffer, viewFramebuffer;
    
    /* OpenGL name for the depth buffer that is attached to viewFramebuffer, if it exists (0 if it does not exist) */
    GLuint depthRenderbuffer;
    
    NSTimer *animationTimer;
    NSTimeInterval animationInterval;
	CLLocationManager *locationManager;
	CMMotionManager *motionManager;
	NSOperationQueue *opQ;
#ifdef USEUDP
	AsyncUdpSocket		*_server;
#else
	TCPServer			*_server;
#endif
	NSInputStream		*_inStream;
	NSOutputStream		*_outStream;
	BOOL				_inReady;
	BOOL				_outReady;
	
	int	max_displays;
	int current_display;
	AVAssetWriter *videoWriter;
	AVAssetWriterInput* writerInput;
	AVAssetWriterInputPixelBufferAdaptor *adaptor;
	
	int displaynumber;
@private
//	id<EAGLViewDelegate> _delegate;
	NSString *_searchingForServicesString;
	NSString *_ownName;
	NSNetService *_ownEntry;
	BOOL _showDisclosureIndicators;
	NSMutableArray *_services;
	NSNetServiceBrowser *_netServiceBrowser;
    NSMutableDictionary *searchtype;
	NSNetService *_currentResolve;
	NSTimer *_timer;
	BOOL _needsActivityIndicator;
	BOOL _initialWaitOver;
	GLuint	_cameraTexture;
}

@property (nonatomic, retain) CLLocationManager *locationManager;
@property (nonatomic, retain) EAGLContext *context;
@property NSTimeInterval animationInterval;
@property(nonatomic,retain) NSNetService* netService;
@property(retain) CaptureSessionManager *captureManager;

//- (id)initWithFrame:(CGRect)frame andContextSharegroup:(EAGLSharegroup*)passedSharegroup;
- (id)initWithFrame:(CGRect)frame andContextSharegroup:(EAGLContext*)passedContext;
- (void)startAnimation;
- (void)stopAnimation;
- (void)drawView;
//- (void)setFramePointer;
//- (void)processPixelBuffer: (CVImageBufferRef)pixelBuffer;
//- (void)newFrame:(GLuint)frame;
- (void)newCameraTextureForDisplay:(GLuint)frame;

-(void) saveScreenToFile:(const char*)fname;
-(void) startMovieWriter:(const char*)fname;
-(void) writeScreenshotToMovie:(float)duration;
-(void) closeMovieWriter;

- (void) advertiseService:(NSString *)name withID:(NSString *)nsid atPort:(int)port;


#ifdef SANDWICH_SUPPORT
// sandwich update Delegate functions
- (void) rearTouchUpdate: (SandwichEventManager * ) sender;
- (void) pressureUpdate: (SandwichEventManager * ) sender;
#endif

- (void) setupNetConnects;

void Net_Advertise(const char* nsid, int port);
void Net_Find(const char* nsid);
void Stop_Net_Advertise(const char* nsid);
void Stop_Net_Find(const char* nsid);

@end

