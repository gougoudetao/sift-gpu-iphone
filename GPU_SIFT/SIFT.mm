
#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/ES2/gl.h>
#import <opencv2/highgui/ios.h>
#import <fstream>

#import "SIFT.h"
#define STRINGIFY(A) #A

#ifdef _ARM_ARCH_7
	#import <arm_neon.h>
#endif

#import "keyPoint.h"

#if 1
#define TS(name) int64 t_##name = cv::getTickCount()
#define TE(name) printf("TIMER_" #name ": %.2fms\n", 1000.*((cv::getTickCount() - t_##name) / cv::getTickFrequency()))
#else
#define TS(name)
#define TE(name)
#endif

@interface SIFT (EAGLViewSprite)

- (void)initWithWidth:(int)width Height:(int)height Octaves:(int)oct;

@end

@implementation SIFT

+ (Class) layerClass
{
	return [CAEAGLLayer class];
}


- (id)initWithCoder:(NSCoder*)coder
{
	if((self = [super initWithCoder:coder])) {
		// Get the layer
		CAEAGLLayer *eaglLayer = (CAEAGLLayer*) self.layer;
		
		eaglLayer.opaque = YES;
		eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
										[NSNumber numberWithBool:FALSE], kEAGLDrawablePropertyRetainedBacking, kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat, nil];
			
		context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
		
		if(!context || ![EAGLContext setCurrentContext:context]) {
			[self release];
			return nil;
		}
		
		[EAGLContext setCurrentContext:context];
	}
	return self;
}

//reads a text file into a buffer.
//necessary to read shader file
const char* filetobuf(const char *file)
{
    FILE *fptr;
    long length;
    char *buf;
	
    fptr = fopen(file, "rb"); 
    if (!fptr) 
        return NULL;
    fseek(fptr, 0, SEEK_END); 
    length = ftell(fptr); 
    buf = (char*)malloc(length+1);
    fseek(fptr, 0, SEEK_SET); 
    fread(buf, length, 1, fptr); 
    fclose(fptr);
    buf[length] = 0; 
	
    return buf;
}

// This function compiles shaders and checks that everything went good.
GLuint BuildShader(NSString* filename, GLenum shaderType)
{
	NSString* ext = shaderType==GL_VERTEX_SHADER ? @"vsh" : @"fsh";
	
	const char* source = filetobuf([[[NSBundle  mainBundle] pathForResource:filename ofType:ext inDirectory:nil] cStringUsingEncoding:NSUTF8StringEncoding]);
    GLuint shaderHandle = glCreateShader(shaderType);
    glShaderSource(shaderHandle, 1, &source, 0);
    glCompileShader(shaderHandle);
    
    GLint compileSuccess;
    glGetShaderiv(shaderHandle, GL_COMPILE_STATUS, &compileSuccess);
    
    if (compileSuccess == GL_FALSE) {
        GLint logLength;
        glGetShaderiv(shaderHandle, GL_INFO_LOG_LENGTH, &logLength);
        if(logLength>0){
            GLchar* log=(GLchar*)malloc(logLength);
            glGetShaderInfoLog(shaderHandle, logLength, &logLength, log);
            NSLog(@"Shader compile log:\n%s",log);
            free(log);
        }
        exit(1);
    }
    
    return shaderHandle;
}


// This function associates a vertex shader and a pixel shader
GLuint BuildProgram(NSString* vertexShaderFilename, NSString* fragmentShaderFilename)
{
    GLuint vertexShader = BuildShader(vertexShaderFilename, GL_VERTEX_SHADER);
    GLuint fragmentShader = BuildShader(fragmentShaderFilename, GL_FRAGMENT_SHADER);
    
    GLuint programHandle = glCreateProgram();
    glAttachShader(programHandle, vertexShader);
    glAttachShader(programHandle, fragmentShader);
    glLinkProgram(programHandle);
    
    GLint linkSuccess;
    glGetProgramiv(programHandle, GL_LINK_STATUS, &linkSuccess);
    if (linkSuccess == GL_FALSE) {
        exit(2);
    }
	return programHandle;
}


