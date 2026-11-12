#ifndef SHOWCASE_COMMON_INCLUDED
#define SHOWCASE_COMMON_INCLUDED

// Funciones compartidas por los shaders del showcase:
// dither ordenado (Bayer), ruido 3D y utilidades de desvanecido.
// No depende de texturas: todo es procedural.

// ---------------------------------------------------------------------------
// Dither ordenado (matriz de Bayer calculada aritméticamente)
// Devuelve un umbral en (0,1) que se repite cada 2, 4 u 8 píxeles.
// ---------------------------------------------------------------------------
float Bayer2(float2 a)
{
    a = floor(a);
    return frac(a.x * 0.5 + a.y * a.y * 0.75);
}

float Bayer4(float2 a)
{
    return Bayer2(0.5 * a) * 0.25 + Bayer2(a);
}

float Bayer8(float2 a)
{
    return Bayer4(0.5 * a) * 0.25 + Bayer2(a);
}

// Umbral de dither para un pixel de pantalla.
// pixelCoord: SV_POSITION.xy   scale: tamaño de cada "punto" en píxeles.
// El resultado queda centrado en cada escalón: (k + 0.5) / 64.
float DitherThreshold(float2 pixelCoord, float scale)
{
    float2 p = floor(pixelCoord / max(scale, 1.0));
    return Bayer8(p) + 0.5 / 64.0;
}

// ---------------------------------------------------------------------------
// Ruido de valor 3D + fBm (en espacio de objeto, no necesita UVs)
// ---------------------------------------------------------------------------
float Hash31(float3 p)
{
    p = frac(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return frac((p.x + p.y) * p.z);
}

float ValueNoise3D(float3 p)
{
    float3 i = floor(p);
    float3 f = frac(p);
    float3 u = f * f * (3.0 - 2.0 * f);

    float n000 = Hash31(i);
    float n100 = Hash31(i + float3(1.0, 0.0, 0.0));
    float n010 = Hash31(i + float3(0.0, 1.0, 0.0));
    float n110 = Hash31(i + float3(1.0, 1.0, 0.0));
    float n001 = Hash31(i + float3(0.0, 0.0, 1.0));
    float n101 = Hash31(i + float3(1.0, 0.0, 1.0));
    float n011 = Hash31(i + float3(0.0, 1.0, 1.0));
    float n111 = Hash31(i + float3(1.0, 1.0, 1.0));

    float nx00 = lerp(n000, n100, u.x);
    float nx10 = lerp(n010, n110, u.x);
    float nx01 = lerp(n001, n101, u.x);
    float nx11 = lerp(n011, n111, u.x);

    return lerp(lerp(nx00, nx10, u.y), lerp(nx01, nx11, u.y), u.z);
}

// Tres octavas, resultado en [0,1]. La suma cruda casi nunca sale de
// 0.15..0.85, así que se estira para aprovechar todo el rango.
float Fbm3D(float3 p)
{
    float sum = 0.5 * ValueNoise3D(p);
    sum += 0.25 * ValueNoise3D(p * 2.03 + 17.1);
    sum += 0.125 * ValueNoise3D(p * 4.01 + 43.7);
    return saturate((sum / 0.875 - 0.15) / 0.7);
}

// ---------------------------------------------------------------------------
// Utilidades de desvanecido
// ---------------------------------------------------------------------------

// Coordenada del eje elegido (0 = X, 1 = Y, 2 = Z) en espacio de objeto.
float AxisCoordinate(float3 positionOS, float axis)
{
    float3 mask = float3(step(axis, 0.5), step(abs(axis - 1.0), 0.5), step(1.5, axis));
    return dot(positionOS, mask);
}

// Vector unitario del eje elegido.
float3 AxisVector(float axis)
{
    return float3(step(axis, 0.5), step(abs(axis - 1.0), 0.5), step(1.5, axis));
}

// Posición normalizada a lo largo del eje: 0 en 'from', 1 en 'to'.
float AxisGradient(float3 positionOS, float axis, float from, float to)
{
    float range = to - from;
    range = abs(range) < 1e-5 ? 1e-5 : range;
    return saturate((AxisCoordinate(positionOS, axis) - from) / range);
}

// Valor de desvanecido final: el slider manual o, si autoAnimate está activo,
// un vaivén suave 0 -> 1 -> 0 para poder lucir el efecto sin scripts.
float ResolveVanish(float vanish, float autoAnimate, float autoSpeed, float time)
{
    float loop = 0.5 - 0.5 * cos(time * autoSpeed);
    return saturate(lerp(vanish, loop, step(0.5, autoAnimate)));
}

#endif
