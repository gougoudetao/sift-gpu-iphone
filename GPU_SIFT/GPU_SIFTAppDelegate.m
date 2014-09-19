
#import "GPU_SIFTAppDelegate.h"
#import "SIFT.h"

@implementation GPU_SIFTAppDelegate

@synthesize window;

- (void)applicationDidFinishLaunching:(UIApplication *)application
{
	[glView initWithWidth:640 Height:480 Octaves:4];
	CGImageRef picture = [UIImage imageNamed:@"test.jpg"].CGImage;
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