// Initialize the class
- (void)initWithWidth:(int)picWidth Height:(int)picHeight
{
	width=picWidth;
	height=picHeight;
		
	// Full screen writing coordinates
	writingPosition[0] = -1.0;  writingPosition[1] = -1.0;  writingPosition[2] = 1.0;  writingPosition[3] = -1.0;  writingPosition[4] = -1.0;  writingPosition[5] = 1.0;  writingPosition[6] = 1.0;  writingPosition[7] = 1.0;
	
	// Fulle screen reading coordinates
	readingPosition[0] = 0.0;  readingPosition[1] = 0.0;  readingPosition[2] = 1.0;  readingPosition[3] = 0.0;  readingPosition[4] = 0.0;  readingPosition[5] = 1.0;  readingPosition[6] = 1.0;  readingPosition[7] = 1.0;

	// ------------------- SHADERS INITIALIZATION PART ----------------------
	/* Builds shaders and sends them data, or at least locates the
	 shader variable position so data can be sent to it later */

    //高斯程序
    gauss=BuildProgram(@"gaussVertex", @"gauss");
    glUseProgram(gauss);
    gaussWritingPosition=glGetAttribLocation(gauss, "writingPosition");
    glVertexAttribPointer(gaussWritingPosition, 2, GL_SHORT, GL_FALSE, 0, writingPosition);
    glEnableVertexAttribArray(gaussWritingPosition);
    gaussReadingPosition=glGetAttribLocation(gauss, "readingPosition");
    glVertexAttribPointer(gaussReadingPosition, 2, GL_SHORT, GL_FALSE, 0, readingPosition);
    glEnableVertexAttribArray(gaussReadingPosition);
    gaussTexelWidthOffset=glGetUniformLocation(gauss, "texelWidthOffset");
    gaussTexelHeightOffset=glGetUniformLocation(gauss, "texelHeightOffset");
    gaussPic=glGetUniformLocation(gauss, "inputImageTexture");
    
    //梯度程序
    gradient=BuildProgram(@"gradientVertex", @"gradient");
    glUseProgram(gradient);
    gradientWritingPosition=glGetAttribLocation(gradient, "writingPosition");
    glVertexAttribPointer(gradientWritingPosition, 2, GL_SHORT, GL_FALSE, 0, writingPosition);
    glEnableVertexAttribArray(gradientWritingPosition);
    gradientReadingPosition=glGetAttribLocation(gradient, "readingPosition");
    glVertexAttribPointer(gradientReadingPosition, 2, GL_SHORT, GL_FALSE, 0, readingPosition);
    glEnableVertexAttribArray(gradientReadingPosition);
    gradientTexelWidthOffset=glGetUniformLocation(gradient, "texelWidthOffset");
    gradientTexelHeightOffset=glGetUniformLocation(gradient, "texelHeightOffset");
    gradientPic=glGetUniformLocation(gradient, "inputImageTexture");
    
    //差分程序
    diff=BuildProgram(@"diffVertex", @"diff");
    glUseProgram(diff);
    diffWritingPosition=glGetAttribLocation(diff, "writingPosition");
    glVertexAttribPointer(diffWritingPosition, 2, GL_SHORT, GL_FALSE, 0, writingPosition);
    glEnableVertexAttribArray(diffWritingPosition);
    diffReadingPosition=glGetAttribLocation(diff, "readingPosition");
    glVertexAttribPointer(diffReadingPosition, 2, GL_SHORT, GL_FALSE, 0, readingPosition);
    glEnableVertexAttribArray(diffReadingPosition);
    diffPic=glGetUniformLocation(diff, "inputImageTexture");
    preDiffPic=glGetUniformLocation(diff, "preInputImageTexture");
    
    //求G矩阵程序
    spatialGrad=BuildProgram(@"spatialGradVertex", @"spatialGrad");
    glUseProgram(spatialGrad);
    spatialGradWritingPosition=glGetAttribLocation(spatialGrad, "writingPosition");
    glVertexAttribPointer(spatialGradWritingPosition, 2, GL_SHORT, GL_FALSE, 0, writingPosition);
    glEnableVertexAttribArray(spatialGradWritingPosition);
    spatialGradReadingPosition=glGetAttribLocation(spatialGrad, "readingPosition");
    glVertexAttribPointer(spatialGradReadingPosition, 2, GL_SHORT, GL_FALSE, 0, readingPosition);
    glEnableVertexAttribArray(spatialGradReadingPosition);
    ixPic=glGetUniformLocation(spatialGrad, "picIX");
    iyPic=glGetUniformLocation(spatialGrad, "picIY");
    
    //求b向量程序
    timeGrad=BuildProgram(@"timeGradVertex", @"timeGrad");
    glUseProgram(timeGrad);
    timeGradWritingPosition=glGetAttribLocation(timeGrad, "writingPosition");
    glVertexAttribPointer(timeGradWritingPosition, 2, GL_SHORT, GL_FALSE, 0, writingPosition);
    glEnableVertexAttribArray(timeGradWritingPosition);
    timeGradReadingPosition=glGetAttribLocation(timeGrad, "readingPosition");
    glVertexAttribPointer(timeGradReadingPosition, 2, GL_SHORT, GL_FALSE, 0, readingPosition);
    glEnableVertexAttribArray(timeGradReadingPosition);
    timeIXPic=glGetUniformLocation(timeGrad, "picIX");
    timeIYPic=glGetUniformLocation(timeGrad, "picIY");
    timeDiffPic=glGetUniformLocation(timeGrad, "picDiff");
    
    //追踪程序
    track=BuildProgram(@"trackerVertex", @"tracker");
    glUseProgram(track);
    trackWritingPosition=glGetAttribLocation(track, "writingPosition");
    glVertexAttribPointer(trackWritingPosition, 2, GL_SHORT, GL_FALSE, 0, writingPosition);
    glEnableVertexAttribArray(trackWritingPosition);
    trackReadingPosition=glGetAttribLocation(track, "readingPosition");
    glVertexAttribPointer(trackReadingPosition, 2, GL_SHORT, GL_FALSE, 0, readingPosition);
    glEnableVertexAttribArray(trackReadingPosition);
    trackKeyPointsPic=glGetUniformLocation(track, "picKeyPoints");
    trackIXPic=glGetUniformLocation(track, "picIX");
    trackIYPic=glGetUniformLocation(track, "picIY");
    trackDiffPic=glGetUniformLocation(track, "picDiff");
    trackWidth=glGetUniformLocation(track, "width");
    trackHeight=glGetUniformLocation(track, "height");
    
	// ---------------------- BUFFERS AND TEXTURES INITIALIZATION --------------------

    //原始图片纹理
	glGenTextures(1, &pic);
	glBindTexture(GL_TEXTURE_2D, pic);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE); 
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
	
    glGenTextures(1, &prePic);
	glBindTexture(GL_TEXTURE_2D, prePic);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
    
    //图像金字塔帧缓存及其纹理初始化
    for(int i=0;i<4;++i){
        glGenFramebuffers(1,&gaussBuf[i]);
        glBindFramebuffer(GL_FRAMEBUFFER, gaussBuf[i]);
        glGenTextures(1, &gaussTex[i]);
        glBindTexture(GL_TEXTURE_2D, gaussTex[i]);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width>>i, height>>i, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, gaussTex[i], 0);
        
        glGenFramebuffers(1,&preGaussBuf[i]);
        glBindFramebuffer(GL_FRAMEBUFFER, preGaussBuf[i]);
        glGenTextures(1, &preGaussTex[i]);
        glBindTexture(GL_TEXTURE_2D, preGaussTex[i]);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width>>i, height>>i, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, preGaussTex[i], 0);
    }
    
    //差分
    for(int i=0;i<4;++i){
        glGenFramebuffers(1,&diffBuf[i]);
        glBindFramebuffer(GL_FRAMEBUFFER, diffBuf[i]);
        glGenTextures(1, &diffTex[i]);
        glBindTexture(GL_TEXTURE_2D, diffTex[i]);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width>>i, height>>i, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, diffTex[i], 0);
    }
	
    //图像梯度帧缓存及其纹理初始化
    for(int i=0;i<4;++i){
        glGenFramebuffers(1,&gradientBuf[i][0]);
        glBindFramebuffer(GL_FRAMEBUFFER, gradientBuf[i][0]);
        glGenTextures(1, &gradientTex[i][0]);
        glBindTexture(GL_TEXTURE_2D, gradientTex[i][0]);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width>>i, height>>i, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, gradientTex[i][0], 0);
        
        glGenFramebuffers(1,&gradientBuf[i][1]);
        glBindFramebuffer(GL_FRAMEBUFFER, gradientBuf[i][1]);
        glGenTextures(1, &gradientTex[i][1]);
        glBindTexture(GL_TEXTURE_2D, gradientTex[i][1]);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width>>i, height>>i, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, gradientTex[i][1], 0);
        
        glGenFramebuffers(1,&preGradientBuf[i][0]);
        glBindFramebuffer(GL_FRAMEBUFFER, preGradientBuf[i][0]);
        glGenTextures(1, &preGradientTex[i][0]);
        glBindTexture(GL_TEXTURE_2D, preGradientTex[i][0]);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width>>i, height>>i, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, preGradientTex[i][0], 0);
        
        glGenFramebuffers(1,&preGradientBuf[i][1]);
        glBindFramebuffer(GL_FRAMEBUFFER, preGradientBuf[i][1]);
        glGenTextures(1, &preGradientTex[i][1]);
        glBindTexture(GL_TEXTURE_2D, preGradientTex[i][1]);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width>>i, height>>i, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, preGradientTex[i][1], 0);
    }
    
    //G矩阵缓存及其纹理初始化
