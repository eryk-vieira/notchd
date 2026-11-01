#version 440
// An agent's avatar in ASCII (core/AvatarView.qml): a photo (color.png, the
// person's mask in its alpha) and how near each of its points is
// (depth.png), drawn as a grid of cells. Per cell: the photo point behind
// it, moved by the head's turn (parallax through the depth), the mouth and
// the eyelids; a light from each side on the surface the depth describes;
// then a dotted block (or an ASCII glyph) as bright as that. The person's
// outline carries the name's letters; around it, streaks and falling
// glyphs. Transparent where there is nothing, premultiplied.
//
// Compiled by `make shaders` (qsb) into avatar.frag.qsb, which is
// committed: the plugin has no build step.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;        // view size, px
    vec2 cell;       // cell size, px
    float time;      // seconds
    vec2 look;       // head turn: yaw, pitch
    float lightYaw;  // the turn the lights see
    float work;      // 0..1 busy: rows glitch, lines run
    float attn;      // 0..1 waiting for you: a slow pulse
    vec4 rip0;       // a click's wave: x, y (px), start time, strength
    vec4 rip1;
    vec4 rip2;
    vec4 rip3;
    float glyphs;    // glyphs in the atlas
    float nameLen;   // atlas[0 .. nameLen) spell the name
    float rampOff;   // atlas[rampOff .. +10) a density ramp
    float arrowOff;  // atlas[arrowOff .. +6) arrows and marks
    float mode;      // 0 dotted blocks, 1 ASCII glyphs
    float zoom;      // the photo's height over the view's
    vec2 focusUv;    // the photo point (0..1) at the view's centre
    vec2 tex;        // the photo's size, px
    float photoColors; // 0 lit by the theme's lights, 1 the photo's own colors
    vec2 mouthL;     // the lips' corners, photo px
    vec2 mouthR;
    float chin;      // the lips' line to the chin, photo px
    float open;      // 0..1 the jaw's opening
    float openMax;   // the jaw's drop at open = 1, photo px
    float wide;      // the mouth's width (oo < 1 < ee)
    float talk;      // 0..1 speaking: arcs leave the mouth
    vec4 eyeA;       // an eye's corners: outer.xy, inner.xy (photo px)
    vec4 eyeB;
    vec4 lids;       // eye A's upper and lower lid, then eye B's
    float blink;     // 0 open .. 1 shut
    vec4 warm;       // the light from the left
    vec4 cool;       // the light from the right
    vec4 hot;        // highlights
};
layout(binding = 1) uniform sampler2D atlas;
layout(binding = 2) uniform sampler2D colorMap;
layout(binding = 3) uniform sampler2D depthMap;

float hash(float n) { return fract(sin(n) * 43758.5453123); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(c, -s, s, c); }

// Past the photo's bottom edge the body carries on: its last row repeats.
float inside(vec2 uv) { return step(0., uv.x) * step(uv.x, 1.) * step(0., uv.y); }
vec2 clampY(vec2 uv) { return vec2(uv.x, min(uv.y, .998)); }
float depthAt(vec2 uv) { return texture(depthMap, clampY(uv)).r * inside(uv); }
float maskAt(vec2 uv) { return texture(colorMap, clampY(uv)).a * inside(uv); }

