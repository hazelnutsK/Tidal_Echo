#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

// Signed distance to a continuous rounded rectangle. The gradient of this
// field gives us the surface normal used for edge refraction and dispersion.
static float tidalRoundedBoxDistance(
    float2 point,
    float2 halfExtent,
    float radius
) {
    float2 q = abs(point) - halfExtent + radius;
    return length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

static float2 tidalRoundedBoxNormal(
    float2 point,
    float2 halfExtent,
    float radius
) {
    constexpr float epsilon = 0.65;
    float dx = tidalRoundedBoxDistance(point + float2(epsilon, 0.0), halfExtent, radius)
        - tidalRoundedBoxDistance(point - float2(epsilon, 0.0), halfExtent, radius);
    float dy = tidalRoundedBoxDistance(point + float2(0.0, epsilon), halfExtent, radius)
        - tidalRoundedBoxDistance(point - float2(0.0, epsilon), halfExtent, radius);
    float2 gradient = float2(dx, dy);
    float magnitude = length(gradient);
    return magnitude > 0.0001 ? gradient / magnitude : float2(0.0, -1.0);
}

// Post-processes Apple's native Liquid Glass surface. The system material
// supplies the real backdrop sampling; this shader exposes the optical knobs
// that Glass itself intentionally keeps private.
[[ stitchable ]] half4 tidalLiquidGlassOptics(
    float2 position,
    SwiftUI::Layer source,
    float2 size,
    float cornerRadius,
    float strength,
    float dispersion,
    float rimWidth,
    float magnify,
    float blur,
    float opticalSize
) {
    float2 safeSize = max(size, float2(1.0));
    float2 center = safeSize * 0.5;
    float2 halfExtent = max(center - float2(0.75), float2(1.0));
    float radius = clamp(cornerRadius, 1.0, min(halfExtent.x, halfExtent.y));
    float2 localPoint = position - center;
    float distance = tidalRoundedBoxDistance(localPoint, halfExtent, radius);
    float insideDepth = max(-distance, 0.0);
    float transitionPixels = mix(2.0, max(7.0, opticalSize * 0.11), clamp(rimWidth, 0.0, 1.0));
    float edge = 1.0 - smoothstep(0.0, transitionPixels, insideDepth);
    float2 normal = tidalRoundedBoxNormal(localPoint, halfExtent, radius);

    float normalizedStrength = clamp(strength, 0.0, 1.0);
    float normalizedMagnify = clamp(magnify, 0.0, 1.0);
    float normalizedDispersion = clamp(dispersion, 0.0, 1.0);
    float normalizedBlur = clamp(blur, 0.0, 1.0);

    // Pull the sampled backdrop toward the optical center, then bend it along
    // the rounded silhouette normal. Both effects peak at the glass rim.
    float2 magnifyOffset = (center - position) * normalizedMagnify * 0.032 * (0.28 + edge * 0.72);
    float refractionPixels = (0.35 + normalizedStrength * 8.5) * edge;
    float2 samplePoint = position + magnifyOffset - normal * refractionPixels;
    samplePoint = clamp(samplePoint, float2(0.5), safeSize - float2(0.5));

    float blurRadius = normalizedBlur * 2.4;
    half4 base = source.sample(samplePoint) * half(0.42);
    base += source.sample(samplePoint + float2( blurRadius, 0.0)) * half(0.145);
    base += source.sample(samplePoint + float2(-blurRadius, 0.0)) * half(0.145);
    base += source.sample(samplePoint + float2(0.0,  blurRadius)) * half(0.145);
    base += source.sample(samplePoint + float2(0.0, -blurRadius)) * half(0.145);

    // Real chromatic dispersion samples each channel at a slightly different
    // refracted coordinate instead of painting a rainbow border on top.
    float chromaPixels = normalizedDispersion * 3.4 * edge;
    half4 redSample = source.sample(clamp(samplePoint + normal * chromaPixels, float2(0.5), safeSize - float2(0.5)));
    half4 blueSample = source.sample(clamp(samplePoint - normal * chromaPixels, float2(0.5), safeSize - float2(0.5)));
    base.r = mix(base.r, redSample.r, half(normalizedDispersion * edge));
    base.b = mix(base.b, blueSample.b, half(normalizedDispersion * edge));

    // A restrained Fresnel lift keeps the edge readable without the synthetic
    // neon outline of the previous implementation.
    float fresnel = pow(clamp(edge, 0.0, 1.0), mix(1.8, 0.72, clamp(rimWidth, 0.0, 1.0)));
    half3 coolHighlight = half3(0.085h, 0.095h, 0.11h);
    half3 warmHighlight = half3(0.10h, 0.075h, 0.065h);
    half3 highlight = mix(coolHighlight, warmHighlight, half(clamp(normal.x * 0.5 + 0.5, 0.0, 1.0)));
    base.rgb += highlight * half(fresnel * (0.18 + rimWidth * 0.48)) * base.a;

    return base;
}