//    for(int i=0;i<4;++i){
//        glGenFramebuffers(1, &spatialGradBuf[i]);
//        glBindFramebuffer(GL_FRAMEBUFFER, spatialGradBuf[i]);
//        glGenTextures(1, &spatialGradTex[i]);
//        glBindTexture(GL_TEXTURE_2D, spatialGradTex[i]);
//        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
//        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
//        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
//        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
//        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width>>i, height>>i, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
//        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, spatialGradTex[i], 0);
//    }
    
    //b向量缓存及其纹理初始化
//    for(int i=0;i<4;++i){
//        glGenFramebuffers(1, &timeGradBuf[i]);
//        glBindFramebuffer(GL_FRAMEBUFFER, timeGradBuf[i]);
//        glGenTextures(1, &timeGradTex[i]);
//        glBindTexture(GL_TEXTURE_2D, timeGradTex[i]);
//        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
//        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
//        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
//        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
//        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width>>i, height>>i, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
//        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, timeGradTex[i], 0);
//    }
    
	glGenFramebuffers(1, &dispBuf);
	glBindFramebuffer(GL_FRAMEBUFFER, dispBuf);
	glGenRenderbuffers(1, &renderBuf);
	glBindRenderbuffer(GL_RENDERBUFFER, renderBuf);
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, renderBuf);
	[context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(id<EAGLDrawable>)self.layer];
	
}


