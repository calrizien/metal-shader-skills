// Parcel -> mass -> setback -> roof -> facade. Original texture-free city at blue hour.
// 3x3 neighbor checks plus an unvisited-cell distance cap prevent taller remote blocks being skipped.
// Windows are filtered material fields; their emission is illustrative, not global illumination.
// @render time=4.0
// @variant DEBUG_MODE=2
// @variant DEBUG_MODE=3
// @variant DEBUG_MODE=4
// @variant DEBUG_MODE=5
#define DEBUG_MODE 0 // 0 beauty | 2 normals | 3 parcel IDs | 4 steps | 5 window mask
const float PARCEL = 3.6;
const float3 CITY_SUN = normalize(float3(-0.6,0.6,0.4));
const int AA = 1; // set 4 for stills

float4 cityProfile(float2 id) {
    float4 b = buildingProfile(id,float2(2.8,13.0),float2(0.75,1.13));
    if (length(id)<0.5) b=float4(18.0,1.15,1.15,2.0);
    return b;
}

float2 map(float3 p) {
    float2 id=domRepeatId(p.xz,float2(PARCEL));
    float2 local=p.xz-id*PARCEL;
    float2 res=float2(p.y,0.0);
    for(int z=-1;z<=1;z++) for(int x=-1;x<=1;x++) {
        float2 cell=id+float2(float(x),float(z));
        float4 b=cityProfile(cell);
        float3 q=p-float3(cell.x*PARCEL,0.0,cell.y*PARCEL);
        float body=sdRoundBox(q-float3(0.0,b.x*0.38,0.0),float3(b.y,b.x*0.38,b.z)-0.035,0.035);
        float upper=sdRoundBox(q-float3(0.0,b.x*0.83,0.0),float3(b.y*0.72,b.x*0.17,b.z*0.72)-0.025,0.025);
        float podium=sdBox(q-float3(0.0,0.35,0.0),float3(b.y+0.15,0.35,b.z+0.15));
        float d=min(podium,min(body,upper));
        if(b.w>0.5) d=min(d,sdBox(q-float3(0.0,b.x+0.22,0.0),float3(b.y*0.45,0.22,b.z*0.5)));
        if(b.w>1.5) d=min(d,sdCapsule(q,float3(0.0,b.x,0.0),float3(0.0,b.x+1.1,0.0),0.035));
        if(d<res.x)res=float2(d,1.0);
    }
    float unvisited=min(1.5*PARCEL-abs(local.x),1.5*PARCEL-abs(local.y));
    res.x=min(res.x,unvisited);
    return res;
}

float3 citySky(float3 rd) {
    float h=smoothstep(-0.12,0.7,rd.y);
    float3 c=mix(float3(0.10,0.12,0.19),float3(0.012,0.028,0.07),h);
    c+=float3(0.12,0.055,0.025)*pow(max(dot(rd,CITY_SUN),0.0),12.0);
    return c;
}

float3 renderCity(float2 coord) {
    float2 uv=(2.0*coord-resolution.xy)/resolution.y;
    float orbit=0.5+0.035*time;
    float3 ro=float3(32.0*sin(orbit),17.0,32.0*cos(orbit));
    float3 rd=cameraRay(cameraMatrix(ro,float3(0.0,6.0,0.0),0.0),uv,1.85);
    float3 sky=citySky(rd);
    float3 hit=raymarch(ro,rd,0.05,110.0,0.95);
#if DEBUG_MODE == 4
    return debugHeat(hit.z/256.0);
#endif
    if(hit.x<0.0)return sky;
    float3 p=ro+rd*hit.x;
    float3 n=calcNormal(p,max(0.001,hit.x*0.00015));
    float2 id=domRepeatId(p.xz,float2(PARCEL));
    float4 b=cityProfile(id);
    float variation=hash12(id);
    float fp=2.0*hit.x/(resolution.y*1.85);
    fp/=max(abs(dot(n,rd)),0.15);
    float3 albedo=mix(float3(0.16,0.19,0.21),float3(0.32,0.29,0.25),variation);
    float windows=0.0;
    float3 emission=float3(0.0);
    if(hit.y>0.5 && n.y<0.6) {
        float2 facade=float2(abs(n.x)>abs(n.z)?p.z:p.x,p.y);
        float2 grid=facade/float2(0.30,0.43);
        windows=facadeWindowMask(grid,float2(0.62,0.65),float2(fp*3.8,fp*2.5));
        float occupied=step(0.42,hash13(float3(floor(grid+0.5),variation*100.0)));
        float keep=1.0-smoothstep(0.3,1.2,fp/0.30);
        occupied=mix(0.58,occupied,keep);
        float3 glass=float3(0.018,0.035,0.055)+citySky(reflect(rd,n))*0.3;
        albedo=mix(albedo,glass,windows);
        emission=windows*occupied*mix(float3(0.6,0.22,0.055),float3(1.2,0.74,0.33),variation)*0.8;
    } else if(hit.y<0.5) {
        albedo=float3(0.045,0.05,0.06);
        float2 streets=abs(domRepeat(p.xz,float2(PARCEL)));
        float marking=(1.0-smoothstep(0.025,0.025+fp,abs(streets.x-PARCEL*0.5)))
                     *filteredStripes(p.z*1.3,fp*1.3);
        albedo=mix(albedo,float3(0.42,0.32,0.13),marking);
    }
    float ao=calcAO(p,n,0.18);
    float shadow=softShadow(p+n*0.015,CITY_SUN,0.02,20.0,10.0);
    float3 col=shadePBR(n,-rd,CITY_SUN,albedo,0.4,0.15)*float3(0.9,0.75,0.6)*shadow;
    col+=albedo*hemisphereLight(n,float3(0.30,0.43,0.66),float3(0.07,0.065,0.055))*ao;
    col+=emission;
#if DEBUG_MODE == 2
    return n*0.5+0.5;
#elif DEBUG_MODE == 3
    return hash33(float3(id,0.0));
#elif DEBUG_MODE == 5
    return float3(windows);
#endif
    float haze=heightFog(ro,rd,hit.x,0.006,0.055);
    return mix(col,citySky(normalize(float3(rd.x,0.06,rd.z))),haze);
}

void shade(thread float4 &fragColor,float2 fragCoord) {
    float3 col=float3(0.0);
    for(int i=0;i<AA;i++) {
        float3 sampleColor=renderCity(fragCoord+(AA>1?aaOffset(i):float2(0.0)));
#if DEBUG_MODE == 0
        sampleColor=tonemapAgX(sampleColor*1.05);
#endif
        col+=sampleColor/float(AA);
    }
#if DEBUG_MODE == 0
    col=linearToSrgb(col)+ditherTPDF(fragCoord,frame);
#endif
    fragColor=float4(col,1.0);
}
