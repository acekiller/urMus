//
//  EAGLView.m
//  urMus
//
//  Created by Georg Essl on 6/20/09.
//  Copyright Georg Essl 2009. All rights reserved. See LICENSE.txt for license details.
//

#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGLDrawable.h>

#import "EAGLView.h"
#import "urAPI.h"
#import "Texture2d.h"
#import "MachTimer.h"
#import "urSound.h"
#import "httpServer.h"
#include <arpa/inet.h>

#define SLEEPER

#ifdef SANDWICH_SUPPORT
static float pressure[4] = {0,0,0,0};
#endif

#define USE_DEPTH_BUFFER 0

extern int currentPage;
extern urAPI_Region_t* firstRegion[];
extern urAPI_Region_t* lastRegion[];

extern urAPI_Region_t* UIParent;

MachTimer* mytimer;

// A class extension to declare private methods
@interface EAGLView ()

@property (nonatomic, retain) EAGLContext *context;
@property (nonatomic, assign) NSTimer *animationTimer;

@property (nonatomic, retain, readwrite) NSNetService *ownEntry;
@property (nonatomic, assign, readwrite) BOOL showDisclosureIndicators;
@property (nonatomic, retain, readwrite) NSMutableArray *services;
@property (nonatomic, retain, readwrite) NSNetServiceBrowser *netServiceBrowser;
@property (nonatomic, retain, readwrite) NSNetService *currentResolve;
@property (nonatomic, retain, readwrite) NSTimer *timer;
@property (nonatomic, assign, readwrite) BOOL needsActivityIndicator;
@property (nonatomic, assign, readwrite) BOOL initialWaitOver;


- (BOOL) createFramebuffer;
- (void) destroyFramebuffer;

@end


@implementation EAGLView

@synthesize context;
@synthesize animationTimer;
@synthesize animationInterval;

@synthesize locationManager;

//@synthesize delegate = _delegate;
@synthesize ownEntry = _ownEntry;
@synthesize showDisclosureIndicators = _showDisclosureIndicators;
@synthesize currentResolve = _currentResolve;
@synthesize netServiceBrowser = _netServiceBrowser;
@synthesize services = _services;
@synthesize needsActivityIndicator = _needsActivityIndicator;
@dynamic timer;
@synthesize initialWaitOver = _initialWaitOver;
@synthesize netService;



// You must implement this method
+ (Class)layerClass {
    return [CAEAGLLayer class];
}

static const double ACCELEROMETER_RATE = 0.030;
static const int ACCELEROMETER_SCALE = 256;
static const int HEADING_SCALE = 256;
static const int LOCATION_SCALE = 256;

// Tracking All touches
NSMutableArray *ActiveTouches;              ///< Used to keep track of all current touches.

struct urDragTouch
{
	urAPI_Region_t* dragregion;
	int touch1;
	int touch2;
//	UITouch* touch1;
//	UITouch* touch2;
	float left;
	float top;
	float right;
	float bottom;
	float dragwidth;
	float dragheight;
	bool active;
	bool flagged;
	urDragTouch() { active = false; flagged = false; touch1 = -1; touch2 = -1;}
};

typedef struct urDragTouch urDragTouch_t;

#define MAX_DRAGS 10
urDragTouch_t dragtouches[MAX_DRAGS];

int FindDragRegion(urAPI_Region_t*region)
{
	for(int i=0; i< MAX_DRAGS; i++)
	{
		if(dragtouches[i].active && dragtouches[i].dragregion == region)
			return i;
	}
	return -1;
}

void AddDragRegion(int idx, int t)
{
	if(dragtouches[idx].touch1 == -1 && dragtouches[idx].touch2!=t)
		dragtouches[idx].touch1 = t;
	else if(dragtouches[idx].touch2 == -1 && dragtouches[idx].touch1!=t)
		dragtouches[idx].touch2 = t;
}

/*void AddDragRegion(int idx, UITouch* t)
{
	if(dragtouches[idx].touch1 == NULL && dragtouches[idx].touch2!=t)
		dragtouches[idx].touch1 = t;
	else if(dragtouches[idx].touch2 == NULL && dragtouches[idx].touch1!=t)
		dragtouches[idx].touch2 = t;
}*/

void ClearAllDragFlags()
{
	for(int i=0; i< MAX_DRAGS; i++)
	{
		dragtouches[i].flagged = false;
	}
}

int FindAvailableDragTouch()
{
	for(int i=0; i< MAX_DRAGS; i++)
		if(dragtouches[i].active == false)
			return i;
	
	int a=0;
	return -1;
}


UITouch* UITTrans[MAX_FINGERS];

void InitUITouchTranslation()
{
	for(int i=0; i< MAX_FINGERS; i++)
	{
		UITTrans[i] = NULL;
	}
}

int UITouch2UTID(UITouch* t)
{
	for(int i=0; i<MAX_FINGERS;i++)
		if( UITTrans[i] == t) return i;
	
	return -1;
}

UITouch* UTID2UITouch(int t)
{
	return UITTrans[t];
}

int AddUITouch(UITouch* t)
{
	bool found = false;
	int n = -1;
	for(int i=0; i< MAX_FINGERS; i++)
	{
		if(UITTrans[i] == t) found = true;
		if(n == -1 && UITTrans[i] == NULL) n = i;
	}
	
	if(found == false && n != -1)
		UITTrans[n] = t;
	
	return n;
}

void RemoveUTID(int t)
{
	UITTrans[t] = NULL;
}

void RemoveUITouchUTID(UITouch* t)
{
	for(int i=0; i<MAX_FINGERS;i++)
		if( UITTrans[i] == t) UITTrans[i] = NULL;
}

int FindDoubleDragTouch(int t1, int t2)
{
	for(int i=0; i< MAX_DRAGS; i++)
		if(dragtouches[i].active && ((dragtouches[i].touch1 == t1 && dragtouches[i].touch2 == t2) || (dragtouches[i].touch1 == t2 && dragtouches[i].touch2 == t1)))
		{
			return i;
		}
	return -1;
}


/*int FindDoubleDragTouch(UITouch* t1, UITouch* t2)
{
	for(int i=0; i< MAX_DRAGS; i++)
		if(dragtouches[i].active && ((dragtouches[i].touch1 == t1 && dragtouches[i].touch2 == t2) || (dragtouches[i].touch1 == t2 && dragtouches[i].touch2 == t1)))
		{
			return i;
		}
	return -1;
}*/

int FindSingleDragTouch(int t)
{
	if(t>=0)
	{
		for(int i=0; i< MAX_DRAGS; i++)
			if((dragtouches[i].active && dragtouches[i].touch1 == t /* && dragtouches[i].touch2 == NULL*/) || (/*dragtouches[i].touch1 == NULL &&*/ dragtouches[i].touch2 == t))
			{
				return i;
			}
	}
	return -1;
}

/*
int FindSingleDragTouch(UITouch* t)
{
	for(int i=0; i< MAX_DRAGS; i++)
		if((dragtouches[i].active && dragtouches[i].touch1 == t) || (dragtouches[i].touch2 == t))
		{
			return i;
		}
	return -1;
}*/

float cursorpositionx[MAX_FINGERS];
float cursorpositiony[MAX_FINGERS];

float cursorscrollspeedx[MAX_FINGERS];
float cursorscrollspeedy[MAX_FINGERS];

// Arrays to pass multi-touch finger to enter/leave handling. This allows smart decisions for enter/leave based on all fingers being considered. Should never be more than 5 and is fixed to avoid problems if MAX_FINGERS should be set to less for some reason.
int argmoved[MAX_FINGERS];
float argcoordx[MAX_FINGERS];
float argcoordy[MAX_FINGERS];
float arg2coordx[MAX_FINGERS];
float arg2coordy[MAX_FINGERS];

// This is the texture to hold DPrint and lua error messages.
Texture2D       *errorStrTex = nil;

std::string errorstr = "";
bool newerror = true;

//#define LATE_LAUNCH
// Main drawing loop. This does everything but brew coffee.
extern lua_State *lua;

- (void)awakeFromNib
{
	// Hide top navigation bar
	[[UIApplication sharedApplication] setStatusBarHidden:YES animated:NO];
	// To notes here: First I also added this to info.plist to make it vanish faster, which just looks nicer.
	// More importantly there is a bug with the statusbar still intercepting when hidden.
	// For that purpose I enabled landscapemode in info.plist. This seems to remove the problem and has no negative side-effect I could find.
	// Now one can enter the touch area from both sides without problems. (gessl 11/9/09)
	
	// Setup accelerometer collection
    [UIAccelerometer sharedAccelerometer].delegate = self;
    [UIAccelerometer sharedAccelerometer].updateInterval = ACCELEROMETER_RATE;
	// Set up the ability to track multiple touches.
	[self setMultipleTouchEnabled:YES];
	self.multipleTouchEnabled = YES;

	float version = [[[UIDevice currentDevice] systemVersion] floatValue];
	
	if (version >= 4.0)
    {
		// setup the gyroscope collection
		motionManager = [[CMMotionManager alloc] init];
		motionManager.gyroUpdateInterval = 1.0/60.0;
		
		if (motionManager.gyroAvailable) {
			opQ = [[NSOperationQueue currentQueue] retain];
			CMGyroHandler gyroHandler = ^ (CMGyroData *gyroData, NSError *error) {
				CMRotationRate rotate = gyroData.rotationRate;
				// handle rotation-rate data here......
				float rate_x = rotate.x/7.0;//128.0;
				float rate_y = rotate.y/7.0;//128.0;
				float rate_z = rotate.z/7.0;//128.0;
				
	//			float heading_north = ([heading trueHeading]-180.0)/180.0;
				
				// lua API events
				callAllOnRotRate(rate_x, rate_y, rate_z);
				// UrSound pipeline
				callAllGyroSources(rate_x, rate_y, rate_z);
				
			};
			[motionManager startGyroUpdatesToQueue:[NSOperationQueue currentQueue]
									   withHandler: gyroHandler];
			
		} else {
	//        NSLog(@"No gyroscope on device.");
			[motionManager release];
		}
    }
	
	// setup the location manager
	self.locationManager = [[[CLLocationManager alloc] init] autorelease];
	
	// check if the hardware has a compass
	if (locationManager.headingAvailable == NO) {
		// No compass is available. This application cannot function without a compass, 
        // so a dialog will be displayed and no magnetic data will be measured.
        self.locationManager = nil;
		// Disable compass flowboxes in this case. TODO
	} else {
		// location service configuration
		locationManager.distanceFilter = kCLDistanceFilterNone; 
		locationManager.desiredAccuracy = kCLLocationAccuracyBest;
		// start the GPS
		[locationManager startUpdatingLocation];

        // heading service configuration
        locationManager.headingFilter = kCLHeadingFilterNone;
        
        // setup delegate callbacks
        locationManager.delegate = self;
        
        // start the compass
        [locationManager startUpdatingHeading];
		
    }
	
	// Initiate the camera initiation sequence. <-- Whoa.
	captureManager = [[CaptureSessionManager alloc] init];
	captureManager.delegate = self;
	[captureManager addVideoInput];
	[captureManager addVideoDataOutput];
	[captureManager autoWhiteBalanceAndExposure:0];
	//[captureManager addVideoPreviewLayer];
	[captureManager.captureSession startRunning];

	//Create and advertise networking and discover others
//	[self setup];
	
	mytimer = new MachTimer();
	mytimer->start();
	
#ifdef LATE_LAUNCH
	NSString *resourcePath = [[NSBundle mainBundle] resourcePath];
	NSString *filePath = [resourcePath stringByAppendingPathComponent:@"urMus.lua"];
	NSArray *paths;
	paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentPath;
	if ([paths count] > 0)
		documentPath = [paths objectAtIndex:0];
	
	// start off http server
	http_start([resourcePath UTF8String],
			   [documentPath UTF8String]);
	
	const char* filestr = [filePath UTF8String];
	
	if(luaL_dofile(lua, filestr)!=0)
	{
		const char* error = lua_tostring(lua, -1);
		errorstr = error; // DPrinting errors for now
		newerror = true;
	}
#endif
}

