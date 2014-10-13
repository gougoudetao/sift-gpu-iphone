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
    
    highp vec4 content=texture2D(picKeyPoints,coordinate);//取得坐标点组成纹理内容
    
    highp vec2 cood=vec2(2.0*(content.x*256.0+content.y),2.0*(content.z*256.0+content.w));//将纹理内容解释成图像坐标除以256
    
    highp vec2 textureCood=vec2(cood.y*256.0,cood.x*256.0)*offset;//将图像坐标转化成纹理坐标，我不知道抽什么风这里坐标x和y是相反的！
    
    highp float u,v;
    for (int k=0; k<5; ++k) {//iteration times
        
        for(int i=-10;i<11;++i){
            for(int j=-10;j<11;++j){
                highp vec2 tempCoord=textureCood+offset*vec2(j,i);//纹理坐标
                highp float tempIX=(texture2D(picIX,tempCoord).x-0.5)*256.0;//像素值
                highp float tempIY=(texture2D(picIY,tempCoord).x-0.5)*256.0;
                highp float tempI=(texture2D(picDiff,tempCoord).x-0.5)*256.0;
                
                iixSum+=tempI*tempIX;
                iiySum+=tempI*tempIY;
                ixiySum+=tempIX*tempIY;
                ixixSum+=tempIX*tempIX;
                iyiySum+=tempIY*tempIY;
            }
        }
        
        highp float A=ixixSum*iyiySum-ixiySum*ixiySum;
        u=(iyiySum*iixSum-ixiySum*iiySum)/A;//像素值
        v=(ixixSum*iiySum-ixiySum*iixSum)/A;//像素值
        
        if(abs(u)<1.0&&abs(v)<1.0) break;
        cood+=vec2(u/256.0,v/256.0);
        textureCood=vec2(cood.y*256.0,cood.x*256.0)*offset;
    }
        
    gl_FragColor=vec4(floor(cood.x/256.0),cood.x-floor(cood.x/256.0),floor(cood.y/256.0),cood.y-floor(cood.y/256.0));
}