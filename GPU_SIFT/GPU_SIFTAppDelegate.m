
#import "GPU_SIFTAppDelegate.h"
#import "SIFT.h"

@implementation GPU_SIFTAppDelegate

@synthesize window;

- (void)applicationDidFinishLaunching:(UIApplication *)application
{
    UIImage* image=[UIImage imageNamed:@"car2.jpg"];
    CGImageRef picture = image.CGImage;
    
    UIImage* preImage=[UIImage imageNamed:@"car1.jpg"];
    CGImageRef prePicture=preImage.CGImage;
    
	[glView initWithWidth:image.size.width Height:image.size.height];
	
    //for(int i=0;i<10;++i)
        [glView computeOpticalFlowOnCGImage:picture preCGImage:prePicture];
}

- (void) applicationWillResignActive:(UIApplication *)application
{
}

- (void) applicationDidBecomeActive:(UIApplication *)application
{
}

- (void)applicationWillTerminate:(UIApplication *)application
{
}

- (void) dealloc
{
	[window release];
	[glView release];
	
	[super dealloc];
}

@end
