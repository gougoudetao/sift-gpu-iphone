attribute vec4 writingPosition;
attribute vec4 readingPosition;

varying vec2 coordinate;

void main()
{
    gl_Position = writingPosition;
    coordinate=readingPosition.xy;
}