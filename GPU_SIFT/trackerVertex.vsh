attribute highp vec4 writingPosition;
attribute vec4 readingPosition;

varying vec2 coordinate;

void main(void)
{
    gl_Position = writingPosition;
    coordinate=readingPosition.xy;
}