#define BYTES_PER_PIXEL 4

// Where the magic happens as far as image processing is concerned
- (void)processPixelBuffer: (CVImageBufferRef)pixelBuffer {
	
	CVPixelBufferLockBaseAddress( pixelBuffer, 0 );
	
	int bufferHeight = CVPixelBufferGetHeight(pixelBuffer);
	int bufferWidth = CVPixelBufferGetWidth(pixelBuffer);
	int bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
	unsigned char *rowBase = (unsigned char *)CVPixelBufferGetBaseAddress(pixelBuffer);
	
	
	//	CGContextRef                    context;
	//	CGColorSpaceRef	colorSpace;
	//	CGAffineTransform               transform;
	//	colorSpace = CGColorSpaceCreateDeviceRGB();
	//	context = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pixelBuffer), bufferWidth, bufferHeight, 8, 4 * bufferWidth, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	//	CGColorSpaceRelease(colorSpace);
	//	CGContextClearRect(context, CGRectMake(0, 0, bufferWidth, bufferHeight));
	//	//	CGContextTranslateCTM(context, 0, height - imageSize.height);
	//	
	//	if(!CGAffineTransformIsIdentity(transform))
	//		CGContextConcatCTM(context, transform);
	//	//	CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(image), CGImageGetHeight(image)), image);
	//	//Convert "RRRRRRRRRGGGGGGGGBBBBBBBBAAAAAAAA" to "RRRRRGGGGGGBBBBB"
	//	//	if(pixelFormat == kTexture2DPixelFormat_RGB565) {
	//	//		tempData = malloc(height * width * 2);
	//	//		inPixel32 = (unsigned int*)data;
	//	//		outPixel16 = (unsigned short*)tempData;
	//	//		for(i = 0; i < width * height; ++i, ++inPixel32)
	//	//			*outPixel16++ = ((((*inPixel32 >> 0) & 0xFF) >> 3) << 11) | ((((*inPixel32 >> 8) & 0xFF) >> 2) << 5) | ((((*inPixel32 >> 16) & 0xFF) >> 3) << 0);
	//	//		free(data);
	//	//		data = tempData;
	//	//		
	//	//	}
	
	
	//TODO: Get the camera data in an OpenGL texture
	// Delete the current texture if it exists
	if (_cameraTexture) {
		glDeleteTextures(1, &_cameraTexture);
	}
	
	// Create a new texture
	GLint	saveName;
	glGenTextures(1, &_cameraTexture);
	glGetIntegerv(GL_TEXTURE_BINDING_2D, &saveName);
	glBindTexture(GL_TEXTURE_2D, _cameraTexture);
	
	// Set appropriate parameters for when the texture is resized
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	
	// Put the image directly into the texture
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, bufferWidth, bufferHeight, 0, GL_BGRA, GL_UNSIGNED_BYTE, CVPixelBufferGetBaseAddress(pixelBuffer));
	glBindTexture(GL_TEXTURE_2D, saveName);
	//glBindTexture(GL_TEXTURE_2D, _cameraTexture);
	
	// Draw it to the screen
	
	//[self newCameraTextureForDisplay:_cameraTexture];
	
	//CGContextRelease(context);
	//	free(data);
	
	/////////////////
	
	// Color initializations
	int64_t redTotal = 0;
	int64_t greenTotal = 0;
	int64_t blueTotal = 0;
	double totalTotal = 0;
	
	// Mid-level vision initializations
	int gradientX = 0;
	int gradientY = 0;
	double edginess = 0;
	
	// We don't look at every single pixel. Doing so would cause unneccesary load on the
	//	system for such basic features. This MUST be a factor of both the bufferHeight
	//	and bufferWidth.
	int downSampleFactor = 8;
	
	// Parse the image from left to right, bottom to top.
	for( int row = 0; row < bufferHeight; row += downSampleFactor ) {
		for( int column = 0; column < bufferWidth; column += downSampleFactor ) {
			
			unsigned char *pixel = rowBase + (row * bytesPerRow) + (column * BYTES_PER_PIXEL);
			
			// Reassignment is done here both to cast the unsigned char into the 8-bit integer
			//	as well as to remain compatible with helper functions above and to keep original
			//	memory buffer in tact.
			uint8_t pixelColor[3];
			for (int j = 0; j < 3; j++)
				pixelColor[j] = (uint8_t)pixel[j];
			
			//pixelColor now contains the BGR values of the current pixel
			
			blueTotal += pixelColor[0];
			greenTotal += pixelColor[1];
			redTotal += pixelColor[2];
			
			
			// Ensure we are not at the boundaries of the image so we can use the Roberts edge detector
			if (row < (bufferHeight-2*downSampleFactor) && column < (bufferWidth-2*downSampleFactor)) {
				
				// Access the other pixels in the neighborhood to calculate the gradient
				unsigned char *pixel9 = rowBase + ((row+downSampleFactor) * bytesPerRow) + ((column+downSampleFactor) * BYTES_PER_PIXEL);
				unsigned char *pixel8 = rowBase + ((row+downSampleFactor) * bytesPerRow) + (column * BYTES_PER_PIXEL);
				unsigned char *pixel6 = rowBase + (row * bytesPerRow) + ((column+downSampleFactor) * BYTES_PER_PIXEL);
				
				//Average of pixel 9 minus the average of the current pixel
				gradientX = (((uint8_t)pixel9[0]+(uint8_t)pixel9[1]+(uint8_t)pixel9[2])/3) - ((pixelColor[0]+pixelColor[1]+pixelColor[2])/3);
				gradientY = (((uint8_t)pixel8[0]+(uint8_t)pixel8[1]+(uint8_t)pixel8[2])/3) - (((uint8_t)pixel6[0]+(uint8_t)pixel6[1]+(uint8_t)pixel6[2])/3);
				edginess += pow(gradientX/255.0,2) + pow(gradientY/255.0,2);
			}
			
			
		}
		
	}
	
	// Normalize the sums into the 0 to 255 range 
	blueTotal = blueTotal/((bufferWidth/downSampleFactor)*(bufferHeight/downSampleFactor));
	greenTotal = greenTotal/((bufferWidth/downSampleFactor)*(bufferHeight/downSampleFactor));
	redTotal = redTotal/((bufferWidth/downSampleFactor)*(bufferHeight/downSampleFactor));
	
	totalTotal = ((double)blueTotal+(double)greenTotal+(double)redTotal)/3;
	
	// Normalize the edginess between 0 and 1
	edginess = log10(edginess)/log10(((bufferWidth/downSampleFactor)-1)*((bufferHeight/downSampleFactor)-1));
	
	// and then the 0 to 1 range
	callAllCameraSources(totalTotal/255.0,blueTotal/255.0,greenTotal/255.0,redTotal/255.0, edginess);
	
	printf("The new red value is %f\n",redTotal/255.);
	
	CVPixelBufferUnlockBaseAddress( pixelBuffer, 0 );
}

- (void)newCameraTextureForDisplay:(GLuint)texture {
	
	_cameraTexture = texture;
	//TODO: Something with this texture
}


- (void)accelerometer:(UIAccelerometer *)accelerometer didAccelerate:(UIAcceleration *)acceleration
{
	// This feeds the lua API events
	callAllOnAccelerate(acceleration.x, acceleration.y, acceleration.z);

	// We call the UrSound pipeline second so that the lua engine can actually change it based on acceleration data before anything happens.
	callAllAccelerateSources(acceleration.x, acceleration.y, acceleration.z);
}

// This delegate method is invoked when the location manager has heading data.
- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)heading {

	float heading_x = heading.x/128.0;
	float heading_y = heading.y/128.0;
	float heading_z = heading.z/128.0;
	
	float heading_north = ([heading trueHeading]-180.0)/180.0;
	
	// lua API events
	callAllOnHeading(heading_x, heading_y, heading_z, heading_north);
	// UrSound pipeline
	callAllCompassSources(heading_x, heading_y, heading_z, heading_north);
}

- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation {
	CLLocationDegrees  latitude = newLocation.coordinate.latitude;
	CLLocationDegrees longitude = newLocation.coordinate.longitude;
	
	float loc_latitude = latitude/90.0; // Normalize!
	float loc_longitude = longitude/180.0; // Normalize!
	
	// lua API events
	callAllOnLocation(loc_latitude, loc_longitude);
	// UrSound pipeline
	callAllLocationSources(loc_latitude, loc_longitude);
}

