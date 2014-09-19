//fragment shader
//computes horizontal or vertical smoothing, in 2 passes.
varying mediump vec2 tCoord;
uniform mediump sampler2D pic0;
uniform mediump sampler2D pic1;
uniform mediump vec2 offset[8];
uniform mediump vec4 kernelValue[8];

void main(void)
{
    mediump vec4 sum=vec4(0.25,0.25,0.25,0.25)*texture2D(pic0,tCoord);
    for(int i=0;i<8;++i){
        sum+=kernelValue[i]*texture2D(pic1,tCoord+offset[i]);
    }
    gl_FragColor=sum;
}
