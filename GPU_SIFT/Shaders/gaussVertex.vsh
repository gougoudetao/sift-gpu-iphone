attribute vec4 writingPosition;
attribute vec4 readingPosition;

uniform float texelWidthOffset;
uniform float texelHeightOffset;

//varying vec2 blurCoordinates[5];
varying vec2 blurCoordinates[9];
void main()
{
	gl_Position = writingPosition;
    
	vec2 singleStepOffset = vec2(texelWidthOffset, texelHeightOffset);
//	blurCoordinates[0] = readingPosition.xy;
//	blurCoordinates[1] = readingPosition.xy + singleStepOffset * 1.407333;
//	blurCoordinates[2] = readingPosition.xy - singleStepOffset * 1.407333;
//	blurCoordinates[3] = readingPosition.xy + singleStepOffset * 3.294215;
//	blurCoordinates[4] = readingPosition.xy - singleStepOffset * 3.294215;
    
    blurCoordinates[0] = readingPosition.xy;
    blurCoordinates[1] = readingPosition.xy + vec2(0,texelHeightOffset);
    blurCoordinates[2] = readingPosition.xy - vec2(0,texelHeightOffset);
    blurCoordinates[3] = readingPosition.xy + vec2(texelWidthOffset,0);
    blurCoordinates[4] = readingPosition.xy - vec2(texelWidthOffset,0);
    blurCoordinates[5] = readingPosition.xy + singleStepOffset;
    blurCoordinates[6] = readingPosition.xy - singleStepOffset;
    blurCoordinates[7] = readingPosition.xy + vec2(texelWidthOffset,-texelHeightOffset);
    blurCoordinates[8] = readingPosition.xy - vec2(texelWidthOffset,-texelHeightOffset);
}