// This delegate method is invoked when the location managed encounters an error condition.
- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    if ([error code] == kCLErrorDenied) {
        // This error indicates that the user has denied the application's request to use location services.
        [manager stopUpdatingHeading];
    } else if ([error code] == kCLErrorHeadingFailure) {
        // This error indicates that the heading could not be determined, most likely because of strong magnetic interference.
    }
}

static EAGLSharegroup* theSharegroup = nil;

- (EAGLContext*)createContext
{
    EAGLContext* context = nil;
	
    if (theSharegroup)
    {
        context = [[EAGLContext alloc] 
				   initWithAPI:kEAGLRenderingAPIOpenGLES1
				   sharegroup:theSharegroup];
    }
    else
    {
        context = [[EAGLContext alloc]
				   initWithAPI:kEAGLRenderingAPIOpenGLES1];
        theSharegroup = context.sharegroup;
    }
	
    return context;
}


//The GL view is stored in the nib file. When it's unarchived it's sent -initWithCoder:
- (id)initWithCoder:(NSCoder*)coder {
    
    if ((self = [super initWithCoder:coder])) {
        // Get the layer
        CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;
        
        eaglLayer.opaque = YES;
        eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                        [NSNumber numberWithBool:YES], kEAGLDrawablePropertyRetainedBacking, kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat, nil];
        
		context = [self createContext];
		//       context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1];
        
        if (!context || ![EAGLContext setCurrentContext:context]) {
            [self release];
            return nil;
        }
        
        animationInterval = 1.0 / 60.0; // We look for 60 FPS

    }
	
	// Set up the ability to track multiple touches.
	[self setMultipleTouchEnabled:YES];
	self.multipleTouchEnabled = YES;

	return self;
}

// Hard-wired screen dimension constants. This will soon be system-dependent variable!
int SCREEN_WIDTH = 320;
int SCREEN_HEIGHT = 480;
int HALF_SCREEN_WIDTH = 160;
int HALF_SCREEN_HEIGHT = 240;
//#define SCREEN_WIDTH 320
//#define SCREEN_HEIGHT 480

// Enables/Disables that error and DPrint texture is rendered. Should always be on really.
#define RENDERERRORSTRTEXTUREFONT
// Enables/Disables debug output for multi-touch debugging. Should be always off now.
#undef DEBUG_TOUCH

// Various texture font strongs
NSString *textlabelstr = @"";
NSString *fontname = @"";
NSString *texturepathstr; // = @"Ship.png";

// Below is modeled after GLPaint

#define kBrushOpacity		(1.0 / 3.0)
#define kBrushPixelStep		3
#define kBrushScale			2
#define kLuminosity			0.75
#define kSaturation			1.0

static Texture2D* brushtexture = NULL;
static float brushsize = 1;

// 2D Painting functionality

// Brush handling

void SetBrushTexture(Texture2D * texture)
{
	brushtexture = texture;
	brushsize = texture.pixelsWide;
}

void SetBrushSize(float size)
{
	brushsize = size;
}

void ClearBrushTexture()
{
	brushtexture = NULL;
	brushsize = 1;
}

float BrushSize()
{
	return brushsize;
}

void SetupBrush()
{
	if(brushtexture != NULL)
	{
		glBindTexture(GL_TEXTURE_2D, brushtexture.name);
		glDisable(GL_DITHER);
		glEnable(GL_TEXTURE_2D);
		glEnable(GL_BLEND);
//		glDisable(GL_BLEND);
		// Make the current material colour track the current color
//		glEnable( GL_COLOR_MATERIAL );
		// Multiply the texture colour by the material colour.
//		glTexEnvf( GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE );
/*		switch(t->texture->blendmode)
		{
			case BLEND_DISABLED:
				glDisable(GL_BLEND);
				break;
			case BLEND_BLEND:
				glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
				break;
			case BLEND_ALPHAKEY:
				// NYI
				glAlphaFunc(GL_GEQUAL, 0.5f); // UR! This may be different
				glEnable(GL_ALPHA_TEST);
				break;
			case BLEND_ADD:
				glBlendFunc(GL_ONE, GL_ONE);
				break;
			case BLEND_MOD:
				glBlendFunc(GL_DST_COLOR, GL_ZERO);
				break;
			case BLEND_SUB: // Experimental blend category. Can be changed wildly NYI marking this for revision.
				glBlendFunc(GL_ONE_MINUS_DST_COLOR, GL_ZERO);
				break;
		}*/
		glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
//		glBlendFunc(GL_SRC_ALPHA, GL_ONE);
		glEnable(GL_POINT_SPRITE_OES);
		glTexEnvf(GL_POINT_SPRITE_OES, GL_COORD_REPLACE_OES, GL_TRUE);
	}	
	else
	{
		glDisable(GL_TEXTURE_2D);
		glDisable(GL_BLEND);
	}
	glPointSize(brushsize);
}

GLuint textureFrameBuffer=-1;

void CreateFrameBuffer()
{
	// create framebuffer
	glGenFramebuffersOES(1, &textureFrameBuffer);
}

// Render point drawing into a texture

void drawPointToTexture(urAPI_Texture_t *texture, float x, float y)
{
	Texture2D *bgtexture = texture->backgroundTex;
	y = texture->backgroundTex->_height - y;

	// allocate frame buffer
	if(textureFrameBuffer == -1)
		CreateFrameBuffer();
	// bind frame buffer
	glBindFramebufferOES(GL_FRAMEBUFFER_OES, textureFrameBuffer);
	
	// attach renderbuffer
	glFramebufferTexture2DOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_TEXTURE_2D, bgtexture.name, 0);
	
	SetupBrush();
	
	glDisableClientState(GL_COLOR_ARRAY);
	glColor4ub(texture->texturebrushcolor[0], texture->texturebrushcolor[1], texture->texturebrushcolor[2], texture->texturebrushcolor[3]);		

	static GLfloat		vertexBuffer[2];
	
	vertexBuffer[0] = (int)x;
	vertexBuffer[1] = (int)y;
	
	//Render the vertex array
	glVertexPointer(2, GL_FLOAT, 0, vertexBuffer);
	glDrawArrays(GL_POINTS, 0, 1);

	// unbind frame buffer
	glBindFramebufferOES(GL_FRAMEBUFFER_OES, 0);
}

int prepareBrushedLine(float startx, float starty, float endx, float endy, int vertexCount, int vertexMax, GLfloat* vertexBuffer)
{
	NSUInteger	count, i;

	//Add points to the buffer so there are drawing points every X pixels
	count = MAX(ceilf(sqrtf((endx - startx) * (endx - startx) + (endy - starty) * (endy - starty)) / kBrushPixelStep), 1);
	for(i = 0; i < count; ++i) {
		if(vertexCount == vertexMax) {
			vertexMax = 2 * vertexMax;
			vertexBuffer = (GLfloat*)realloc(vertexBuffer, vertexMax * 2 * sizeof(GLfloat));
		}
		
		vertexBuffer[2 * vertexCount + 0] = startx + (endx - startx) * ((GLfloat)i / (GLfloat)count);
		vertexBuffer[2 * vertexCount + 1] = starty + (endy - starty) * ((GLfloat)i / (GLfloat)count);
		vertexCount += 1;
	}
	return vertexCount;
}

// Render a quadrangle to a texture
void drawQuadToTexture(urAPI_Texture_t *texture, float x1, float y1, float x2, float y2, float x3, float y3, float x4, float y4)
{
	Texture2D *bgtexture = texture->backgroundTex;
	y1 = texture->backgroundTex->_height - y1;
	y2 = texture->backgroundTex->_height - y2;
	y3 = texture->backgroundTex->_height - y3;
	y4 = texture->backgroundTex->_height - y4;
	
	// allocate frame buffer
	if(textureFrameBuffer == -1)
		CreateFrameBuffer();
	// bind frame buffer
	glBindFramebufferOES(GL_FRAMEBUFFER_OES, textureFrameBuffer);
	
	// attach renderbuffer
	glFramebufferTexture2DOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_TEXTURE_2D, bgtexture.name, 0);
	
	SetupBrush();
	
	glEnable(GL_LINE_SMOOTH);
	glDisableClientState(GL_COLOR_ARRAY);
	glColor4ub(texture->texturebrushcolor[0], texture->texturebrushcolor[1], texture->texturebrushcolor[2], texture->texturebrushcolor[3]);		

	if(brushtexture==NULL)
	{
		static GLfloat		vertexBuffer[8];
		
		vertexBuffer[0] = x1;
		vertexBuffer[1] = y1;
		vertexBuffer[2] = x2;
		vertexBuffer[3] = y2;
		vertexBuffer[4] = x3;
		vertexBuffer[5] = y3;
		vertexBuffer[6] = x4;
		vertexBuffer[7] = y4;
		
		glLineWidth(brushsize);
		//Render the vertex array
		glVertexPointer(2, GL_FLOAT, 0, vertexBuffer);
		if(texture->fill)
			glDrawArrays(GL_TRIANGLE_FAN,0,4);
		else
			glDrawArrays(GL_LINE_LOOP, 0, 4);
	}
	else
	{
		
		static GLfloat*		vertexBuffer = NULL;
		static NSUInteger	vertexMax = sqrt(SCREEN_HEIGHT*SCREEN_HEIGHT+SCREEN_WIDTH*SCREEN_WIDTH); //577; // Sqrt(480^2+320^2)
		NSUInteger			vertexCount = 0,
		count,
		i;
		
		//Allocate vertex array buffer
		if(vertexBuffer == NULL)
			vertexBuffer = (GLfloat*)malloc(vertexMax * 2 * sizeof(GLfloat));
	
		vertexCount = prepareBrushedLine(x1,y1,x2,y2,vertexCount,vertexMax,vertexBuffer);
		vertexCount = prepareBrushedLine(x2,y2,x3,y3,vertexCount,vertexMax,vertexBuffer);
		vertexCount = prepareBrushedLine(x3,y3,x4,y4,vertexCount,vertexMax,vertexBuffer);
		vertexCount = prepareBrushedLine(x4,y4,x1,y1,vertexCount,vertexMax,vertexBuffer);
		
		//Render the vertex array
		glVertexPointer(2, GL_FLOAT, 0, vertexBuffer);
		glDrawArrays(GL_POINTS, 0, vertexCount);
	}
	
	// unbind frame buffer
	glBindFramebufferOES(GL_FRAMEBUFFER_OES, 0);
}

