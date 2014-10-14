uniform sampler2D inputImageTexture;
//varying highp vec2 blurCoordinates[5];
varying highp vec2 blurCoordinates[9];
void main()
{
	highp vec4 sum = vec4(0.0);
//    sum += texture2D(inputImageTexture, blurCoordinates[0]) * 0.204164;
//    sum += texture2D(inputImageTexture, blurCoordinates[1]) * 0.304005;
//    sum += texture2D(inputImageTexture, blurCoordinates[2]) * 0.304005;
//    sum += texture2D(inputImageTexture, blurCoordinates[3]) * 0.093913;
//    sum += texture2D(inputImageTexture, blurCoordinates[4]) * 0.093913;
	sum += texture2D(inputImageTexture, blurCoordinates[0]) * 0.25;
	sum += texture2D(inputImageTexture, blurCoordinates[1]) * 0.125;
	sum += texture2D(inputImageTexture, blurCoordinates[2]) * 0.125;
	sum += texture2D(inputImageTexture, blurCoordinates[3]) * 0.125;
	sum += texture2D(inputImageTexture, blurCoordinates[4]) * 0.125;
    sum += texture2D(inputImageTexture, blurCoordinates[5]) * 0.0625;
    sum += texture2D(inputImageTexture, blurCoordinates[6]) * 0.0625;
    sum += texture2D(inputImageTexture, blurCoordinates[7]) * 0.0625;
    sum += texture2D(inputImageTexture, blurCoordinates[8]) * 0.0625;
	gl_FragColor = sum;
}