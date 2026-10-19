#version 460 core
#include <flutter/runtime_effect.glsl>
// "Chroma blur" scene change from the user's reference: a soft diagonal band
// with two light fringes sweeps from bottom-left to top-right.
uniform vec2 uRes;
uniform float uTime;
uniform float uProgress;
uniform float uAlpha;
uniform float uMax;
uniform float uWidth;
uniform vec3 uA;
uniform vec3 uB;
uniform vec3 uFringe;
out vec4 fragColor;

float hash(vec2 p){ return fract(sin(dot(p, vec2(41.0, 289.0))) * 45758.5453); }
float noise(vec2 p){
  vec2 i = floor(p), f = fract(p);
  float a = hash(i), b = hash(i + vec2(1.0, 0.0)), c = hash(i + vec2(0.0, 1.0)), d = hash(i + vec2(1.0, 1.0));
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}
void main(){
  vec2 frag = FlutterFragCoord().xy;
  // Flutter's origin is top-left; the reference is bottom-left.
  vec2 uv = vec2(frag.x / uRes.x, 1.0 - frag.y / uRes.y);
  float p = smoothstep(0.0, 1.0, uProgress);
  float n = noise(uv * 10.0 + vec2(uTime * 0.28, -uTime * 0.18));
  float wave = sin((uv.y + n * 0.12) * 28.0 + uTime * 2.2) * 0.018;
  float d = uv.x * 0.62 + uv.y * 0.38 + wave - (p * 1.42 - 0.2);
  float curtain = exp(-d * d * uWidth);
  float grain = noise(uv * 34.0 + uTime * 0.18) * 0.055;
  float k = uWidth * 1.53;
  float chroma = exp(-(d + 0.045) * (d + 0.045) * k) + exp(-(d - 0.045) * (d - 0.045) * k);
  vec3 color = mix(uA, uB, smoothstep(-0.18, 0.18, sin((uv.y + n) * 6.2832)));
  color = mix(color, uFringe, smoothstep(0.2, 1.0, chroma) * 0.34);
  color = mix(color, uFringe, 0.16);
  float alpha = (curtain * 0.72 + chroma * 0.18 + grain * curtain)
    * smoothstep(0.0, 0.16, p) * smoothstep(1.0, 0.74, p) * uAlpha;
  alpha = clamp(alpha, 0.0, uMax);
  fragColor = vec4(color * alpha, alpha);
}