// A blink: the upper lid slides down to the lower one. The lid is the skin
// just above the eye stretched over it, a dark lash line on its edge.
// Returns the photo px to read; z: 0 untouched, 1 lid, 2 lash line.
vec3 eyelid(vec2 p, vec4 eye, vec2 h) {
    vec2 a = eye.xy, b = eye.zw, c = (a + b) * .5;
    vec2 ax = normalize(b - a);
    vec2 dn = vec2(-ax.y, ax.x);
    if (dn.y < 0.) dn = -dn;
    float hw = length(b - a) * .5;
    float u = dot(p - c, ax) / hw, w = dot(p - c, dn);
    if (abs(u) >= 1.) return vec3(p, 0.);
    float k = 1. - u * u;
    float up = -h.x * pow(k, .7), lo = h.y * pow(k, .8);
    float lidY = mix(up, lo + 1., blink);
    if (w < up || w > lidY) return vec3(p, 0.);
    if (w > lidY - 2.2) return vec3(p, 2.);
    float f = (w - up) / max(lidY - up, 1e-3);
    return vec3(c + ax * u * hw + dn * (up - 4. - (1. - f) * 5.), 1.);
}
vec3 blinkWarp(vec2 s) {
    if (blink < .01) return vec3(s, 0.);
    vec2 p = s * tex;
    vec3 r = eyelid(p, eyeA, lids.xy);
    if (r.z < .5) r = eyelid(p, eyeB, lids.zw);
    return vec3(r.xy / tex, r.z);
}

// Talking: below the lips' line, the face slides along its own "down".
// Between the lips a gap opens: the photo's own lip line stretched (teeth,
// or a dark crease), darker inside; z in [1, 2) is how deep into it.
// The corners and cheeks stretch, the neck stays.
vec3 mouthWarp(vec2 s) {
    if (open < .002) return vec3(s, 0.);
    vec2 p = s * tex;
    vec2 c = (mouthL + mouthR) * .5;
    vec2 ax = normalize(mouthR - mouthL);
    vec2 dn = vec2(-ax.y, ax.x);
    if (dn.y < 0.) dn = -dn;
    float hw = length(mouthR - mouthL) * .5 * wide;
    float u = dot(p - c, ax), v = dot(p - c, dn);
    if (v < 0.) return vec3(s, 0.);
    float D = open * openMax;
    float x = clamp(abs(u) / hw, 0., 1.);
    float gap = abs(u) < hw ? D * pow(1. - x * x, .6) : 0.;
    if (v < gap) return vec3((p - dn * v * .8) / tex, 1. + clamp(v / gap, 0., .999));
    float jaw = 1. - smoothstep(hw * 1.1, hw * 2.6, abs(u));
    float fade = 1. - smoothstep(chin - 5., chin + 30., v);
    float dd = mix(gap, D * jaw, smoothstep(0., 25., v - gap)) * fade;
    return vec3((p - dn * dd) / tex, 0.);
}

float glyph(float idx, vec2 local) {
    vec2 l = clamp(local, 0., 1.);
    return texture(atlas, vec2((idx + l.x) / glyphs, l.y)).a;
}
// A cell as a "pixel": its level in 7 steps, a fine dot texture, a gap.
float block(vec2 local, vec2 px, float lum) {
    float gap = step(local.x, 1. - 1.4 / cell.x) * step(local.y, 1. - 1.4 / cell.y);
    float dots = mod(floor(px.x) + floor(px.y), 2.);
    float level = floor(lum * 7. + .5) / 7.;
    return gap * level * (.62 + .38 * dots);
}

float ripple(vec4 r, vec2 center, inout vec2 disp) {
    if (r.w <= 0.) return 0.;
    float age = time - r.z;
    if (age < 0. || age > 3.) return 0.;
    vec2 dv = center - r.xy;
    float d = length(dv);
    float w = exp(-pow((d - age * res.y * .9) / (cell.y * 2.5), 2.)) * exp(-age * 1.3) * r.w;
    disp += normalize(dv + 1e-4) * w * cell.y * 1.6;
    return w;
}

