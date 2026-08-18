// ==================== Liquid Glass ==================== //
//
// A real refractive glass shader, not a translucent overlay.
//
// It receives whatever is rendered behind it as `uBackdrop` (Flutter binds
// the backdrop automatically when this is used via ImageFilter.shader
// inside a BackdropFilter) and physically bends those pixels:
//
//   * a rounded-rect signed distance field defines the pane's shape;
//   * the SDF's gradient is used as a surface normal, so light bends hard
//     at the rim and passes straight through the middle - which is exactly
//     what makes real glass read as glass rather than as frosting;
//   * R/G/B are sampled at slightly different offsets, producing the faint
//     chromatic fringing you see at the edge of a real lens;
//   * a specular band is added where the surface normal faces the light.
//
// Requires Impeller (default on Android 10+ / iOS).

#include <flutter/runtime_effect.glsl>

// ImageFilter.shader requires the first uniform to be a vec2.
uniform vec2 uSize;        // layer size, logical px
uniform vec4 uRect;        // pane rect within the layer: x, y, w, h
uniform vec2 uRadiusEdge;  // x = corner radius, y = edge falloff width
uniform vec4 uOptics;      // x = refraction, y = dispersion,
                           // z = light angle (rad), w = specular strength
uniform vec4 uTint;        // rgb = tint colour, a = tint amount

uniform sampler2D uBackdrop;

out vec4 fragColor;

// Signed distance to a rounded rectangle centred on the origin.
float sdRoundRect(vec2 p, vec2 halfSize, float r) {
  vec2 q = abs(p) - halfSize + r;
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

vec2 backdropUv(vec2 frag) {
  vec2 uv = frag / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return uv;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;

  vec2 center = uRect.xy + uRect.zw * 0.5;
  vec2 halfSize = uRect.zw * 0.5;
  vec2 p = frag - center;

  float radius = uRadiusEdge.x;
  float edgeWidth = max(uRadiusEdge.y, 1.0);

  float d = sdRoundRect(p, halfSize, radius);

  // Outside the pane the backdrop passes through untouched.
  if (d > 0.0) {
    fragColor = texture(uBackdrop, backdropUv(frag));
    return;
  }

  // Surface normal from the SDF gradient. Near the rim this points
  // outward strongly; in the flat centre it cancels to almost nothing.
  float e = 1.0;
  vec2 grad = vec2(
    sdRoundRect(p + vec2(e, 0.0), halfSize, radius) -
    sdRoundRect(p - vec2(e, 0.0), halfSize, radius),
    sdRoundRect(p + vec2(0.0, e), halfSize, radius) -
    sdRoundRect(p - vec2(0.0, e), halfSize, radius)
  ) / (2.0 * e);

  // 1 at the rim, 0 in the flat middle.
  float edge = 1.0 - smoothstep(-edgeWidth, 0.0, d);
  float bend = pow(edge, 2.2) * uOptics.x;

  vec2 offset = grad * bend;
  float dispersion = uOptics.y;

  vec3 refracted = vec3(
    texture(uBackdrop, backdropUv(frag - offset * (1.0 + dispersion))).r,
    texture(uBackdrop, backdropUv(frag - offset)).g,
    texture(uBackdrop, backdropUv(frag - offset * (1.0 - dispersion))).b
  );

  // Specular band where the normal faces the light.
  float lightAngle = uOptics.z;
  vec2 lightDir = vec2(cos(lightAngle), sin(lightAngle));
  vec2 n = normalize(grad + vec2(1e-4));
  float spec = pow(max(dot(n, lightDir), 0.0), 6.0) * edge * uOptics.w;

  vec3 color = mix(refracted, uTint.rgb, uTint.a);
  color += spec;

  fragColor = vec4(color, 1.0);
}
