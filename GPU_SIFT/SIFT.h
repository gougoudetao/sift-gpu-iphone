

#import <UIKit/UIKit.h>
#import <OpenGLES/EAGL.h>

@interface SIFT : UIView
{
@private
	
	EAGLContext *context;
    
	int width;
	int height;
	
	// OpenGL framebuffer pointers:
//	GLuint renderBuf, dispBuf;
    GLuint gaussBuf[4],preGaussBuf[4],diffBuf[4];
    GLuint gradientBuf[4][2];
    GLuint spatialGradBuf[4];
    GLuint timeGradBuf[4];
    GLuint trackkeyPointsBuf[5];
    
	// OpenGL texture pointers:
	GLuint pic,prePic;
    GLuint gaussTex[4],preGaussTex[4],diffTex[4];
    GLuint gradientTex[4][2];
	GLuint spatialGradTex[4];
    GLuint timeGradTex[4];
    GLuint trackKeyPointsTex[5];
    
	// OpenGL program pointers:
	GLuint gauss,gradient,diff,spatialGrad,timeGrad,track;
    
	// Program parameters location pointers:
	GLuint gaussWritingPosition,gaussReadingPosition,gaussTexelWidthOffset,gaussTexelHeightOffset,gaussPic;
	GLuint gradientWritingPosition,gradientReadingPosition,gradientTexelWidthOffset,gradientTexelHeightOffset,gradientPic;
    GLuint diffWritingPosition,diffReadingPosition,diffPic,preDiffPic;
    GLuint trackWritingPosition,trackReadingPosition,trackKeyPointsPic,trackIXPic,trackIYPic,trackDiffPic,trackWidth,trackHeight,trackLevel;
    
    //constants:
	GLshort writingPosition[8];
	GLshort readingPosition[8];
}

-(void) initWithWidth:(int)picWidth Height:(int)picHeight;
-(void) computeOpticalFlowOnCGImage:(CGImageRef)picture preCGImage:(CGImageRef)prePicture;

@end
