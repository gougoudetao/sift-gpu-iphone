uniform sampler2D inputImageTexture;
varying highp vec2 gradCoordinates[2];

void main()
{
	highp vec4 u = texture2D(inputImageTexture, gradCoordinates[0]);
	highp vec4 l = texture2D(inputImageTexture, gradCoordinates[1]);
	gl_FragColor = (u-l+1.0)/2.0;
}