
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
    trackLevel=glGetUniformLocation(track, "level");
    
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
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
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
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width>>i, height>>i, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, gradientTex[i][0], 0);
        
        glGenFramebuffers(1,&gradientBuf[i][1]);
        glBindFramebuffer(GL_FRAMEBUFFER, gradientBuf[i][1]);
        glGenTextures(1, &gradientTex[i][1]);
        glBindTexture(GL_TEXTURE_2D, gradientTex[i][1]);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width>>i, height>>i, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, gradientTex[i][1], 0);
    }
    
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
    //一系列Opencv的操作
    //提取前一帧图像中利于跟踪的特征点
    UIImage* preImage=[UIImage imageWithCGImage:prePicture];
    cv::Mat preFrame,preGray;
    UIImageToMat(preImage, preFrame);
    cv::cvtColor(preFrame, preGray, CV_BGR2GRAY);
    UIImage* nowImage=[UIImage imageWithCGImage:picture];
    cv::Mat nowFrame,nowGray;
    UIImageToMat(nowImage, nowFrame);
    cv::cvtColor(nowFrame, nowGray, CV_BGR2GRAY);
    
    cv::Size subPixWinSize=cv::Size(10,10);
    cv::TermCriteria termcrit(CV_TERMCRIT_ITER|CV_TERMCRIT_EPS,20,0.03);
    
    std::vector<cv::Point2f> keyPoints,nowPoints;
    cv::goodFeaturesToTrack(preGray, keyPoints, 500, 0.01, 10,cv::Mat(), 3, 0, 0.04);
    cv::cornerSubPix(preGray, keyPoints, subPixWinSize, cv::Size(-1,-1), termcrit);
    int keyPointsNum=keyPoints.size();
    std::vector<uchar> status;
    std::vector<float> err;
    
    cv::calcOpticalFlowPyrLK(preGray, nowGray, keyPoints, nowPoints, status, err);
    
    std::vector<cv::Point2f> preTruePoints,nowTruePoints;
    
    for(int i=0;i<keyPointsNum;++i){
        if(!status[i]) continue;
        
        preTruePoints.push_back(keyPoints[i]);
        nowTruePoints.push_back(nowPoints[i]);
    }
    
    [self drawKeypointsAndSaveToFileWithMat:preFrame KeyPoints:keyPoints filename:@"preImage.jpg" color:cv::Scalar(0,255,0)];
    [self drawFloatKeypointsAndSaveToFileWithMat:nowFrame KeyPoints:nowPoints filename:@"trueImage.jpg"];
    [self writeVectorsToFileWithPrekeypointVector:keyPoints nowKeypointVector:nowPoints KeyPointsNum:keyPointsNum filename:@"truePoints.txt"];
    
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
        glUniform1f(gaussTexelWidthOffset, 1.0/w);
        glUniform1f(gaussTexelHeightOffset, 1.0/h);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, pic);
        glUniform1i(gaussPic, 0);
        glBindFramebuffer(GL_FRAMEBUFFER, gaussBuf[i]);
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        
        //读取纹理到图片并显示
        uint8_t *testGaussData;
        testGaussData=(uint8_t*)calloc(4*w*h, sizeof(uint8_t));
        glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, testGaussData);
        [self saveTextureAsImageWithBytes:testGaussData width:w height:h filename:[NSString stringWithFormat:@"gaussLevel%d.jpg",i]];
        [self saveTextureWithCoordinateAsFileWithBytes:testGaussData width:w height:h filename:[NSString stringWithFormat:@"gaussLevel%d.txt",i]];
        
        glUseProgram(gauss);
        glVertexAttribPointer(gaussWritingPosition, 2, GL_SHORT, GL_FALSE, 0, writingPosition);
        glVertexAttribPointer(gaussReadingPosition, 2, GL_SHORT, GL_FALSE, 0, readingPosition);
        glUniform1f(gaussTexelWidthOffset, 1.0/w);
        glUniform1f(gaussTexelHeightOffset, 1.0/h);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, prePic);
        glUniform1i(gaussPic, 0);
        glBindFramebuffer(GL_FRAMEBUFFER, preGaussBuf[i]);
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        
        //读取纹理到图片并显示
        uint8_t *testPreGaussData;
        testPreGaussData=(uint8_t*)calloc(4*w*h, sizeof(uint8_t));
        glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, testPreGaussData);
        [self saveTextureAsImageWithBytes:testPreGaussData width:w height:h filename:[NSString stringWithFormat:@"preGaussLevel%d.jpg",i]];
        [self saveTextureWithCoordinateAsFileWithBytes:testPreGaussData width:w height:h filename:[NSString stringWithFormat:@"preGaussLevel%d.txt",i]];
        
        
        //求差分图像
        if(i!=0){
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
        }else{//原图
            glUseProgram(diff);
            glVertexAttribPointer(diffWritingPosition, 2, GL_SHORT, GL_FALSE, 0, writingPosition);
            glVertexAttribPointer(diffReadingPosition, 2, GL_SHORT, GL_FALSE, 0, readingPosition);
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, pic);
            glUniform1i(diffPic, 0);
            glActiveTexture(GL_TEXTURE1);
            glBindTexture(GL_TEXTURE_2D, prePic);
            glUniform1i(preDiffPic, 1);
            glActiveTexture(GL_TEXTURE0);
            glBindFramebuffer(GL_FRAMEBUFFER, diffBuf[i]);
            glClear(GL_COLOR_BUFFER_BIT);
            glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        }
        
        uint8_t *testDiffData;
        testDiffData=(uint8_t*)calloc(4*w*h, sizeof(uint8_t));
        glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, testDiffData);
        [self saveTextureWithCoordinateAsFileWithBytes:testDiffData width:w height:h filename:[NSString stringWithFormat:@"diff%d.txt",i]];
        
        
        
        //求IX
        if(i!=0){
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
        }else{
            glUseProgram(gradient);
            glVertexAttribPointer(gradientWritingPosition, 2, GL_SHORT, GL_FALSE, 0, writingPosition);
            glVertexAttribPointer(gradientReadingPosition, 2, GL_SHORT, GL_FALSE, 0, readingPosition);
            glUniform1f(gradientTexelWidthOffset, 1.0/w);
            glUniform1f(gradientTexelHeightOffset, 0);
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, pic);
            glUniform1i(gradientPic, 0);
            glActiveTexture(GL_TEXTURE0);
            glBindFramebuffer(GL_FRAMEBUFFER, gradientBuf[i][0]);
            glClear(GL_COLOR_BUFFER_BIT);
            glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        }
        uint8_t *testGradientIXData;
        testGradientIXData=(uint8_t*)calloc(4*w*h, sizeof(uint8_t));
        glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, testGradientIXData);
        [self saveTextureWithCoordinateAsFileWithBytes:testGradientIXData width:w height:h filename:[NSString stringWithFormat:@"gradientIX%d.txt",i]];
        
        
        //求IY
        if(i!=3){
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
        }else{
            glUseProgram(gradient);
            glVertexAttribPointer(gradientWritingPosition, 2, GL_SHORT, GL_FALSE, 0, writingPosition);
            glVertexAttribPointer(gradientReadingPosition, 2, GL_SHORT, GL_FALSE, 0, readingPosition);
            glUniform1f(gradientTexelWidthOffset, 0);
            glUniform1f(gradientTexelHeightOffset,1.0/h);
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, pic);
            glUniform1i(gradientPic, 0);
            glActiveTexture(GL_TEXTURE0);
            glBindFramebuffer(GL_FRAMEBUFFER, gradientBuf[i][1]);
            glClear(GL_COLOR_BUFFER_BIT);
            glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        }
        
        uint8_t *testGradientIYData;
        testGradientIYData=(uint8_t*)calloc(4*w*h, sizeof(uint8_t));
        glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, testGradientIYData);
        [self saveTextureWithCoordinateAsFileWithBytes:testGradientIYData width:w height:h filename:[NSString stringWithFormat:@"gradientIY%d.txt",i]];
        
        
