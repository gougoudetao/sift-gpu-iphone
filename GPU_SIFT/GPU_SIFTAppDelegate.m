
#import "GPU_SIFTAppDelegate.h"
#import "SIFT.h"

@implementation GPU_SIFTAppDelegate

@synthesize window;

- (void)applicationDidFinishLaunching:(UIApplication *)application
{
    UIImage* image=[UIImage imageNamed:@"lena.jpg"];
    CGImageRef picture = image.CGImage;
    
	[glView initWithWidth:image.size.width Height:image.size.height Octaves:4];
	
	NSMutableArray * test = [glView computeSiftOnCGImage:picture];
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