-(NSString *)applicationDocumentsDirectoryPath{
    NSString *documentDirectory=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)lastObject];
    
    return documentDirectory;
}

void convertToGray (uint8_t * __restrict dest, uint8_t * __restrict src, int width, int height)
{
    long k=0;
    for(int j=0;j<height;++j){
        for(int i=0;i<width;++i){
            uint8_t color=(77*src[k]+151*src[k+1]+28*src[k+2])/256;
            dest[k]=color;
            dest[k+1]=color;
            dest[k+2]=color;
            dest[k+3]=255;
            k+=4;
        }
    }
}

-(void) computeSiftOnCGImage:(CGImageRef)picture preCGImage:(CGImageRef)prePicture
{
    //提取前一帧图像中利于跟踪的特征点
    UIImage* preImage=[UIImage imageWithCGImage:prePicture];
    cv::Mat preFrame,preGray;
    UIImageToMat(preImage, preFrame);
    cv::cvtColor(preFrame, preGray, CV_BGR2GRAY);
    std::vector<cv::Point2i> keyPoints;
    cv::goodFeaturesToTrack(preGray, keyPoints, 500, 0.01, 10,cv::Mat(), 3, 0, 0.04);
    int keyPointsNum=keyPoints.size();
    
	//initializing image data
	uint8_t *originalData,*grayData;
	originalData = (uint8_t *) calloc(width * height * 4, sizeof(uint8_t));
    grayData=(uint8_t*)calloc(width*height*4, sizeof(uint8_t));
    
    uint8_t *preOriginalData,*preGrayData;
    preOriginalData=(uint8_t *)calloc(width*height*4, sizeof(uint8_t));
	preGrayData=(uint8_t *)calloc(width*height*4, sizeof(uint8_t));
    
	//Loading image
	CGDataProviderRef dataRef = CGImageGetDataProvider(picture);
	CFDataRef data = CGDataProviderCopyData(dataRef);
	originalData = (GLubyte *) CFDataGetBytePtr(data);
    convertToGray(grayData,originalData,width,height);
	glBindTexture(GL_TEXTURE_2D, pic);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, grayData);
    
    CGDataProviderRef preDataRef=CGImageGetDataProvider(prePicture);
    CFDataRef preData=CGDataProviderCopyData(preDataRef);
    preOriginalData=(GLubyte*)CFDataGetBytePtr(preData);
    convertToGray(preGrayData,preOriginalData,width,height);
    glBindTexture(GL_TEXTURE_2D, prePic);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, preGrayData);
    
    //计算图像金字塔
    for(int i=0;i<4;++i){
        int w=width>>i;
        int h=height>>i;
        glViewport(0, 0, w, h);
        
        //求高斯图像
        glUseProgram(gauss);
        glVertexAttribPointer(gaussWritingPosition, 2, GL_SHORT, GL_FALSE, 0, writingPosition);
        glVertexAttribPointer(gaussReadingPosition, 2, GL_SHORT, GL_FALSE, 0, readingPosition);
        glUniform1f(gaussTexelWidthOffset, 1.0/width);
        glUniform1f(gaussTexelHeightOffset, 1.0/height);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, pic);
        glUniform1i(gaussPic, 0);
        glBindFramebuffer(GL_FRAMEBUFFER, gaussBuf[i]);
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        
        //读取纹理到图片并显示
