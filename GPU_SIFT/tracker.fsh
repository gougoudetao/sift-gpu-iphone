uniform sampler2D picKeyPoints;
uniform sampler2D picIX;
uniform sampler2D picIY;
uniform sampler2D picDiff;
uniform mediump float width;
uniform mediump float height;

varying highp vec2 coordinate;

void main()
{
    highp float iixSum=0.0005;//IIX
    highp float iiySum=0.0005;//IIY
    highp float ixiySum=0.0005;//IXIY
    highp float ixixSum=0.0005;//IXIX
    highp float iyiySum=0.0005;//IYIY
    
    highp vec2 offset=vec2(1.0/width,1.0/height);
    
    highp vec4 temp=texture2D(picKeyPoints,coordinate);
    
    highp vec2 cood=vec2(2.0*(temp.x*256.0+temp.y),2.0*(temp.z*256.0+temp.w));
    
    /*
    for (int k=0; k<5; ++k) {//iteration times
        
        for(int i=-10;i<11;++i){
            for(int j=-10;j<11;++j){
                highp vec2 tempCoord=cood+offset*vec2(i,j);
                highp vec4 tempIX=texture2D(picIX,tempCoord);
                highp vec4 tempIY=texture2D(picIY,tempCoord);
                highp vec4 tempI=texture2D(picDiff,tempCoord);
                
                iixSum+=(tempI.x-0.5)*(tempIX.x-0.5);
                iiySum+=(tempI.x-0.5)*(tempIY.x-0.5);
                ixiySum+=(tempIX.x-0.5)*(tempIY.x-0.5);
                ixixSum+=(tempIX.x-0.5)*(tempIX.x-0.5);
                iyiySum+=(tempIY.x-0.5)*(tempIY.x-0.5);
            }
        }
        
        highp float A=ixixSum*iyiySum-ixiySum*ixiySum;
        highp float deltaWidth=(iyiySum*iixSum-ixiySum*iiySum)/A;
        highp float deltaHeight=(ixixSum*iiySum-ixiySum*iixSum)/A;
        
        cood+=vec2(deltaWidth,deltaHeight);
    }
    
    cood*=vec2(width,height);*/
    gl_FragColor=vec4(cood.x,cood.y,texture2D(picIX,cood).x,texture2D(picIY,cood).x);
    //gl_FragColor=vec4(floor(cood.x)/256.0,cood.x-floor(cood.x),floor(cood.y)/256.0,cood.y-floor(cood.y));
}