//        if(i==3){
//            [self computeVelocityWithDiffdata:testDiffData IXData:testGradientIXData IYData:testGradientIYData xCoord:14 yCoord:14 width:w height:h];
//        }
        
        //清理申请变量
        free(testGaussData);
        free(testPreGaussData);
        free(testDiffData);
        free(testGradientIXData);
        free(testGradientIYData);
    }
    
    std::vector<cv::Point2f> trackerPoints;
    
    int sqSize=(int)ceil(sqrt((float)keyPointsNum));
    uint8_t *keyPointData=(uint8_t*)calloc(sqSize*sqSize*4, sizeof(uint8_t));
    for(int i=0;i<keyPoints.size();++i){
        
        int x=floor(keyPoints[i].x/8+0.5);
        int y=floor(keyPoints[i].y/8+0.5);
        keyPointData[4*i]=x/256;
        keyPointData[4*i+1]=x%256;
        keyPointData[4*i+2]=y/256;
        keyPointData[4*i+3]=y%256;
    }
    
    glGenFramebuffers(1, &trackkeyPointsBuf);
    glBindFramebuffer(GL_FRAMEBUFFER, trackkeyPointsBuf);
    glGenTextures(1, &trackKeyPointsTex);
    glBindTexture(GL_TEXTURE_2D, trackKeyPointsTex);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
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
        glUniform1i(trackLevel, i);
        glBindFramebuffer(GL_FRAMEBUFFER, trackkeyPointsBuf);
        glClear(GL_COLOR_ATTACHMENT0);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        
        uint8_t *testTrackData;
        testTrackData=(uint8_t*)calloc(4*sqSize*sqSize, sizeof(uint8_t));
        glReadPixels(0, 0, sqSize, sqSize, GL_RGBA, GL_UNSIGNED_BYTE, testTrackData);
        [self saveTextureAsFileWithBytes:testTrackData width:sqSize height:sqSize filename:[NSString stringWithFormat:@"track%d.txt",i]];
        
        if(i==0){
            trackerPoints=[self getTrackedPointsWithBytes:testTrackData KeyNumber:keyPointsNum];
        }
        free(testTrackData);
    }
    

    [self drawKeypointsAndSaveToFileWithMat:nowFrame KeyPoints:trackerPoints filename:@"nowImage.jpg" color:cv::Scalar(255,0,0)];
    [self writeVectorsToFileWithPrekeypointVector:keyPoints nowKeypointVector:trackerPoints KeyPointsNum:keyPointsNum filename:@"points.txt"];
    
}


