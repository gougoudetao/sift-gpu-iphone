uniform sampler2D inputImageTexture;
uniform sampler2D preInputImageTexture;

varying highp vec2 coordinate;

void main()
{
    lowp vec4 u = texture2D(inputImageTexture, coordinate);
	lowp vec4 l = texture2D(preInputImageTexture, coordinate);
	gl_FragColor = (u-l+1.0)/2.0;
}
