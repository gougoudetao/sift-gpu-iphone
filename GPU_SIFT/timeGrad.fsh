uniform sampler2D picIX;
uniform sampler2D picIY;
uniform sampler2D picDiff;

varying highp vec2 coordinate;

void main()
{
    highp float iixSum=0.0;
    highp float iiySum=0.0;
    highp vec2 offset=vec2(1.0/640.0,1.0/480.0);
    
    for(int i=-10;i<11;++i){
        for(int j=-10;j<11;++j){
            highp vec2 tempCoord=coordinate+offset*vec2(i,j);
            highp vec4 tempIX=texture2D(picIX,tempCoord);
            highp vec4 tempIY=texture2D(picIY,tempCoord);
            highp vec4 tempI=texture2D(picDiff,tempCoord);
            
            iixSum+=(tempI.x-0.5)*(tempIX.x-0.5);
            iiySum+=(tempI.x-0.5)*(tempIY.x-0.5);
        }
    }
    gl_FragColor=vec4(iixSum/441.0,iiySum/441.0,0,0);
}