-(void)writeVectorsToFileWithPrekeypointVector:(std::vector<cv::Point2f>&)pre nowKeypointVector:(std::vector<cv::Point2f>&)now KeyPointsNum:(int)keypointsNum filename:(NSString*)name
{
    using namespace std;
    ofstream ofs;
    NSString* filename=[[self applicationDocumentsDirectoryPath]stringByAppendingPathComponent:name];
    ofs.open([filename cStringUsingEncoding:NSASCIIStringEncoding]);
    
    for(int i=0;i<keypointsNum;++i){
        ofs<<"pre: "<<pre[i].x<<","<<pre[i].y<<" now: "<<now[i].x<<","<<now[i].y<<endl;
    }
    ofs.close();
}

-(std::vector<cv::Point2f>)getTrackedPointsWithBytes:(uint8_t*)data KeyNumber:(int)keyNumber
{
    NSLog(@"keyPoints number: %d",keyNumber);
    std::vector<cv::Point2f> points;
    for(int i=0;i<keyNumber;++i){
        int coordX=data[4*i]*256+data[4*i+1];
        int coordY=data[4*i+2]*256+data[4*i+3];
        cv::Point2f temp(coordX,coordY);
        points.push_back(temp);
    }
    
    return points;
}

-(void)drawFloatKeypointsAndSaveToFileWithMat:(cv::Mat&)image KeyPoints:(const std::vector<cv::Point2f>&)keyPoints filename:(NSString*)name
{
    for(int i=0;i<keyPoints.size();++i){
        cv::circle(image, keyPoints[i], 3, cv::Scalar(0,255,0),-1,8);
    }
    
    UIImage* saveImage=MatToUIImage(image);
    NSString* filename=[[self applicationDocumentsDirectoryPath]stringByAppendingPathComponent:name];
    
    [UIImageJPEGRepresentation(saveImage, 1.0)writeToFile:filename atomically:YES];
}