//        uint8_t *testGaussData;
//        testGaussData=(uint8_t*)calloc(4*w*h, sizeof(uint8_t));
//        glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, testGaussData);
//        [self saveTextureAsImageWithBytes:testGaussData width:w height:h filename:[NSString stringWithFormat:@"gaussLevel%d.jpg",i]];
//        [self saveTestureAsFileWithBytes:testGaussData width:w height:h filename:[NSString stringWithFormat:@"gaussLevel%d.txt",i]];
//        free(testGaussData);
        
        glUseProgram(gauss);
        glVertexAttribPointer(gaussWritingPosition, 2, GL_SHORT, GL_FALSE, 0, writingPosition);
        glVertexAttribPointer(gaussReadingPosition, 2, GL_SHORT, GL_FALSE, 0, readingPosition);
        glUniform1f(gaussTexelWidthOffset, 1.0/width);
        glUniform1f(gaussTexelHeightOffset, 1.0/height);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, prePic);
        glUniform1i(gaussPic, 0);
        glBindFramebuffer(GL_FRAMEBUFFER, preGaussBuf[i]);
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        
        //读取纹理到图片并显示
//        uint8_t *testPreGaussData;
//        testPreGaussData=(uint8_t*)calloc(4*w*h, sizeof(uint8_t));
//        glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, testPreGaussData);
//        [self saveTextureAsImageWithBytes:testPreGaussData width:w height:h filename:[NSString stringWithFormat:@"preGaussLevel%d.jpg",i]];
//        [self saveTestureAsFileWithBytes:testPreGaussData width:w height:h filename:[NSString stringWithFormat:@"preGaussLevel%d.txt",i]];
//        free(testPreGaussData);
        
        
        //求差分图像
        glUseProgram(diff);
        glVertexAttribPointer(diffWritingPosition, 2, GL_SHORT, GL_FALSE, 0, writingPosition);
        glVertexAttribPointer(diffReadingPosition, 2, GL_SHORT, GL_FALSE, 0, readingPosition);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, gaussTex[i]);
        glUniform1i(diffPic, 0);
        glActiveTexture(GL_TEXTURE1);
        glBindTexture(GL_TEXTURE_2D, preGaussTex[i]);
        glUniform1i(preDiffPic, 1);
        glActiveTexture(GL_TEXTURE0);
        glBindFramebuffer(GL_FRAMEBUFFER, diffBuf[i]);
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        
        uint8_t *testDiffData;
        testDiffData=(uint8_t*)calloc(4*w*h, sizeof(uint8_t));
        glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, testDiffData);
        [self saveTestureAsFileWithBytes:testDiffData width:w height:h filename:[NSString stringWithFormat:@"diff%d.txt",i]];
        free(testDiffData);
        
        
        //求IX
        glUseProgram(gradient);
        glVertexAttribPointer(gradientWritingPosition, 2, GL_SHORT, GL_FALSE, 0, writingPosition);
        glVertexAttribPointer(gradientReadingPosition, 2, GL_SHORT, GL_FALSE, 0, readingPosition);
        glUniform1f(gradientTexelWidthOffset, 1.0/w);
        glUniform1f(gradientTexelHeightOffset, 0);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, gaussTex[i]);
        glUniform1i(gradientPic, 0);
        glActiveTexture(GL_TEXTURE0);
        glBindFramebuffer(GL_FRAMEBUFFER, gradientBuf[i][0]);
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        
        uint8_t *testGradientIXData;
        testGradientIXData=(uint8_t*)calloc(4*w*h, sizeof(uint8_t));
        glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, testGradientIXData);
        [self saveTestureAsFileWithBytes:testGradientIXData width:w height:h filename:[NSString stringWithFormat:@"gradientIX%d.txt",i]];
        free(testGradientIXData);
        
        /*
        glUseProgram(gradient);
        glVertexAttribPointer(gradientWritingPosition, 2, GL_SHORT, GL_FALSE, 0, writingPosition);
        glVertexAttribPointer(gradientReadingPosition, 2, GL_SHORT, GL_FALSE, 0, readingPosition);
        glUniform1f(gradientTexelWidthOffset, 1.0/w);
        glUniform1f(gradientTexelHeightOffset, 0);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, gaussTex[i]);
        glUniform1i(gradientPic, 0);
        glActiveTexture(GL_TEXTURE0);
        glBindFramebuffer(GL_FRAMEBUFFER, preGradientBuf[i][0]);
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        
        uint8_t *testPreGradientIXData;
        testPreGradientIXData=(uint8_t*)calloc(4*w*h, sizeof(uint8_t));
        glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, testPreGradientIXData);
        [self saveTestureAsFileWithBytes:testPreGradientIXData width:w height:h filename:[NSString stringWithFormat:@"preGradientIX%d.txt",i]];
        free(testPreGradientIXData);
         */
        
        //求IY
        glUseProgram(gradient);
        glVertexAttribPointer(gradientWritingPosition, 2, GL_SHORT, GL_FALSE, 0, writingPosition);
        glVertexAttribPointer(gradientReadingPosition, 2, GL_SHORT, GL_FALSE, 0, readingPosition);
        glUniform1f(gradientTexelWidthOffset, 0);
        glUniform1f(gradientTexelHeightOffset,1.0/h);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, gaussTex[i]);
        glUniform1i(gradientPic, 0);
        glActiveTexture(GL_TEXTURE0);
        glBindFramebuffer(GL_FRAMEBUFFER, gradientBuf[i][1]);
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        
        uint8_t *testGradientIYData;
        testGradientIYData=(uint8_t*)calloc(4*w*h, sizeof(uint8_t));
        glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, testGradientIYData);
        [self saveTestureAsFileWithBytes:testGradientIYData width:w height:h filename:[NSString stringWithFormat:@"gradientIY%d.txt",i]];
        free(testGradientIYData);
        
        /*
        glUseProgram(gradient);
        glVertexAttribPointer(gradientWritingPosition, 2, GL_SHORT, GL_FALSE, 0, writingPosition);
        glVertexAttribPointer(gradientReadingPosition, 2, GL_SHORT, GL_FALSE, 0, readingPosition);
        glUniform1f(gradientTexelWidthOffset, 0);
        glUniform1f(gradientTexelHeightOffset,1.0/h);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, gaussTex[i]);
        glUniform1i(gradientPic, 0);
        glActiveTexture(GL_TEXTURE0);
        glBindFramebuffer(GL_FRAMEBUFFER, preGradientBuf[i][1]);
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        
        uint8_t *testPreGradientIYData;
        testPreGradientIYData=(uint8_t*)calloc(4*w*h, sizeof(uint8_t));
        glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, testPreGradientIYData);
        [self saveTestureAsFileWithBytes:testPreGradientIYData width:w height:h filename:[NSString stringWithFormat:@"preGradientIY%d.txt",i]];
        free(testPreGradientIYData);
         */
        
        /*
        //求G矩阵
        glUseProgram(spatialGrad);
        glVertexAttribPointer(spatialGradWritingPosition, 2, GL_SHORT, GL_FALSE, 0, writingPosition);
        glVertexAttribPointer(spatialGradReadingPosition, 2, GL_SHORT, GL_FALSE, 0, readingPosition);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, gradientTex[i][0]);
        glUniform1i(ixPic, 0);
        glActiveTexture(GL_TEXTURE1);
        glBindTexture(GL_TEXTURE_2D, gradientTex[i][1]);
        glUniform1i(iyPic, 1);
        glActiveTexture(GL_TEXTURE0);
        glBindFramebuffer(GL_FRAMEBUFFER, spatialGradBuf[i]);
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        
        //求b向量
        glUseProgram(timeGrad);
        glVertexAttribPointer(timeGradWritingPosition, 2, GL_SHORT, GL_FALSE, 0, writingPosition);
        glVertexAttribPointer(timeGradReadingPosition, 2, GL_SHORT, GL_FALSE, 0, readingPosition);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D,gradientTex[i][0]);
        glUniform1i(timeIXPic, 0);
        glActiveTexture(GL_TEXTURE1);
        glBindTexture(GL_TEXTURE_2D, gradientTex[i][1]);
        glUniform1i(timeIYPic, 1);
        glActiveTexture(GL_TEXTURE2);
        glBindTexture(GL_TEXTURE_2D, diffTex[i]);
        glUniform1i(timeDiffPic, 2);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_FRAMEBUFFER, timeGradBuf[i]);
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        */
        
    }
    
    
    int sqSize=(int)ceil(sqrt((float)keyPointsNum));
    uint8_t *keyPointData=(uint8_t*)calloc(sqSize*sqSize*4, sizeof(uint8_t));
    for(int i=0;i<keyPoints.size();++i){
        int x=keyPoints[i].x/16;
        int y=keyPoints[i].y/16;
        keyPointData[4*i]=x/256;
        keyPointData[4*i+1]=x%256;
        keyPointData[4*i+2]=y/256;
        keyPointData[4*i+3]=y%256;
    }
    
    glGenFramebuffers(1, &trackkeyPointsBuf);
    glBindFramebuffer(GL_FRAMEBUFFER, trackkeyPointsBuf);
    glGenTextures(1, &trackKeyPointsTex);
    glBindTexture(GL_TEXTURE_2D, trackKeyPointsTex);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, sqSize, sqSize, 0, GL_RGBA, GL_UNSIGNED_BYTE, keyPointData);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, trackKeyPointsTex, 0);
    
    
    glViewport(0, 0, sqSize, sqSize);
    for(int i=3;i>=0;--i){
        int w=width>>i;
        int h=height>>i;
        glUseProgram(track);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, trackKeyPointsTex);
        glUniform1i(trackKeyPointsPic, 0);
        glActiveTexture(GL_TEXTURE1);
        glBindTexture(GL_TEXTURE_2D, gradientTex[i][0]);
        glUniform1i(trackIXPic, 1);
        glActiveTexture(GL_TEXTURE2);
        glBindTexture(GL_TEXTURE_2D, gradientTex[i][1]);
        glUniform1i(trackIYPic, 2);
        glActiveTexture(GL_TEXTURE3);
        glBindTexture(GL_TEXTURE_2D, diffTex[i]);
        glUniform1i(trackDiffPic, 3);
        glActiveTexture(GL_TEXTURE0);
        glUniform1f(trackWidth, (float)w);
        glUniform1f(trackHeight, (float)h);
        glBindFramebuffer(GL_FRAMEBUFFER, trackkeyPointsBuf);
        glClear(GL_COLOR_ATTACHMENT0);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        
        uint8_t *testTrackData;
        testTrackData=(uint8_t*)calloc(4*sqSize*sqSize, sizeof(uint8_t));
        glReadPixels(0, 0, sqSize, sqSize, GL_RGBA, GL_UNSIGNED_BYTE, testTrackData);
        [self saveTestureAsFileWithBytes:testTrackData width:sqSize height:sqSize filename:[NSString stringWithFormat:@"track%d.txt",i]];
        free(testTrackData);
    }
    
    for(int i=0;i<5;++i){
        [self saveKeyPointsAsFileWithVector:keyPoints width:sqSize height:sqSize scale:i filename:[NSString stringWithFormat:@"input%d.txt",i]];
    }
    
}