#define PI 3.1415926536

// Render an ellipse to a texture
void drawEllipseToTexture(urAPI_Texture_t *texture, float x, float y, float w, float h)
{
	Texture2D *bgtexture = texture->backgroundTex;
	y = texture->backgroundTex->_height - y;
	
	// allocate frame buffer
	if(textureFrameBuffer == -1)
		CreateFrameBuffer();
	// bind frame buffer
	glBindFramebufferOES(GL_FRAMEBUFFER_OES, textureFrameBuffer);
	
	// attach renderbuffer
	glFramebufferTexture2DOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_TEXTURE_2D, bgtexture.name, 0);
		
	SetupBrush();
	
	glEnable(GL_LINE_SMOOTH);
	glDisableClientState(GL_COLOR_ARRAY);
	glColor4ub(texture->texturebrushcolor[0], texture->texturebrushcolor[1], texture->texturebrushcolor[2], texture->texturebrushcolor[3]);		

	if(brushtexture==NULL)
	{
		GLfloat vertices[720];
	
		for (int i = 0; i < 720; i += 2) {
			// x value
			vertices[i]   = x+w*cos(2.0*PI*i/720.0);
			// y value
			vertices[i+1] = y+h*sin(2.0*PI*i/720.0);
		}
		glLineWidth(brushsize);
		//Render the vertex array
		glVertexPointer(2, GL_FLOAT, 0, vertices);
		if(texture->fill)
			glDrawArrays(GL_TRIANGLE_FAN,0,360);
		else
			glDrawArrays(GL_LINE_LOOP, 0, 360);
	}
	else
	{
		
		static GLfloat*		vertexBuffer = NULL;
		static NSUInteger	vertexMax = sqrt(SCREEN_HEIGHT*SCREEN_HEIGHT+SCREEN_WIDTH*SCREEN_WIDTH); //577; // Sqrt(480^2+320^2)
		NSUInteger			i;
		
		GLfloat vertices[720];
		
		for (int i = 0; i < 720; i += 2) {
			// x value
			vertices[i]   = x+w*cos(2.0*PI*i/360.0);
			// y value
			vertices[i+1] = y+h*sin(2.0*PI*i/360.0);
		}
		
		//Render the vertex array
		glVertexPointer(2, GL_FLOAT, 0, vertices);
		//		glDrawArrays(GL_LINES, 0, vertexCount);
		glDrawArrays(GL_POINTS, 0, 360);
	}
	
	// unbind frame buffer
	glBindFramebufferOES(GL_FRAMEBUFFER_OES, 0);
	
}

// Render line drawing to a texture

void drawLineToTexture(urAPI_Texture_t *texture, float startx, float starty, float endx, float endy)
{
	Texture2D *bgtexture = texture->backgroundTex;
	
	starty = texture->backgroundTex->_height - starty;
	endy = texture->backgroundTex->_height - endy;
	// allocate frame buffer
	if(textureFrameBuffer == -1)
		CreateFrameBuffer();
	// bind frame buffer
	glBindFramebufferOES(GL_FRAMEBUFFER_OES, textureFrameBuffer);
	
	// attach renderbuffer
	glFramebufferTexture2DOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_TEXTURE_2D, bgtexture.name, 0);
	
	SetupBrush();

//	if(bgtexture==NULL)
	if(brushtexture==NULL)
	{
		static GLfloat		vertexBuffer[4];
		
		vertexBuffer[0] = startx;
		vertexBuffer[1] = starty;
		vertexBuffer[2] = endx;
		vertexBuffer[3] = endy;

		glEnable(GL_LINE_SMOOTH);
		glDisableClientState(GL_COLOR_ARRAY);
		glColor4ub(texture->texturebrushcolor[0], texture->texturebrushcolor[1], texture->texturebrushcolor[2], texture->texturebrushcolor[3]);		
		//		glColor4ub(0,0,255,30);
		glLineWidth(brushsize);
		//Render the vertex array
		glVertexPointer(2, GL_FLOAT, 0, vertexBuffer);
		glDrawArrays(GL_LINES, 0, 2);
	}
	else
	{

		static GLfloat*		vertexBuffer = NULL;
		static NSUInteger	vertexMax = sqrt(SCREEN_HEIGHT*SCREEN_HEIGHT+SCREEN_WIDTH*SCREEN_WIDTH); //577; // Sqrt(480^2+320^2)
		NSUInteger			vertexCount = 0,
		count,
		i;
		
		//Allocate vertex array buffer
		if(vertexBuffer == NULL)
			vertexBuffer = (GLfloat*)malloc(vertexMax * 2 * sizeof(GLfloat));
		
		//Add points to the buffer so there are drawing points every X pixels
		count = MAX(ceilf(sqrtf((endx - startx) * (endx - startx) + (endy - starty) * (endy - starty)) / kBrushPixelStep), 1);
		for(i = 0; i < count; ++i) {
			if(vertexCount == vertexMax) {
				vertexMax = 2 * vertexMax;
				vertexBuffer = (GLfloat*)realloc(vertexBuffer, vertexMax * 2 * sizeof(GLfloat));
			}
			
			vertexBuffer[2 * vertexCount + 0] = startx + (endx - startx) * ((GLfloat)i / (GLfloat)count);
			vertexBuffer[2 * vertexCount + 1] = starty + (endy - starty) * ((GLfloat)i / (GLfloat)count);
			vertexCount += 1;
		}
		
		glDisableClientState(GL_COLOR_ARRAY);
		glColor4ub(texture->texturebrushcolor[0], texture->texturebrushcolor[1], texture->texturebrushcolor[2], texture->texturebrushcolor[3]);		
		//Render the vertex array
		glVertexPointer(2, GL_FLOAT, 0, vertexBuffer);
		glDrawArrays(GL_POINTS, 0, vertexCount);
	}
	
	// unbind frame buffer
	glBindFramebufferOES(GL_FRAMEBUFFER_OES, 0);
}

// Clear a texture with a given RGB color

void clearTexture(Texture2D* texture, float r, float g, float b, float a)
{
	if(textureFrameBuffer == -1)
		CreateFrameBuffer();
	glBindFramebufferOES(GL_FRAMEBUFFER_OES, textureFrameBuffer);
	
	// attach renderbuffer
	glFramebufferTexture2DOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_TEXTURE_2D, texture.name, 0);
	
	glClearColor(r, g, b, a);
	glClear(GL_COLOR_BUFFER_BIT);
	// unbind frame buffer
	glBindFramebufferOES(GL_FRAMEBUFFER_OES, 0);
}

// Create a texture instance for a given region

Texture2D* createBlankTexture(float width, float height)
{
	CGSize size;
	size.width = width;
	size.height = height;

	return [[Texture2D alloc] initWithSize:size];
}

void instantiateTexture(urAPI_Region_t* t)
{
	texturepathstr = [[NSString alloc] initWithUTF8String:t->texture->texturepath];
//	NSString *filePath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:texturepathstr]; // Leak here, fix.
//	UIImage* textureimage = [UIImage imageNamed:texturepathstr];
	UIImage* textureimage = [UIImage imageWithContentsOfFile:texturepathstr];
	if(textureimage==NULL)
		textureimage = [UIImage imageNamed:texturepathstr];
	
	if(textureimage)
	{
		CGSize rectsize;
		rectsize.width = t->width;
		rectsize.height = t->height;
		t->texture->backgroundTex = [[Texture2D alloc] initWithImage:textureimage rectsize:rectsize];
		t->texture->width = [textureimage size].width;
		t->texture->height = [textureimage size].height;
	}
	[texturepathstr release];	
}

void instantiateBlankTexture(urAPI_Region_t* t)
{	
	t->texture->backgroundTex = createBlankTexture(t->width, t->height);
	t->texture->width = t->width;
	t->texture->height = t->height;
	clearTexture(t->texture->backgroundTex, t->texture->texturesolidcolor[0], t->texture->texturesolidcolor[1], t->texture->texturesolidcolor[2], t->texture->texturesolidcolor[3]);
}

void instantiateAllTextures(urAPI_Region_t* t)
{
	if(t->texture->texturepath != TEXTURE_SOLID)
	{
		instantiateTexture(t);
	}
	else {
		instantiateBlankTexture(t);
	}
}

// Convert line break modes to UILineBreakMode enums

UILineBreakMode tolinebreakmode(int wrap)
{
	switch(wrap)
	{
		case WRAP_WORD:
			return UILineBreakModeWordWrap;
		case WRAP_CHAR:
			return UILineBreakModeCharacterWrap;
		case WRAP_CLIP:
			return UILineBreakModeClip;
	}
	return UILineBreakModeWordWrap;
}