-(void)drawKeypointsAndSaveToFileWithMat:(cv::Mat&)image KeyPoints:(const std::vector<cv::Point2f>&)keyPoints filename:(NSString*)name color:(cv::Scalar)scalar
{
    for(int i=0;i<keyPoints.size();++i){
        cv::circle(image, keyPoints[i], 3, scalar,-1,8);
    }
    
    UIImage* saveImage=MatToUIImage(image);
    NSString* filename=[[self applicationDocumentsDirectoryPath]stringByAppendingPathComponent:name];
    
    [UIImageJPEGRepresentation(saveImage, 1.0)writeToFile:filename atomically:YES];
}

-(void)computeVelocityWithDiffdata:(uint8_t*)diff IXData:(uint8_t*)IX IYData:(uint8_t*)IY xCoord:(int)x yCoord:(int)y width:(int)w height:(int)h
{
    int coordX=x;
    int coordY=y;
    
    double iixSum=0.005;//IIX
    double iiySum=0.005;//IIY
    double ixiySum=0.005;//IXIY
    double ixixSum=0.005;//IXIX
    double iyiySum=0.005;//IYIY
    
    double u,v;
    for(int k=0;k<5;++k){//迭代次数
        for(int i=-10;i<11;++i){
            for(int j=-10;j<11;++j){
                int tempX=coordX+i;
                if(tempX<0)tempX=0;
                else if (tempX>w)tempX=w;
                
                int tempY=coordY+j;
                if(tempY<0)tempY=0;
                else if (tempY>h)tempY=h;
                
                long k=tempX*w+tempY;
                
                double tempIX=(int)IX[4*k]-128;
                double tempIY=(int)IY[4*k]-128;
                double tempI=(int)diff[4*k]-128;
                
                iixSum+=tempI*tempIX;
                iiySum+=tempI*tempIY;
                ixiySum+=tempIX*tempIY;
                ixixSum+=tempIX*tempIX;
                iyiySum+=tempIY*tempIY;
            }
        }
        double A=ixixSum*iyiySum-ixiySum*ixiySum;
        u=(iyiySum*iixSum-ixiySum*iiySum)/A;
        v=(ixixSum*iiySum-ixiySum*iixSum)/A;
        
        NSLog(@"u:%3.5f,v:%3.5f",u,v);
        if((u<0.5&&u>-0.5)&&(v<0.5&&v<-0.5))break;
        coordX=floor(coordX+u+0.5);
        coordY=floor(coordY+v+0.5);
    }
    
    NSLog(@"x:%d,y:%d",coordX,coordY);
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
    
    //NSLog(@"save image %@",name);
}

-(void)saveTextureAsFileWithBytes:(uint8_t*)data width:(int)w height:(int)h filename:(NSString*)name
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
    //NSLog(@"save file %@",name);
}

-(void)saveTextureWithCoordinateAsFileWithBytes:(uint8_t*)data width:(int)w height:(int)h filename:(NSString*)name
{
    using namespace std;
    ofstream ofs;
    NSString* filename=[[self applicationDocumentsDirectoryPath]stringByAppendingPathComponent:name];
    ofs.open([filename cStringUsingEncoding:NSASCIIStringEncoding]);
    long k=0;
    for(int j=0;j<h;++j){
        for(int i=0;i<w;++i){
            ofs<<j<<","<<i<<":"<<(int)data[k]<<","<<(int)data[k+1]<<","<<(int)data[k+2]<<","<<(int)data[k+3]<<" ";
            k+=4;
        }
        ofs<<endl;
    }
    
    ofs.close();
    //NSLog(@"save file %@",name);
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
    //NSLog(@"save file %@",name);
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
