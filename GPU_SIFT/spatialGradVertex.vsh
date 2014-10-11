attribute vec4 writingPosition;
attribute vec4 readingPosition;
uniform float texelOffsetWidth;
uniform float texelOffsetHeight;

varying vec2 coordinate;
varying vec2 texelOffset;
void main()
{
    gl_Position = writingPosition;
    coordinate=readingPosition.xy;
    texelOffset=vec2(texelOffsetWidth,texelOffsetHeight);
}