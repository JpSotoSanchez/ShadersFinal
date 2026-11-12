// Espada láser con desvanecido (URP 17, Unity 6)
//
// - Núcleo blanco caliente + halo de color que se vuelve transparente hacia el
//   borde de la hoja (fresnel).
// - Ruido animado que hace vibrar la energía y recorta la transparencia.
// - Vanish: la hoja se retrae de la punta a la base con un borde irregular
//   de ruido y un filo brillante.
//
// Pensado para un cilindro o cápsula. Usa colores HDR: con Bloom en el Volume
// la hoja "sangra" luz.
Shader "Showcase/Laser Sword Vanish"
{
    Properties
    {
        [Header(Color)]
        [HDR] _CoreColor ("Color del núcleo", Color) = (4, 4, 4, 1)
        [HDR] _GlowColor ("Color del halo", Color) = (0.1, 1.6, 4, 1)
        _CoreWidth ("Ancho del núcleo", Range(0, 1)) = 0.45
        _GlowFalloff ("Caída del halo", Range(0.2, 6)) = 1.2
        _Opacity ("Opacidad", Range(0, 1)) = 1
        _Additive ("Mezcla aditiva", Range(0, 1)) = 0.8

        [Header(Ruido)]
        _NoiseScale ("Escala del ruido", Range(0.5, 30)) = 6
        _NoiseSpeed ("Velocidad del ruido", Range(0, 10)) = 2.5
        _Flicker ("Vibración de energía", Range(0, 1)) = 0.35
        _NoiseAlpha ("Ruido en transparencia", Range(0, 1)) = 0.25

        [Header(Vanish)]
        _Vanish ("Vanish", Range(0, 1)) = 0
        [Enum(X,0,Y,1,Z,2)] _Axis ("Eje de la hoja", Float) = 1
        _BladeBase ("Base de la hoja (espacio objeto)", Float) = -1
        _BladeTip ("Punta de la hoja (espacio objeto)", Float) = 1
        _NoiseEdge ("Irregularidad del corte", Range(0, 1)) = 0.25
        _EdgeWidth ("Ancho del filo", Range(0.001, 0.5)) = 0.08
        [HDR] _EdgeColor ("Color del filo", Color) = (6, 6, 6, 1)

        [Header(Auto animar)]
        [Toggle] _AutoAnimate ("Animar vanish solo", Float) = 0
        _AutoSpeed ("Velocidad", Range(0.1, 10)) = 1.5

        [Header(Render)]
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull", Float) = 2
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Transparent"
            "IgnoreProjector" = "True"
        }

        Pass
        {
            Name "ForwardUnlit"
            Tags { "LightMode" = "UniversalForward" }

            // Color premultiplicado: _Additive mueve la mezcla entre alpha normal y aditiva.
            Blend One OneMinusSrcAlpha
            ZWrite Off
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "../Common/ShowcaseCommon.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _CoreColor;
                half4 _GlowColor;
                half4 _EdgeColor;
                float _CoreWidth;
                float _GlowFalloff;
                float _Opacity;
                float _Additive;
                float _NoiseScale;
                float _NoiseSpeed;
                float _Flicker;
                float _NoiseAlpha;
                float _Vanish;
                float _Axis;
                float _BladeBase;
                float _BladeTip;
                float _NoiseEdge;
                float _EdgeWidth;
                float _AutoAnimate;
                float _AutoSpeed;
                float _Cull;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionOS : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings Vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                output.positionOS = input.positionOS.xyz;
                output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                output.positionCS = TransformWorldToHClip(output.positionWS);
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);

                float time = _Time.y;
                float3 axisDir = AxisVector(_Axis);

                // Ruido que viaja de la base a la punta.
                float3 noisePos = input.positionOS * _NoiseScale - axisDir * time * _NoiseSpeed;
                float noiseValue = Fbm3D(noisePos);

                // --- Vanish: la hoja se retrae hacia la base ---
                float along = AxisGradient(input.positionOS, _Axis, _BladeBase, _BladeTip);
                float cutNoise = (Fbm3D(input.positionOS * _NoiseScale * 0.6 + 7.3) - 0.5) * _NoiseEdge;
                float vanish = ResolveVanish(_Vanish, _AutoAnimate, _AutoSpeed, time);
                float margin = _NoiseEdge * 0.5 + 0.001;
                float cut = lerp(1.0 + margin + _EdgeWidth, -margin, vanish);
                float visible = cut - (along + cutNoise);
                clip(visible);
                float edge = 1.0 - saturate(visible / _EdgeWidth);

                // --- Forma de la hoja: núcleo + halo según el ángulo de vista ---
                half3 normalWS = normalize(input.normalWS);
                half3 viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
                half facing = abs(dot(normalWS, viewDirWS));

                // 0 en el centro de la hoja, 1 en la silueta.
                half radial = sqrt(saturate(1.0 - facing * facing));
                half core = 1.0 - smoothstep(_CoreWidth * 0.5, max(_CoreWidth, 0.01), radial);
                half glow = pow(saturate(1.0 - radial), _GlowFalloff);

                half flicker = 1.0 + (noiseValue - 0.5) * 2.0 * _Flicker;
                half3 color = lerp(_GlowColor.rgb, _CoreColor.rgb, core) * flicker;
                color = lerp(color, _EdgeColor.rgb, edge);

                half alpha = saturate(glow * lerp(1.0, noiseValue * 1.6, _NoiseAlpha));
                alpha = saturate(max(alpha, edge)) * _Opacity;

                return half4(color * alpha, alpha * (1.0 - _Additive));
            }
            ENDHLSL
        }
    }

    FallBack Off
}