- (void)drawView {
  
  // eval http buffer
  eval_buffer_exec(lua);
  
	urs_PullVis(); // update vis data before we call events, this way we have a rate based pulling that is available in all events.
	// Clock ourselves.
	float elapsedtime = mytimer->elapsedSec();
	mytimer->start();
	callAllOnUpdate(elapsedtime); // Call lua APIs OnUpdates when we render a new region. We do this first so that stuff can still be drawn for this region.
	
	CGRect  bounds = [self bounds];
	
    // Replace the implementation of this method to do your own custom drawing
    
    GLfloat squareVertices[] = {
        -0.5f, -0.5f,
        0.5f,  -0.5f,
        -0.5f,  0.5f,
        0.5f,   0.5f,
    };
    GLubyte squareColors[] = {
        255, 255,   0, 255,
        0,   255, 255, 255,
        0,     0,   0,   0,
        255,   0, 255, 255,
    };
	
	GLfloat shadowColors[] = {
		0.0, 0.0, 0.0, 50.0
	};
    
    [EAGLContext setCurrentContext:context];
    
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glBindFramebufferOES(GL_FRAMEBUFFER_OES, viewFramebuffer);
    glViewport(0, 0, backingWidth, backingHeight);
	
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
	glOrthof(0.0f, SCREEN_WIDTH, 0.0f, SCREEN_HEIGHT, -1.0f, 1.0f);
    glMatrixMode(GL_MODELVIEW);
    glRotatef(0.0f, 0.0f, 0.0f, 1.0f);
    
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f); // Background color
    glClear(GL_COLOR_BUFFER_BIT);
	
	// Render all (visible and unclipped) regions on a given page.
	
	for(urAPI_Region_t* t=firstRegion[currentPage]; t != nil; t=t->next)
	{
		if(t->isClipping)
		{
			glScissor(t->clipleft,t->clipbottom,t->clipwidth,t->clipheight);
			glEnable(GL_SCISSOR_TEST);
		}
		else
		{
			glDisable(GL_SCISSOR_TEST);
		}
		
		if(t->isVisible)
		{
			squareVertices[0] = t->left;
			squareVertices[1] = t->bottom;
			squareVertices[2] = t->left;
			squareVertices[3] = t->bottom+t->height;
			squareVertices[4] = t->left+t->width;
			squareVertices[5] = t->bottom;
			squareVertices[6] = t->left+t->width;
			squareVertices[7] = t->bottom+t->height;
			
			glVertexPointer(2, GL_FLOAT, 0, squareVertices);
			glEnableClientState(GL_VERTEX_ARRAY);
			glEnableClientState(GL_TEXTURE_COORD_ARRAY);
			glEnableClientState(GL_VERTEX_ARRAY);
			float alpha = t->alpha;
			if(t->texture!=NULL)
			{
/*				if(t->texture->texturepath == TEXTURE_SOLID)
				{
					squareColors[0] = t->texture->texturesolidcolor[0];
					squareColors[1] = t->texture->texturesolidcolor[1];
					squareColors[2] = t->texture->texturesolidcolor[2];
					squareColors[3] = t->texture->texturesolidcolor[3]*alpha;
					
					squareColors[4] = t->texture->texturesolidcolor[0];
					squareColors[5] = t->texture->texturesolidcolor[1];
					squareColors[6] = t->texture->texturesolidcolor[2];
					squareColors[7] = t->texture->texturesolidcolor[3]*alpha;
					
					squareColors[8] = t->texture->texturesolidcolor[0];
					squareColors[9] = t->texture->texturesolidcolor[1];
					squareColors[10] = t->texture->texturesolidcolor[2];
					squareColors[11] = t->texture->texturesolidcolor[3]*alpha;
					
					squareColors[12] = t->texture->texturesolidcolor[0];
					squareColors[13] = t->texture->texturesolidcolor[1];
					squareColors[14] = t->texture->texturesolidcolor[2];
					squareColors[15] = t->texture->texturesolidcolor[3]*alpha;
				}
				else
				{*/
					squareColors[0] = t->texture->gradientBL[0];
					squareColors[1] = t->texture->gradientBL[1];
					squareColors[2] = t->texture->gradientBL[2];
					squareColors[3] = t->texture->gradientBL[3]*alpha;
					
					squareColors[4] = t->texture->gradientBR[0];
					squareColors[5] = t->texture->gradientBR[1];
					squareColors[6] = t->texture->gradientBR[2];
					squareColors[7] = t->texture->gradientBR[3]*alpha;
					
					squareColors[8] = t->texture->gradientUL[0];
					squareColors[9] = t->texture->gradientUL[1];
					squareColors[10] = t->texture->gradientUL[2];
					squareColors[11] = t->texture->gradientUL[3]*alpha;
					
					squareColors[12] = t->texture->gradientUR[0];
					squareColors[13] = t->texture->gradientUR[1];
					squareColors[14] = t->texture->gradientUR[2];
					squareColors[15] = t->texture->gradientUR[3]*alpha;
//				}
				glColorPointer(4, GL_UNSIGNED_BYTE, 0, squareColors);
				glEnableClientState(GL_COLOR_ARRAY);
				
				if(t->texture->backgroundTex == nil && t->texture->texturepath != TEXTURE_SOLID)
				{
					instantiateTexture(t);
				}
				
				switch(t->texture->blendmode)
				{
					case BLEND_DISABLED:
						glDisable(GL_BLEND);
						break;
					case BLEND_BLEND:
						glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
						break;
					case BLEND_ALPHAKEY:
						// NYI
						glAlphaFunc(GL_GEQUAL, 0.5f); // UR! This may be different
						glEnable(GL_ALPHA_TEST);
						break;
					case BLEND_ADD:
						glBlendFunc(GL_ONE, GL_ONE);
						break;
					case BLEND_MOD:
						glBlendFunc(GL_DST_COLOR, GL_ZERO);
						break;
					case BLEND_SUB: // Experimental blend category. Can be changed wildly NYI marking this for revision.
						glBlendFunc(GL_ONE_MINUS_DST_COLOR, GL_ZERO);
						break;
				}

				if(t->texture->backgroundTex)
				{
					glEnable(GL_TEXTURE_2D);

					glEnableClientState(GL_TEXTURE_COORD_ARRAY);
					GLfloat  coordinates[] = {  t->texture->texcoords[0],          t->texture->texcoords[1],
						t->texture->texcoords[2],  t->texture->texcoords[3],
						t->texture->texcoords[4],              t->texture->texcoords[5],
					t->texture->texcoords[6],  t->texture->texcoords[7]  };

					glTexCoordPointer(2, GL_FLOAT, 0, coordinates);
					if(t->texture->usecamera)
					{
						CGRect rect = CGRectMake(t->left,t->bottom,t->width,t->height);
						GLfloat vertices[] = {  rect.origin.x,                                                  rect.origin.y,                                                  0.0,
							rect.origin.x + rect.size.width,                rect.origin.y,                                                  0.0,
							rect.origin.x,                                                  rect.origin.y + rect.size.height,               0.0,
							rect.origin.x + rect.size.width,                rect.origin.y + rect.size.height,               0.0 };
						
						glBindTexture(GL_TEXTURE_2D, _cameraTexture);
						glVertexPointer(3, GL_FLOAT, 0, vertices);
						//	glTexCoordPointer(2, GL_FLOAT, 0, coordinates);
						glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
					}
					else
					{
						[t->texture->backgroundTex drawInRect:CGRectMake(t->left,t->bottom,t->width,t->height)];
					}
					
					if(t->texture->isTiled)
					{
						glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
						glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);					
					}
					else {
						glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
						glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);					
					}
					
					glEnable(GL_BLEND);
					glDisable(GL_ALPHA_TEST);
				}
				else
				{
					glDisable(GL_TEXTURE_2D);
					glDisableClientState(GL_TEXTURE_COORD_ARRAY);
					glColorPointer(4, GL_UNSIGNED_BYTE, 0, squareColors);
					glEnableClientState(GL_COLOR_ARRAY);
					glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
					glEnable(GL_BLEND);
					glDisable(GL_ALPHA_TEST);
				}
				// switch it back to GL_ONE for other types of images, rather than text because Texture2D uses CG to load, which premultiplies alpha
				glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
			}
			else
			{
			}
			
			if(t->textlabel!=NULL)
			{
				// texturing will need these
				glEnableClientState(GL_TEXTURE_COORD_ARRAY);
				glEnableClientState(GL_VERTEX_ARRAY);
				glEnable(GL_TEXTURE_2D);
				
				if(t->textlabel->updatestring)
				{
					if(t->textlabel->textlabelTex)
						[t->textlabel->textlabelTex dealloc];
					UITextAlignment align = UITextAlignmentCenter;
					switch(t->textlabel->justifyh)
					{
						case JUSTIFYH_CENTER:
							align = UITextAlignmentCenter;
							break;
						case JUSTIFYH_LEFT:
							align = UITextAlignmentLeft;
							break;
						case JUSTIFYH_RIGHT:
							align = UITextAlignmentRight;
							break;
					}
					textlabelstr = [[NSString alloc] initWithUTF8String:t->textlabel->text]; // Leak here. Fix.
					fontname = [[NSString alloc] initWithUTF8String:t->textlabel->font];
					t->textlabel->updatestring = false;
					if(t->textlabel->drawshadow==false)
					{
						t->textlabel->textlabelTex = [[Texture2D alloc] initWithString:textlabelstr
																			  dimensions:CGSizeMake(t->width, t->height) alignment:align
																			  fontName:fontname fontSize:t->textlabel->textheight lineBreakMode:tolinebreakmode(t->textlabel->wrap)];
					}
					else
					{
						CGSize shadowoffset = CGSizeMake(t->textlabel->shadowoffset[0],t->textlabel->shadowoffset[1]);
						shadowColors[0] = t->textlabel->shadowcolor[0];
						shadowColors[1] = t->textlabel->shadowcolor[1];
						shadowColors[2] = t->textlabel->shadowcolor[2];
						shadowColors[3] = t->textlabel->shadowcolor[3];
						t->textlabel->textlabelTex = [[Texture2D alloc] initWithString:textlabelstr
																			  dimensions:CGSizeMake(t->width, t->height) alignment:align
																				fontName:fontname fontSize:t->textlabel->textheight lineBreakMode:tolinebreakmode(t->textlabel->wrap)
																			shadowOffset:CGSizeMake(t->textlabel->shadowoffset[0],t->textlabel->shadowoffset[1]) shadowBlur:t->textlabel->shadowblur shadowColor:t->textlabel->shadowcolor];
					}
					[fontname release];
					[textlabelstr release];
				}
				
				// text will need blending
				glEnable(GL_BLEND);
				
				// text from Texture2D uses A8 tex format, so needs GL_SRC_ALPHA
				glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
				for(int i=0;i<4;i++) // default regions are white
				{
					squareColors[4*i] = t->textlabel->textcolor[0];
					squareColors[4*i+1] = t->textlabel->textcolor[1];
					squareColors[4*i+2] = t->textlabel->textcolor[2];
					squareColors[4*i+3] = t->textlabel->textcolor[3]*t->alpha;
				}
				glColorPointer(4, GL_UNSIGNED_BYTE, 0, squareColors);
				glEnableClientState(GL_COLOR_ARRAY);
				
				int bottom = t->bottom;
				int fontheight = [t->textlabel->textlabelTex fontblockHeight];
				switch(t->textlabel->justifyv)
				{
					case JUSTIFYV_MIDDLE:
						bottom -= t->height/2-fontheight/2;
						break;
					case JUSTIFYV_TOP:
						bottom = bottom;
						break;
					case JUSTIFYV_BOTTOM:
						bottom -= t->height-fontheight; 
						break;
				}
				
				glPushMatrix();
				glTranslatef(t->left+t->width/2, bottom+t->height/2, 0);
				glRotatef(t->textlabel->rotation, 0.0f, 0.0f, 1.0f);
				[t->textlabel->textlabelTex drawAtPoint:CGPointMake(-t->width/2, -t->height/2) tile:true];
				glPopMatrix();
				
				// switch it back to GL_ONE for other types of images, rather than text because Texture2D uses CG to load, which premultiplies alpha
				glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
			}
		}
	}
	
	glDisable(GL_SCISSOR_TEST);
	
	glDisable(GL_TEXTURE_2D);
