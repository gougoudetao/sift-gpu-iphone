attribute vec4 writingPosition;
attribute vec4 readingPosition;

uniform float texelWidthOffset;
uniform float texelHeightOffset;

varying vec2 gradCoordinates[2];

void main()
{
	gl_Position = writingPosition;
    
	vec2 singleStepOffset = vec2(texelWidthOffset, texelHeightOffset);
	gradCoordinates[0] = readingPosition.xy + singleStepOffset;
	gradCoordinates[1] = readingPosition.xy - singleStepOffset;
}