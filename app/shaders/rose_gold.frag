#version 460 core
#include <flutter/runtime_effect.glsl>
// FLOW field ported from the user's Rose gold export: scale 52,
// distortion 50, swirl 8; four equal-width stops; sRGB via Oklab.
uniform vec2 uSize;
uniform float uTime;
// Four palette stops in sRGB 0..1, so presets can swap without a new shader.
uniform vec3 uC0;
uniform vec3 uC1;
uniform vec3 uC2;
uniform vec3 uC3;
out vec4 fragColor;

float soft(float x) { return smoothstep(0.0,1.0,x); }
vec2 anchor(float i,float t) {
  return .5+.5*vec2(sin(t*(.6+fract(i/3.0)*.9)+i*.37),cos(t*(.8+fract((i+1.0)/4.0))+i*.555));
}
vec3 toLab(vec3 c) {
  vec3 rgb=mix(c/12.92,pow((c+.055)/1.055,vec3(2.4)),step(vec3(.04045),c));
  vec3 lms=pow(vec3(dot(rgb,vec3(.4122214708,.5363325363,.0514459929)),dot(rgb,vec3(.2119034982,.6806995451,.1073969566)),dot(rgb,vec3(.0883024619,.2817188376,.6299787005))),vec3(1.0/3.0));
  return vec3(dot(lms,vec3(.2104542553,.793617785,-.0040720468)),dot(lms,vec3(1.9779984951,-2.428592205,.4505937099)),dot(lms,vec3(.0259040371,.7827717662,-.808675766)));
}
vec3 fromLab(vec3 lab) {
  vec3 x=vec3(lab.x+.3963377774*lab.y+.2158037573*lab.z,lab.x-.1055613458*lab.y-.0638541728*lab.z,lab.x-.0894841775*lab.y-1.291485548*lab.z);
  x=x*x*x;
  vec3 rgb=vec3(dot(x,vec3(4.0767416621,-3.3077115913,.2309699292)),dot(x,vec3(-1.2684380046,2.6097574011,-.3413193965)),dot(x,vec3(-.0041960863,-.7034186147,1.707614701)));
  return clamp(mix(rgb*12.92,1.055*pow(max(rgb,vec3(0.0)),vec3(1.0/2.4))-.055,step(vec3(.0031308),rgb)),0.0,1.0);
}
void main() {
  vec2 p=(FlutterFragCoord().xy/max(uSize,vec2(1.0))-.5)/1.024+.5;
  float edge=soft(length(p-.5));
  for(int i=1;i<=2;i++) {
    float d=float(i);
    p.x+=.5*(1.0-edge)/d*sin(uTime+d*.4*soft(p.y))*cos(.2*uTime+d*2.4*soft(p.y));
    p.y+=.5*(1.0-edge)/d*cos(uTime+d*2.0*soft(p.x));
  }
  float a=-3.0*.08*edge;
  p=mat2(cos(a),sin(a),-sin(a),cos(a))*(p-.5)+.5;
  vec3 sum=vec3(0.0);float weights=0.0;
  for(int i=0;i<4;i++) {
    vec2 delta=p-anchor(float(i),uTime);
    float weight=1.0/(pow(dot(delta,delta),1.75)+.0001);
    vec3 c=i==0?uC0:i==1?uC1:i==2?uC2:uC3;
    sum+=toLab(c)*weight;weights+=weight;
  }
  vec3 col=fromLab(sum/max(weights,.0001));
  // Clean field: no grain overlay on top.
  fragColor=vec4(col,1.0);
}