#ifdef RENDERERRORSTRTEXTUREFONT
	// texturing will need these
	glEnableClientState(GL_TEXTURE_COORD_ARRAY);
	glEnableClientState(GL_VERTEX_ARRAY);
	glEnable(GL_TEXTURE_2D);
	
	if (errorStrTex == nil)
	{
		newerror = false;
		errorStrTex = [[Texture2D alloc] initWithString:[[NSString alloc] initWithCString:errorstr.c_str()]
										 dimensions:CGSizeMake(SCREEN_WIDTH, 128) alignment:UITextAlignmentCenter
										   fontName:@"Helvetica" fontSize:14 lineBreakMode:UILineBreakModeWordWrap ];
	}
	else if(newerror)
	{
		[errorStrTex dealloc];
		newerror = false;
		errorStrTex = [[Texture2D alloc] initWithString:[[NSString alloc] initWithCString:errorstr.c_str()]
										 dimensions:CGSizeMake(SCREEN_WIDTH, 128) alignment:UITextAlignmentCenter
										   fontName:@"Helvetica" fontSize:14 lineBreakMode:UILineBreakModeWordWrap];
	}
	
	// text will need blending
	glEnable(GL_BLEND);
	
	// text from Texture2D uses A8 tex format, so needs GL_SRC_ALPHA
	glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	for(int i=0;i<16;i++) // default regions are white
		squareColors[i] = 200;
	glColorPointer(4, GL_UNSIGNED_BYTE, 0, squareColors);
	glEnableClientState(GL_COLOR_ARRAY);
	[errorStrTex drawAtPoint:CGPointMake(0.0,
									 bounds.size.height * 0.5f) tile:true];
	
	// switch it back to GL_ONE for other types of images, rather than text because Texture2D uses CG to load, which premultiplies alpha
	glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
	
#endif
	
	
	
    glBindRenderbufferOES(GL_RENDERBUFFER_OES, viewRenderbuffer);
    [context presentRenderbuffer:GL_RENDERBUFFER_OES];
}

- (void)layoutSubviews {
    [EAGLContext setCurrentContext:context];
    [self destroyFramebuffer];
    [self createFramebuffer];
    [self drawView];
}


- (BOOL)createFramebuffer {
	
	CGRect screendimensions = [[UIScreen mainScreen] bounds];
    
	SCREEN_WIDTH = screendimensions.size.width;
	SCREEN_HEIGHT = screendimensions.size.height;
	HALF_SCREEN_WIDTH = SCREEN_WIDTH/2;
	HALF_SCREEN_HEIGHT = SCREEN_HEIGHT/2;
	
	
    glGenFramebuffersOES(1, &viewFramebuffer);
    glGenRenderbuffersOES(1, &viewRenderbuffer);
    
    glBindFramebufferOES(GL_FRAMEBUFFER_OES, viewFramebuffer);
    glBindRenderbufferOES(GL_RENDERBUFFER_OES, viewRenderbuffer);
    [context renderbufferStorage:GL_RENDERBUFFER_OES fromDrawable:(CAEAGLLayer*)self.layer];
    glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_RENDERBUFFER_OES, viewRenderbuffer);
    
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &backingWidth);
    glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &backingHeight);
    
    if (USE_DEPTH_BUFFER) {
        glGenRenderbuffersOES(1, &depthRenderbuffer);
        glBindRenderbufferOES(GL_RENDERBUFFER_OES, depthRenderbuffer);
        glRenderbufferStorageOES(GL_RENDERBUFFER_OES, GL_DEPTH_COMPONENT16_OES, backingWidth, backingHeight);
        glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_DEPTH_ATTACHMENT_OES, GL_RENDERBUFFER_OES, depthRenderbuffer);
    }
    
    if(glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES) != GL_FRAMEBUFFER_COMPLETE_OES) {
        NSLog(@"failed to make complete framebuffer object %x", glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES));
        return NO;
    }
    
    return YES;
}


- (void)destroyFramebuffer {
    
    glDeleteFramebuffersOES(1, &viewFramebuffer);
    viewFramebuffer = 0;
    glDeleteRenderbuffersOES(1, &viewRenderbuffer);
    viewRenderbuffer = 0;
    
    if(depthRenderbuffer) {
        glDeleteRenderbuffersOES(1, &depthRenderbuffer);
        depthRenderbuffer = 0;
    }
}


- (void)startAnimation {
    self.animationTimer = [NSTimer scheduledTimerWithTimeInterval:animationInterval target:self selector:@selector(drawView) userInfo:nil repeats:YES];
//#define LATE_LAUNCH2
#ifdef LATE_LAUNCH2
	NSString *resourcePath = [[NSBundle mainBundle] resourcePath];
#ifndef SLEEPER
	NSString *filePath = [resourcePath stringByAppendingPathComponent:@"urMus.lua"];
#else
	NSString *filePath = [resourcePath stringByAppendingPathComponent:@"urSleeperLaunch.lua"];
#endif
	NSArray *paths;
	paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentPath;
	if ([paths count] > 0)
		documentPath = [paths objectAtIndex:0];
	
	// start off http server
#define HTTP_EDITING
#ifdef HTTP_EDITING
	http_start([resourcePath UTF8String],
			   [documentPath UTF8String]);
#endif
	
	const char* filestr = [filePath UTF8String];
	
	if(luaL_dofile(lua, filestr)!=0)
	{
		const char* error = lua_tostring(lua, -1);
		errorstr = [[NSString alloc] initWithCString:error ]; // DPrinting errors for now
		newerror = true;
	}
#endif	
	
}


- (void)stopAnimation {
    self.animationTimer = nil;
}


- (void)setAnimationTimer:(NSTimer *)newTimer {
    [animationTimer invalidate];
    animationTimer = newTimer;
}


- (void)setAnimationInterval:(NSTimeInterval)interval {
    
    animationInterval = interval;
    if (animationTimer) {
        [self stopAnimation];
        [self startAnimation];
    }
}


