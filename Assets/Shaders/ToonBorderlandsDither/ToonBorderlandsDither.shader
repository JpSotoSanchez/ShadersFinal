// Toon + Borderlands + Dither (URP 17, Unity 6)
//
// - Toon: la luz se corta en bandas planas en lugar de un degradado.
// - Dither: la frontera entre bandas se resuelve con un patrón de Bayer en
//   pantalla (trama de puntos tipo cómic) en vez de un corte limpio.
// - Borderlands: contorno grueso de tinta (casco invertido) + líneas de tinta
//   interiores donde la superficie se aleja de la cámara.
Shader "Showcase/Toon Borderlands Dither"
{
    Properties
    {
        [Header(Base)]
        [MainTexture] _BaseMap ("Textura", 2D) = "white" {}
        [MainColor] _BaseColor ("Color", Color) = (1, 1, 1, 1)

        [Header(Toon)]
        _ShadowColor ("Color de sombra", Color) = (0.28, 0.24, 0.38, 1)
        [IntRange] _Steps ("Bandas de luz", Range(1, 6)) = 2
        _AmbientStrength ("Luz ambiental", Range(0, 1)) = 0.35

        [Header(Dither)]
        _DitherAmount ("Dither entre bandas", Range(0, 1)) = 0.6
        _DitherScale ("Tamaño del punto (px)", Range(1, 8)) = 2

        [Header(Brillo especular)]
        [HDR] _SpecColor ("Color del brillo", Color) = (1, 1, 1, 1)
        _SpecSize ("Tamaño del brillo", Range(0, 1)) = 0.15
        _SpecIntensity ("Intensidad del brillo", Range(0, 1)) = 0

        [Header(Tinta Borderlands)]
        _OutlineColor ("Color de tinta", Color) = (0.02, 0.02, 0.03, 1)
        _OutlineWidth ("Grosor del contorno (px)", Range(0, 12)) = 4
        _InkThreshold ("Umbral de tinta interior", Range(0, 1)) = 0.78
        _InkStrength ("Fuerza de tinta interior", Range(0, 1)) = 0.6
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Geometry"
        }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "../Common/ShowcaseCommon.hlsl"

        TEXTURE2D(_BaseMap);
        SAMPLER(sampler_BaseMap);

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _BaseColor;
            half4 _ShadowColor;
            half4 _SpecColor;
            half4 _OutlineColor;
            float _Steps;
            float _AmbientStrength;
            float _DitherAmount;
            float _DitherScale;
            float _SpecSize;
            float _SpecIntensity;
            float _OutlineWidth;
            float _InkThreshold;
            float _InkStrength;
        CBUFFER_END
        ENDHLSL

        // -------------------------------------------------------------------
        // Luz toon con dither
        // -------------------------------------------------------------------
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            Cull Back
            ZWrite On

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _CLUSTER_LIGHT_LOOP
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float fogFactor : TEXCOORD3;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings Vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                VertexPositionInputs positions = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = positions.positionCS;
                output.positionWS = positions.positionWS;
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                output.fogFactor = ComputeFogFactor(positions.positionCS.z);
                return output;
            }

            // Corta la luz en bandas. 'jitter' (-0.5..0.5) desplaza el corte
            // pixel a pixel, lo que convierte la frontera en una trama de puntos.
            half ToonBands(half lightAmount, half jitter)
            {
                half steps = max(_Steps, 1.0);
                return saturate(floor(lightAmount * steps + 0.5 + jitter * _DitherAmount) / steps);
            }

            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);

                half4 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor;
                half3 normalWS = normalize(input.normalWS);
                half3 viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWS);

                // El bucle de luces adicionales de Forward+ necesita estos datos.
                InputData inputData = (InputData)0;
                inputData.positionWS = input.positionWS;
                inputData.normalWS = normalWS;
                inputData.viewDirectionWS = viewDirWS;
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);

                half jitter = DitherThreshold(input.positionCS.xy, _DitherScale) - 0.5;

                // Luz principal
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                half mainLit = saturate(dot(normalWS, mainLight.direction))
                    * mainLight.shadowAttenuation * mainLight.distanceAttenuation;
                half mainBand = ToonBands(mainLit, jitter);

                half3 shadowTint = lerp(_ShadowColor.rgb, half3(1.0, 1.0, 1.0), mainBand);
                half3 color = albedo.rgb * shadowTint * mainLight.color;

                // Brillo especular plano
                half3 halfDir = normalize(mainLight.direction + viewDirWS);
                half specTerm = pow(saturate(dot(normalWS, halfDir)), lerp(256.0, 8.0, _SpecSize));
                half specMask = step(0.5, specTerm + jitter * _DitherAmount * 0.5) * mainBand;
                color += _SpecColor.rgb * mainLight.color * specMask * _SpecIntensity;

                // Luces adicionales (también en bandas)
                #if defined(_ADDITIONAL_LIGHTS)
                uint lightCount = GetAdditionalLightsCount();
                LIGHT_LOOP_BEGIN(lightCount)
                    Light light = GetAdditionalLight(lightIndex, input.positionWS, half4(1.0, 1.0, 1.0, 1.0));
                    half lightAmount = saturate(dot(normalWS, light.direction))
                        * light.shadowAttenuation * light.distanceAttenuation;
                    color += albedo.rgb * light.color * ToonBands(lightAmount, jitter);
                LIGHT_LOOP_END
                #endif

                // Ambiente
                color += albedo.rgb * SampleSH(normalWS) * _AmbientStrength;

                // Tinta interior: se oscurece donde la superficie se aleja de la cámara.
                half fresnel = 1.0 - saturate(dot(normalWS, viewDirWS));
                half ink = step(_InkThreshold, fresnel + jitter * _DitherAmount * 0.2);
                color = lerp(color, _OutlineColor.rgb, ink * _InkStrength);

                color = MixFog(color, input.fogFactor);
                return half4(color, 1.0);
            }
            ENDHLSL
        }

        // -------------------------------------------------------------------
        // Contorno: se dibujan las caras traseras infladas a lo largo de la normal
        // -------------------------------------------------------------------
        Pass
        {
            Name "Outline"
            Tags { "LightMode" = "SRPDefaultUnlit" }

            Cull Front
            ZWrite On

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float fogFactor : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings Vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                float4 positionCS = TransformObjectToHClip(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                float3 normalCS = TransformWorldToHClipDir(normalWS);

                // Grosor constante en píxeles, sin importar la distancia.
                float2 direction = normalCS.xy / max(length(normalCS.xy), 1e-5);
                positionCS.xy += direction * (_OutlineWidth * 2.0 / _ScreenParams.xy) * positionCS.w;

                output.positionCS = positionCS;
                output.fogFactor = ComputeFogFactor(positionCS.z);
                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                half3 color = MixFog(_OutlineColor.rgb, input.fogFactor);
                return half4(color, 1.0);
            }
            ENDHLSL
        }

        // -------------------------------------------------------------------
        // Sombras
        // -------------------------------------------------------------------
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings Vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);

                #if defined(_CASTING_PUNCTUAL_LIGHT_SHADOW)
                float3 lightDirectionWS = normalize(_LightPosition - positionWS);
                #else
                float3 lightDirectionWS = _LightDirection;
                #endif

                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
                output.positionCS = ApplyShadowClamping(positionCS);
                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                return 0;
            }
            ENDHLSL
        }

        // -------------------------------------------------------------------
        // Profundidad
        // -------------------------------------------------------------------
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask R
            Cull Back

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_instancing

            struct Attributes
            {
                float4 positionOS : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings Vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                return input.positionCS.z;
            }
            ENDHLSL
        }

        // -------------------------------------------------------------------
        // Profundidad + normales (lo usan SSAO y otros efectos de pantalla)
        // -------------------------------------------------------------------
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }

            ZWrite On
            Cull Back

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile_instancing

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings Vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                return half4(normalize(input.normalWS), 0.0);
            }
            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