void main() {
    vec2 px = qt_TexCoord0 * res;
    vec2 cellId = floor(px / cell);
    vec2 local = fract(px / cell);
    vec2 center = (cellId + .5) * cell;
    float rows = floor(res.y / cell.y);
    float t = time;

    vec2 disp = vec2(0.);
    float ring = ripple(rip0, center, disp) + ripple(rip1, center, disp)
               + ripple(rip2, center, disp) + ripple(rip3, center, disp);
    vec2 glitch = vec2(0.);
    if (hash(cellId.y * 7.13 + floor(t * 9.)) > 1. - .07 * work)
        glitch.x = (hash(cellId.y + floor(t * 9.) * 3.1) - .5) * cell.x * 10.;

    // view -> photo
    vec2 sp = center + disp + glitch;
    float aspect = tex.x / tex.y;
    vec2 uv = (sp - .5 * res) / (res.y * zoom);
    uv = vec2(uv.x / aspect, uv.y) + focusUv;

    // The head's turn: near points travel further than far ones.
    vec2 shift = vec2(-look.x, look.y) * .09;
    vec2 s = uv;
    for (int i = 0; i < 8; i++) s = uv + shift * (depthAt(s) - .45);

    vec3 mw = mouthWarp(s);
    float cavity = mw.z;
    s = mw.xy;
    vec3 bw = blinkWarp(s);
    s = bw.xy;
    float lidCode = bw.z;
    float m = cavity > 0. ? 1. : maskAt(s);
    vec3 col = vec3(0.);
    float ink = 0.;

    if (m > .5) {
        vec4 photo = texture(colorMap, clampY(s));
        float z = depthAt(s);
        if (cavity > 0.) { photo.rgb *= mix(.8, .32, sin(3.14159 * (cavity - 1.))); z -= .04; }
        if (lidCode > 1.5) photo.rgb = vec3(.07, .04, .04);
        else if (lidCode > .5) photo.rgb *= .9;
        vec2 e = vec2(2.5 / tex.x, 0.);
        vec2 f = vec2(0., 2.5 / tex.y);
        float dx = depthAt(s + e) - depthAt(s - e);
        float dy = depthAt(s + f) - depthAt(s - f);
        vec3 n = normalize(vec3(-dx * 22., dy * 22., 1.));
        n.xz = rot(-lightYaw * .6) * n.xz;

        float key  = pow(max(dot(n, normalize(vec3(-1., .35, .45))), 0.), 1.3);
        float fill = pow(max(dot(n, normalize(vec3(1., .1, .3))), 0.), 1.6);
        float albedo = smoothstep(.04, .78, dot(photo.rgb, vec3(.3, .55, .15)));
        float shade = albedo * (.22 + key * 1.2 + fill * 1.1);

        // Contours of the depth drift over the face like a scanned mesh,
        // and one bright band scans down it.
        float speed = .2 + work * 1.4;
        float contour = smoothstep(.9, 1., fract(z * 9. - t * speed)) * .45;
        float scan = smoothstep(.93, 1., fract(s.y * 1.6 - t * speed * .6));
        float lines = max(contour, scan) * smoothstep(.2, .5, z);

        vec3 relit = (warm.rgb * key * 1.7 + cool.rgb * fill * 1.8 + warm.rgb * .12) * (.3 + albedo * 1.5);
        vec3 real = photo.rgb * (.85 + key * .7 + fill * .45);
        col = mix(relit, real * 1.3, photoColors);
        col = mix(col, hot.rgb, lines * .5 + ring * .8);
        float lum = clamp(pow(shade * 1.5, .8) + lines * .3 + ring * .6 + attn * .12 * (.5 + .5 * sin(t * 5.)), 0., 1.);

        // The outline and the depth's jumps (hair over the face) carry the name.
        float mEdge = abs(maskAt(s + e * 1.6) - maskAt(s - e * 1.6)) + abs(maskAt(s + f * 1.6) - maskAt(s - f * 1.6));
        float dEdge = length(vec2(dx, dy));
        bool edge = (mEdge > .35 || dEdge > .11) && hash2(cellId + floor(t * (2. + work * 10.))) > .3;
        if (edge) {
            float li = mod(cellId.y + floor(t * (1. + work * 6.)), nameLen);
            float warmSide = step(n.x, 0.);
            col = mix(mix(cool.rgb * 1.3, hot.rgb * 1.2, warmSide), photo.rgb * 1.6, photoColors * .6);
            ink = glyph(li, local);
        } else if (mode < .5) {
            ink = block(local, px, max(lum, .07));
        } else {
            ink = glyph(rampOff + floor(clamp(lum, 0., .999) * 10.), local);
            col *= 1.3;
        }
    } else {
        // Streaks up and to the right.
        float along  = center.x - center.y;
        float across = center.x + center.y;
        float band = floor(across / (cell.x * 1.6));
        float lit = step(1. - (.1 + work * .12 + ring * .3), hash(band * 1.37));
        float spd = .05 + hash(band + 4.1) * .12 + work * .1;
        float len = .08 + hash(band + 9.2) * .22;
        float pos = fract(along / (res.x + res.y) * 1.2 + t * spd + hash(band + 2.3));
        float streak = lit * step(pos, len) * (pos / len) * (.25 + .5 * hash(band + 5.5));
        vec3 sc = hash(band + 7.7) > .45 ? cool.rgb : warm.rgb;

        // Glyphs falling down the sides.
        float side = smoothstep(.18, .42, abs(center.x / res.x - .5));
        float fall = 0., fallIdx = 0.;
        if (hash(cellId.x * 3.31 + 11.) > .93 - work * .04) {
            float headRow = fract(t * (.08 + hash(cellId.x) * .2) + hash(cellId.x + 1.)) * rows * 1.6;
            float k = headRow - cellId.y;
            if (k > 0. && k < 6. + hash(cellId.x + 3.) * 10.) {
                fall = (1. - k / 16.) * side;
                fallIdx = hash(cellId.y + floor(t * 4.)) > .5 ? mod(cellId.y, nameLen) : arrowOff + mod(cellId.y, 6.);
            }
        }
        // Scraps of the name.
        vec2 chunk = vec2(floor(cellId.x / 7.), cellId.y);
        float scrap = step(.985 - work * .01, hash2(chunk + floor(t * 1.5) * .37));

        if (fall > .01) {
            col = (hash(cellId.x + 8.) > .5 ? cool.rgb : warm.rgb) * (.5 + fall);
            ink = glyph(fallIdx, local);
        } else if (scrap > 0.) {
            col = (hash2(chunk) > .5 ? warm.rgb : cool.rgb) * .45;
            ink = glyph(mod(cellId.x, nameLen), local);
        } else if (streak > 0.) {
            col = sc;
            ink = mode < .5 ? block(local, px, streak) : glyph(rampOff + floor(streak * 9.), local);
        }
        // The voice: arcs leave the mouth, the way the face looks.
        vec2 mc = (mouthL + mouthR) * .5 / tex;
        vec2 ms = (mc - focusUv) * vec2(aspect, 1.) * res.y * zoom + .5 * res;
        vec2 dv = center - ms;
        float dist = length(dv);
        float cone = smoothstep(.35, .9, dv.x / (dist + 1e-4));
        float wave = smoothstep(.8, 1., fract(dist / (cell.y * 2.4) - t * 2.2));
        float voice = talk * cone * wave * exp(-dist / (res.y * .45)) * smoothstep(cell.y * 3., cell.y * 6., dist);
        if (voice > .05 && ink < .05) {
            col = mix(cool.rgb, hot.rgb, open);
            ink = mode < .5 ? block(local, px, voice) : glyph(rampOff + floor(voice * 9.), local);
        }
        col += cool.rgb * ring * .5;
        ink = max(ink, ring * .35 * mod(floor(px.x) + floor(px.y), 2.));
    }

    float vign = 1. - .55 * pow(length((px / res - .5) * vec2(1.1, 1.3)), 2.);
    float a = clamp(ink * vign, 0., 1.);
    fragColor = vec4(clamp(col, 0., 1.) * a, a) * qt_Opacity;
}
