attribute vec4 writingPosition;
attribute vec4 readingPosition;

uniform float texelWidthOffset;
uniform float texelHeightOffset;

varying vec2 blurCoordinates[5];

void main()
{
	gl_Position = writingPosition;
    
	vec2 singleStepOffset = vec2(texelWidthOffset, texelHeightOffset);
	blurCoordinates[0] = readingPosition.xy;
	blurCoordinates[1] = readingPosition.xy + singleStepOffset * 1.407333;
	blurCoordinates[2] = readingPosition.xy - singleStepOffset * 1.407333;
	blurCoordinates[3] = readingPosition.xy + singleStepOffset * 3.294215;
	blurCoordinates[4] = readingPosition.xy - singleStepOffset * 3.294215;
}