- (void)dealloc {
    
    [self stopAnimation];
    
    if ([EAGLContext currentContext] == context) {
        [EAGLContext setCurrentContext:nil];
    }

    // Shut down networking
	
	[self stopCurrentResolve];
	self.services = nil;
	[self.netServiceBrowser stop];
	self.netServiceBrowser = nil;
	[self.netService removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
	self.netService = nil;
	[_searchingForServicesString release];
	[_ownName release];
	[_ownEntry release];

    [ActiveTouches release];
    [context release];  
    [super dealloc];
}


#pragma mark -
#pragma mark === Touch handling  ===
#pragma mark

#define NR_FINGERS 2

CGFloat distanceBetweenPoints(CGPoint first, CGPoint second)
{
	CGFloat deltax = second.x-first.x;
	CGFloat deltay = second.y-first.y;
	return sqrt(deltax*deltax + deltay*deltay);
}

/*
int NumHitMatches(urAPI_Region_t* hitregion[], int max, int idx, int repeat)
{
	int count = 0;
	for(int i=0; i<max; i++)
		if(hitregion[idx] == hitregion[i])
			count++;

}
*/

// Platform independent stuff

urAPI_Region_t* hitregion[MAX_FINGERS];

void onTouchDownParse(int t, int numTaps, float posx, float posy)
{
	if(t>=0)
	{
		hitregion[t] = NULL;
		cursorpositionx[t] = posx;
		cursorpositiony[t] = posy;
		
		hitregion[t] = findRegionHit(posx, SCREEN_HEIGHT-posy);
		if(hitregion[t]!=nil)
		{
			float x = hitregion[t]->lastinputx;
			float y = hitregion[t]->lastinputy;
			// A double tap.
			if (numTaps == 2 && hitregion[t]->OnDoubleTap) 
			{
				callScript(hitregion[t]->OnDoubleTap, hitregion[t]);
				//					callScript(hitregion[t]->OnTouchUp, hitregion[t]);
			}
			else if (numTaps == 3 && false)
			{
				// Tripple Tap NYI
			}
			else if (numTaps == 1)
				callScriptWith2Args(hitregion[t]->OnTouchDown, hitregion[t],x,y);
			else {
				callScriptWith2Args(hitregion[t]->OnTouchDown, hitregion[t],x,y);
//				callScriptWith2Args(hitregion[t]->OnTouchUp, hitregion[t],x,y); // GESSL: Double Tap issue.
			}
		}
	}
}

int arg = 0;
void onTouchArgInit()
{
	arg = 0;
}

void onTouchMoveUpdate(int t, int t2, float oposx, float oposy, float posx, float posy)
{
	if(t2 >=0)
	{
		cursorscrollspeedx[t2] = posx - oposx;
		cursorscrollspeedy[t2] = posy - oposy;
		cursorpositionx[t2] = posx;
		cursorpositiony[t2] = posy;
		argmoved[arg] = t;
		argcoordx[arg] = posx;
		argcoordy[arg] = SCREEN_HEIGHT-posy;
		arg2coordx[arg] = oposx;
		arg2coordy[arg] = SCREEN_HEIGHT-oposy;
		arg++;
	}
}

void onTouchEnds(int numTaps, float oposx, float oposy, float posx, float posy)
{
	urAPI_Region_t* hitregion = findRegionHit(posx, SCREEN_HEIGHT-posy);
	if(hitregion /* && numTaps <= 1 */) // GESSL: Double tab issue
	{
		callScriptWith2Args(hitregion->OnTouchUp, hitregion,hitregion->lastinputx,hitregion->lastinputy);
		//		callAllOnLeaveRegions(posx, SCREEN_HEIGHT-posy); // GESSL: Double tab issue

	}
	else
	{
		argcoordx[arg] = posx;
		argcoordy[arg] = SCREEN_HEIGHT-posy;
		arg2coordx[arg] = oposx;
		arg2coordy[arg] = SCREEN_HEIGHT-oposy;
		arg++;
	}
}


void ClampRegion(urAPI_Region_t*region)
{
	if(region->left < 0) region->left = 0;
	if(region->bottom < 0) region->bottom = 0;
	if(region->width > SCREEN_WIDTH) region->width = SCREEN_WIDTH;
	if(region->height > SCREEN_HEIGHT) region->height = SCREEN_HEIGHT;
	if(region->left+region->width > SCREEN_WIDTH) region->left = SCREEN_WIDTH-region->width;
	if(region->bottom+region->height > SCREEN_HEIGHT) region->bottom = SCREEN_HEIGHT-region->height;
}


void onTouchDoubleDragUpdate(int t, int dragidx, float pos1x, float pos1y, float pos2x, float pos2y)
{
	if(t>=0)
	{
		float dx = cursorscrollspeedx[t];
		float dy = -(cursorscrollspeedy[t]);
		if( dx !=0 || dy != 0)
		{
			urAPI_Region_t* dragregion = dragtouches[dragidx].dragregion;
			dragregion->left += dx;
			dragregion->bottom += dy;
			float cursorpositionx2 = pos2x;
			float cursorpositiony2 = pos2y;
			if(dragregion->isResizable)
			{
				float deltanewwidth = fabs(cursorpositionx2-pos1x);
				float deltanewheight = fabs(cursorpositiony2-pos1y);
				dragregion->width = dragtouches[dragidx].dragwidth + deltanewwidth;
				dragregion->height = dragtouches[dragidx].dragheight + deltanewheight;
			}
			dragregion->right = dragregion->left + dragregion->width;
			dragregion->top = dragregion->bottom + dragregion->height;
			if(dragregion->isClamped) ClampRegion(dragregion);
			callScript(dragregion->OnSizeChanged, dragregion);
		}
	}
}

bool testDoubleDragStart(int t1, int t2)
{
	if(hitregion[t1] != NULL && hitregion[t1] == hitregion[t2] && hitregion[t1]->isMovable && hitregion[t1]->isResizable) // Pair of fingers on draggable region?
		return true;
	else
		return false;
}

void doTouchDoubleDragStart(int t1,int t2,int touch1, int touch2)
{
	if(t1>=0 && t2>=0)
	{
		hitregion[t1]->isDragged = true; // YAYA
		hitregion[t1]->isResized = true;
		int dragidx = FindAvailableDragTouch();
		dragtouches[dragidx].dragregion = hitregion[t1];
		dragtouches[dragidx].touch1 = touch1; //UITouch2UTID([[touches allObjects] objectAtIndex:t1]);
		dragtouches[dragidx].touch2 = touch2; //UITouch2UTID([[touches allObjects] objectAtIndex:t2]);
		dragtouches[dragidx].dragwidth = hitregion[t1]->width-fabs(cursorpositionx[t2]-cursorpositionx[t1]);
		dragtouches[dragidx].dragheight = hitregion[t1]->height-fabs(cursorpositiony[t2]-cursorpositiony[t1]);
		dragtouches[dragidx].active = true;
	}
}

bool testSingleDragStart(int t)
{
	if(hitregion[t]!=nil && hitregion[t]->isMovable)
		return true;
	else 
		return false;
}

bool getSingleDoubleTouchConversionID(int t)
{
	int dragidx = FindDragRegion(hitregion[t]);
	if(dragidx == -1)
		return -1;
	else 
		return dragtouches[dragidx].touch1;
}

void doTouchSingleDragStart(int t, int touch1, float pos1x, float pos1y, float pos2x, float pos2y)
{
	hitregion[t]->isDragged = true; // YAYA
	int dragidx = FindDragRegion(hitregion[t]);
	if(dragidx == -1)
	{
		dragidx = FindAvailableDragTouch();
		dragtouches[dragidx].dragregion = hitregion[t];
		dragtouches[dragidx].touch1 = touch1;
		dragtouches[dragidx].touch2 = -1;
		dragtouches[dragidx].active = true;
	}
	else
	{
		AddDragRegion(dragidx,touch1);
		if(dragtouches[dragidx].touch2 != -1)
		{
			dragtouches[dragidx].dragwidth = dragtouches[dragidx].dragregion->width-fabs(pos2x-pos1x);
			dragtouches[dragidx].dragheight = dragtouches[dragidx].dragregion->height-fabs(pos2y-pos1y);
		}
	}
}

void onTouchSingleDragUpdate(int t, int dragidx)
{
	if(t>=0 && dragidx>=0)
	{
		float dx = cursorscrollspeedx[t];
		float dy = -(cursorscrollspeedy[t]);
		if( dx !=0 || dy != 0)
		{
			urAPI_Region_t* dragregion = dragtouches[dragidx].dragregion;
			dragregion->left += dx;
			dragregion->bottom += dy;
			dragregion->right += dx;
			dragregion->top += dy;
		}
	}
}

void onTouchScrollUpdate(int t)
{
	urAPI_Region_t* scrollregion = findRegionXScrolled(cursorpositionx[t],SCREEN_HEIGHT-cursorpositiony[t],cursorscrollspeedx[t]);
	if(scrollregion != nil)
	{
		callScriptWith1Args(scrollregion->OnHorizontalScroll, scrollregion, cursorscrollspeedx[t]);
	}
	scrollregion = findRegionYScrolled(cursorpositionx[t],SCREEN_HEIGHT-cursorpositiony[t],-cursorscrollspeedy[t]);
	if(scrollregion != nil)
	{
		callScriptWith1Args(scrollregion->OnVerticalScroll, scrollregion, -cursorscrollspeedy[t]);
	}
	
	scrollregion = findRegionMoved(cursorpositionx[t],SCREEN_HEIGHT-cursorpositiony[t],cursorscrollspeedx[t],-cursorscrollspeedy[t]);
	
	if(scrollregion != nil)
	{
		callScriptWith5Args(scrollregion->OnMove, scrollregion, cursorpositionx[t]-scrollregion->left-cursorscrollspeedx[t],SCREEN_HEIGHT-cursorpositiony[t]-scrollregion->bottom+cursorscrollspeedy[t], cursorscrollspeedx[t], -cursorscrollspeedy[t],t+1);
	}
}

void onTouchDragEnd(int t,int touch, float posx, float posy)
{
	if(touch >=0 && t>=0)
	{
		
		cursorpositionx[t] = posx;
		cursorpositiony[t] = posy;

		int dragidx = FindSingleDragTouch(touch);
		
		if(dragidx != -1)
		{
			if(dragtouches[dragidx].touch1 == touch)
			{
				RemoveUTID(dragtouches[dragidx].touch1);
				dragtouches[dragidx].touch1 = -1;
			}
			if(dragtouches[dragidx].touch2 == touch)
			{
				RemoveUTID(dragtouches[dragidx].touch2);
				dragtouches[dragidx].touch2 = -1;
			}
			if(	dragtouches[dragidx].touch1 == -1 && dragtouches[dragidx].touch2 == -1)
			{
				dragtouches[dragidx].active = false;
				dragtouches[dragidx].dragregion->isDragged = false;
				callScript(dragtouches[dragidx].dragregion->OnDragStop, dragtouches[dragidx].dragregion);
			}
			else if(dragtouches[dragidx].touch2 != -1)
			{
				RemoveUTID(dragtouches[dragidx].touch1);
				dragtouches[dragidx].touch1 = dragtouches[dragidx].touch2;
				dragtouches[dragidx].touch2 = -1;
			}
			dragtouches[dragidx].dragregion->isResized = false;
		}
	}
}


// Handles the start of a touch
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    if (ActiveTouches == nil)
        ActiveTouches = [[NSMutableArray alloc] init];
    
    for (UITouch *touch in touches) {
        if (![ActiveTouches containsObject:touch])
            [ActiveTouches addObject:touch];
    }
	NSUInteger numTouches = [touches count];

#ifdef DEBUG_TOUCH
	char errorstrbuf[16];
	sprintf(errorstrbuf,"Begin %d",numTouches);
	errorstr = errorstrbuf;
	newerror = true;
#endif
	
	// Event for all fingers (global). We do this first so people can choose to create/remove regions that can also receive events for the locations (yay)
	for(int t =0; t<numTouches; t++)
	{
		UITouch *touch = [[touches allObjects] objectAtIndex:t];
		CGPoint position = [touch locationInView:self];
		callAllTouchSources(position.x/(float)HALF_SCREEN_WIDTH-1.0, 1.0-position.y/(float)HALF_SCREEN_HEIGHT,t);
	}
	
	for(int t=0; t< numTouches; t++)
	{
		UITouch *touch = [[touches allObjects] objectAtIndex:t];
		NSUInteger numTaps = [touch tapCount];
		CGPoint position = [touch locationInView:self];

		onTouchDownParse(t, numTaps, position.x, position.y);
	}
	
	// Find two-finger drags
	for(int t1 = 0; t1<numTouches-1; t1++)
	{
		for(int t2 = t1+1; t2<numTouches; t2++)
		{
			if(testDoubleDragStart(t1,t2))
			{
				int touch1 = AddUITouch([[touches allObjects] objectAtIndex:t1]);
				int touch2 = AddUITouch([[touches allObjects] objectAtIndex:t2]);

				doTouchDoubleDragStart(t1,t2,touch1, touch2);
			}
		}
	}
	
	// Find single finger drags (not already classified as two-finger ones.
	for(int t = 0; t<numTouches; t++)
	{
		if(testSingleDragStart(t))
		{
			int touch1 = AddUITouch([[touches allObjects] objectAtIndex:t]);
			CGPoint position1 = [[[touches allObjects] objectAtIndex:t] locationInView:self];
			CGPoint position2;

			int touch2 = getSingleDoubleTouchConversionID(t);
			
			if(touch2 != -1)
			{
				position2 = [UTID2UITouch(touch2) locationInView:self];
			}
				
			doTouchSingleDragStart(t, touch1, position1.x, position1.y, position2.x, position2.y);
		}
	}		
}