-(void)saveTextureAsImageWithBytes:(uint8_t*)data width:(int)w height:(int)h filename:(NSString*)name
{
    NSData* imageData=[NSData dataWithBytes:data length:4*w*h];
    CGColorSpaceRef colorSpace;
    colorSpace=CGColorSpaceCreateDeviceRGB();
    
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)imageData);
    
    CGImageRef imageRef = CGImageCreate(w,                                 //width
                                        h,                                 //height
                                        8,                                          //bits per component
                                        8 * 4,                       //bits per pixel
                                        w*4,                            //bytesPerRow
                                        colorSpace,                                 //colorspace
                                        kCGImageAlphaNone|kCGBitmapByteOrderDefault,// bitmap info
                                        provider,                                   //CGDataProviderRef
                                        NULL,                                       //decode
                                        false,                                      //should interpolate
                                        kCGRenderingIntentDefault                   //intent
                                        );
    UIImage* finalImage=[UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    
    NSString* filename=[[self applicationDocumentsDirectoryPath]stringByAppendingPathComponent:name];
    
    //NSLog(@"%@",filename);
    [UIImageJPEGRepresentation(finalImage, 1.0)writeToFile:filename atomically:YES];
    
    NSLog(@"save image %@",name);
}

-(void)saveTestureAsFileWithBytes:(uint8_t*)data width:(int)w height:(int)h filename:(NSString*)name
{
    using namespace std;
    ofstream ofs;
    NSString* filename=[[self applicationDocumentsDirectoryPath]stringByAppendingPathComponent:name];
    ofs.open([filename cStringUsingEncoding:NSASCIIStringEncoding]);
    long k=0;
    for(int j=0;j<h;++j){
        for(int i=0;i<w;++i){
            ofs<<(int)data[k]<<","<<(int)data[k+1]<<","<<(int)data[k+2]<<","<<(int)data[k+3]<<" ";
            k+=4;
        }
        ofs<<endl;
    }
    
    ofs.close();
    NSLog(@"save file %@",name);
}

-(void)saveKeyPointsAsFileWithVector:(std::vector<cv::Point2i>)keyPoints width:(int)w height:(int)h scale:(int)scale filename:(NSString*)name
{
    using namespace std;
    assert(scale>=0);
    ofstream ofs;
    NSString* filename=[[self applicationDocumentsDirectoryPath]stringByAppendingPathComponent:name];
    ofs.open([filename cStringUsingEncoding:NSASCIIStringEncoding]);
    for(int i=0;i<keyPoints.size();++i){
        int x=keyPoints[i].x>>scale;
        int y=keyPoints[i].y>>scale;
        ofs<<x/256<<","<<x%256<<","<<y/256<<","<<y%256<<" ";
        if((i+1)%width==0)
            ofs<<endl;
    }
    ofs.close();
    NSLog(@"save file %@",name);
}

// Release resources when they are no longer needed.
- (void)dealloc
{
	if([EAGLContext currentContext] == context) {
		[EAGLContext setCurrentContext:nil];
	}
	
	[context release];
	context = nil;
	
	[super dealloc];
}



@end