// Handles the continuation of a touch.
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{  
	
	NSUInteger numTouches = [touches count];
#ifdef DEBUG_TOUCH
	char errorstrbuf[16];
	sprintf(errorstrbuf,"Move %d",numTouches);
	errorstr = errorstrbuf;
	newerror = true;
#endif

	
	// Event for all fingers (global)
	for(int t =0; t<numTouches; t++)
	{
		UITouch *touch = [[touches allObjects] objectAtIndex:t];
		CGPoint position = [touch locationInView:self];
		callAllTouchSources(position.x/(float)HALF_SCREEN_WIDTH-1.0, 1.0-position.y/(float)HALF_SCREEN_HEIGHT,t);
	}

	onTouchArgInit();
	for(int t=0; t< numTouches; t++)
	{
		UITouch *touch = [[touches allObjects] objectAtIndex:t];
		UITouchPhase phase = [touch phase];
		CGPoint position = [touch locationInView:self];
		if(phase == UITouchPhaseMoved) 
		{
			CGPoint oldposition = [[[touches allObjects] objectAtIndex:t] previousLocationInView:self];
			int t2 = t;
			if(oldposition.x != cursorpositionx[t] || oldposition.y != cursorpositiony[t])
			{
				for(t2=0; t2<MAX_FINGERS && (oldposition.x != cursorpositionx[t2] || oldposition.y != cursorpositiony[t2]); t2++);
				if(t2==MAX_FINGERS)
				{
					int a=0;
					t2=t;
				}
			}	
			onTouchMoveUpdate(t, t2, oldposition.x, oldposition.y, position.x, position.y);
		}
		else
		{
			int a=0;
		}
	}
	
	for(int i=0; i < arg; i++)
	{
		int t = argmoved[i];
		int dragidx = FindSingleDragTouch(UITouch2UTID([[touches allObjects] objectAtIndex:t]));
		if(dragidx != -1)
		{
			if(dragtouches[dragidx].touch2 != -1) // Double Touch here.
			{
				CGPoint position1 = [UTID2UITouch(dragtouches[dragidx].touch1) locationInView:self];
				CGPoint position2 = [UTID2UITouch(dragtouches[dragidx].touch2) locationInView:self];
				
				onTouchDoubleDragUpdate(t, dragidx, position1.x, position1.y, position2.x, position2.y);
				
			}
			else
			{
				onTouchSingleDragUpdate(t, dragidx);
			}
		}
		else 
		{
			onTouchScrollUpdate(t);
		}
	}
	
	callAllOnEnterLeaveRegions(arg, argcoordx, argcoordy,arg2coordx,arg2coordy);
}

// Handles the end of a touch event.
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
#ifdef DEBUG_TOUCH
	errorstr = "End";
	newerror = true;
#endif
    for (UITouch *touch in touches) {
        [ActiveTouches removeObject:touch];
    }
	NSUInteger numTouches = [touches count];

	// Event for all fingers (global). We do this first so people can choose to create/remove regions that can also receive events for the locations (yay)
	for(int t =0; t<numTouches; t++)
	{
		UITouch *touch = [[touches allObjects] objectAtIndex:t];
		CGPoint position = [touch locationInView:self];
		callAllTouchSources(position.x/(float)HALF_SCREEN_WIDTH-1.0, 1.0-position.y/(float)HALF_SCREEN_HEIGHT,t);
	}
	
	onTouchArgInit();
	
	for(int t=0; t< numTouches; t++)
	{
		UITouch *touchip = [[touches allObjects] objectAtIndex:t];
		int touch = UITouch2UTID(touchip);
		UITouchPhase phase = [touchip phase];
		CGPoint position = [touchip locationInView:self];

		if(phase == UITouchPhaseEnded)		{

			onTouchDragEnd(t,touch,position.x,position.y);
			CGPoint oldposition = [touchip previousLocationInView:self];
			NSUInteger numTaps = [touchip tapCount];
			onTouchEnds(numTaps, oldposition.x, oldposition.y, position.x, position.y);
		}
		else
		{
			int a = 0;
		}
	}

	callAllOnEnterLeaveRegions(arg, argcoordx, argcoordy,arg2coordx,arg2coordy);
	
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    // Enumerates through all touch object
    for (UITouch *touch in touches){
		// Sends to the dispatch method, which will make sure the appropriate subview is acted upon
	}
}

#ifdef SANDWICH_SUPPORT
// sandwich update Delegate functions
- (void) rearTouchUpdate: (SandwichEventManager * ) sender;
{
	
	CGPoint touchCoords = [sender touchCoordsForTouchAtIndex: 0];
	//	tx = touchCoords.x; gessl disabling rear
	//	ty = touchCoords.y;
}

- (void) pressureUpdate: (SandwichEventManager * ) sender;
{
	pressure[0] = sender.pressureValues[0];
	pressure[1] = sender.pressureValues[1];
	pressure[2] = sender.pressureValues[2];
	pressure[3] = sender.pressureValues[3];
	
	float avg = pressure[3];	
	
	// This feeds the lua API events
	callAllOnPressure(avg);
	
	// We call the UrSound pipeline second so that the lua engine can actually change it based on acceleration data before anything happens.
//	callAllPressureSources(avg);
	
}
#endif


// Networking

// The Bonjour application protocol, which must:
// 1) be no longer than 14 characters
// 2) contain only lower-case letters, digits, and hyphens
// 3) begin and end with lower-case letter or digit
// It should also be descriptive and human-readable
// See the following for more information:
// http://developer.apple.com/networking/bonjour/faq.html
#define kurNetIdentifier		@"urMus"


#define kurNetTestID	@"_urMus._udp."

// Interfacing with C of the lua API
extern EAGLView* g_glView;

void Net_Send(float data)
{
	int8_t idata = data*128;
	//	[g_glView send:(int8_t)idata];
}

void Net_Advertise(const char* nsid, int port)
{
	NSString *nsid2 =  [[NSString alloc] initWithUTF8String: nsid];
	NSString *fullnsid = [NSString stringWithFormat:@"_%@urMus._udp.", nsid2];
	[g_glView advertiseService:[[UIDevice currentDevice] name] withID:fullnsid atPort:port];
}

void Net_Find(const char* nsid)
{
	NSString *nsid2 =  [[NSString alloc] initWithUTF8String: nsid];
	NSString *fullnsid = [NSString stringWithFormat:@"_%@urMus._udp.", nsid2];
	[g_glView searchForServicesOfType:fullnsid inDomain:@""];
}

- (void) advertiseService:(NSString *)name withID:(NSString *)nsid atPort:(int)port {
	self.netService = [[NSNetService alloc] initWithDomain:@""
											  type:nsid
											  name:name
											  port:port];
	// Delegate is informed of status asynchronously

	[self.netService scheduleInRunLoop:[NSRunLoop currentRunLoop]
							   forMode:NSRunLoopCommonModes];
	
	[self.netService setDelegate:self];
	[self.netService publish];
	[self.netService retain];
}

- (void) setup {
	
	[self advertiseService:[[UIDevice currentDevice] name] withID:kurNetTestID atPort:8888];

	[self searchForServicesOfType:@"_urMus._udp." inDomain:@""];
}
	

// Creates an NSNetServiceBrowser that searches for services of a particular type in a particular domain.
// If a service is currently being resolved, stop resolving it and stop the service browser from
// discovering other services.
- (BOOL)searchForServicesOfType:(NSString *)type inDomain:(NSString *)domain {
	
	[self.netServiceBrowser stop];
	[self.services removeAllObjects];
	
	NSNetServiceBrowser *aNetServiceBrowser = [[NSNetServiceBrowser alloc] init];
	if(!aNetServiceBrowser) {
        // The NSNetServiceBrowser couldn't be allocated and initialized.
		return NO;
	}
	
	aNetServiceBrowser.delegate = self;
	self.netServiceBrowser = aNetServiceBrowser;
	[aNetServiceBrowser release];
	[self.netServiceBrowser searchForServicesOfType:type inDomain:domain];
	
	return YES;
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didRemoveService:(NSNetService *)service moreComing:(BOOL)moreComing {
	// If a service went away, stop resolving it if it's currently being resolved,
	// remove it from the list and update the table view if no more events are queued.

	callAllOnNetDisconnect([[service name] UTF8String]);
	[self.services removeObject:service];
}	

- (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didFindService:(NSNetService *)service moreComing:(BOOL)moreComing {
	// If a service came online, add it to the list and update the table view if no more events are queued.
	[service setDelegate:self];
	[service resolveWithTimeout:10];
	 NSString* temp = [service.name copy];	
	[service retain];
}	

// This should never be called, since we resolve with a timeout of 0.0, which means indefinite
- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict {
//	[self stopCurrentResolve];
	int a;
}

- (NSString *)getStringFromAddressData:(NSData *)dataIn {
	struct sockaddr_in  *socketAddress = nil;
	NSString            *ipString = nil;
	
	socketAddress = (struct sockaddr_in *)[dataIn bytes];
	ipString = [NSString stringWithFormat: @"%s",
				inet_ntoa(socketAddress->sin_addr)];  ///problem here
	return ipString;
}
	
	
- (void)netServiceDidResolveAddress:(NSNetService *)service {
	int cnt = [[service addresses] count];
	for (int i = 0; i < [[service addresses] count]; i++)
	{
		if ([service.name isEqual:[[UIDevice currentDevice] name]]) {
			self.ownEntry = service;
			[_services removeObject:service];
		}
		else
		{
			NSString* ipaddress = [self getStringFromAddressData:[[service addresses] objectAtIndex:i]];
			if (![ipaddress isEqual:@"0.0.0.0"])
			{
				callAllOnNetConnect([ipaddress UTF8String]);
				[self.services addObject:service];
			}
		}
	}
	[service retain];
}

@end
