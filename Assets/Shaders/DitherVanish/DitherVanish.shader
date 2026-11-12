// Dither + Vanish (URP 17, Unity 6)
//
// El objeto es opaco y se desvanece "apagando" píxeles con un patrón de Bayer
// (transparencia de rejilla), así que no hay problemas de orden de dibujado
// y sigue proyectando y recibiendo sombras mientras desaparece.
//
// El desvanecido puede ser parejo, seguir manchas de ruido, o barrer el objeto
// a lo largo de un eje. El frente del desvanecido brilla con _EdgeColor.
Shader "Showcase/Dither Vanish"
{
    Properties
    {
        [Header(Base)]
        [MainTexture] _BaseMap ("Textura", 2D) = "white" {}
        [MainColor] _BaseColor ("Color", Color) = (1, 1, 1, 1)
        _ShadowColor ("Color de sombra", Color) = (0.25, 0.25, 0.35, 1)
        _AmbientStrength ("Luz ambiental", Range(0, 1)) = 0.4

        [Header(Vanish)]
        _Vanish ("Vanish", Range(0, 1)) = 0
        _DitherScale ("Tamaño del punto (px)", Range(1, 8)) = 2
        _DitherBand ("Suavidad del dither", Range(0.01, 1)) = 0.35

        [Header(Ruido y barrido)]
        _NoiseAmount ("Seguir manchas de ruido", Range(0, 1)) = 0.6
        _NoiseScale ("Escala del ruido", Range(0.5, 30)) = 4
        _Directional ("Barrido por eje", Range(0, 1)) = 0
        [Enum(X,0,Y,1,Z,2)] _Axis ("Eje del barrido", Float) = 1
        _AxisStart ("Donde empieza (espacio objeto)", Float) = 0.5
        _AxisEnd ("Donde termina (espacio objeto)", Float) = -0.5

        [Header(Borde)]
        [HDR] _EdgeColor ("Color del borde", Color) = (0.2, 2.5, 4, 1)
        _EdgeWidth ("Ancho del borde", Range(0, 0.5)) = 0.12

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
            "RenderType" = "TransparentCutout"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "AlphaTest"
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
            half4 _EdgeColor;
            float _AmbientStrength;
            float _Vanish;
            float _DitherScale;
            float _DitherBand;
            float _NoiseAmount;
            float _NoiseScale;
            float _Directional;
            float _Axis;
            float _AxisStart;
            float _AxisEnd;
            float _EdgeWidth;
            float _AutoAnimate;
            float _AutoSpeed;
            float _Cull;
        CBUFFER_END

        // Distancia al frente del desvanecido para un punto del objeto:
        //   <= 0  ya desapareció
        //   0..1  zona de transición
        // Con _Vanish = 0 todo el objeto queda por encima de la transición y con
        // _Vanish = 1 todo queda por debajo.
        float VanishDistance(float3 positionOS)
        {
            float noiseValue = Fbm3D(positionOS * _NoiseScale);
            float sweep = AxisGradient(positionOS, _Axis, _AxisStart, _AxisEnd);

            // Orden en que desaparece cada punto (0 = primero, 1 = último).
            float uniformOrder = lerp(0.5, noiseValue, _NoiseAmount);
            float sweepOrder = saturate(sweep + (noiseValue - 0.5) * _NoiseAmount * 0.5);
            float order = lerp(uniformOrder, sweepOrder, _Directional);

            float vanish = ResolveVanish(_Vanish, _AutoAnimate, _AutoSpeed, _Time.y);
            // Rango real de 'order' para que el slider no tenga zonas muertas.
            float orderMin = lerp(lerp(0.5, 0.0, _NoiseAmount), 0.0, _Directional);
            float orderMax = lerp(lerp(0.5, 1.0, _NoiseAmount), 1.0, _Directional);
            float band = max(_DitherBand, _EdgeWidth);
            float front = lerp(orderMin - band, orderMax + 0.001, vanish);
            return order - front;
        }

        // Descarta el pixel según el patrón de dither. Devuelve la distancia
        // al frente para que el pase de color pueda pintar el borde.
        float ClipVanish(float3 positionOS, float2 pixelCoord)
        {
            float dist = VanishDistance(positionOS);
            float coverage = saturate(dist / _DitherBand);
            clip(coverage - DitherThreshold(pixelCoord, _DitherScale));
            return dist;
        }
        ENDHLSL

        // -------------------------------------------------------------------
        // Color
        // -------------------------------------------------------------------
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            Cull [_Cull]
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
                float3 positionOS : TEXCOORD3;
                float fogFactor : TEXCOORD4;
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
                output.positionOS = input.positionOS.xyz;
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                output.fogFactor = ComputeFogFactor(positions.positionCS.z);
                return output;
            }

            half4 Frag(Varyings input, FRONT_FACE_TYPE isFrontFace : FRONT_FACE_SEMANTIC) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);

                float dist = ClipVanish(input.positionOS, input.positionCS.xy);

                half4 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor;
                half3 normalWS = normalize(input.normalWS);
                normalWS = IS_FRONT_VFACE(isFrontFace, normalWS, -normalWS);

                // El bucle de luces adicionales de Forward+ necesita estos datos.
                InputData inputData = (InputData)0;
                inputData.positionWS = input.positionWS;
                inputData.normalWS = normalWS;
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);

                // Luz principal
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                half mainLit = saturate(dot(normalWS, mainLight.direction))
                    * mainLight.shadowAttenuation * mainLight.distanceAttenuation;
                half3 color = albedo.rgb * mainLight.color * lerp(_ShadowColor.rgb, half3(1.0, 1.0, 1.0), mainLit);

                // Luces adicionales
                #if defined(_ADDITIONAL_LIGHTS)
                uint lightCount = GetAdditionalLightsCount();
                LIGHT_LOOP_BEGIN(lightCount)
                    Light light = GetAdditionalLight(lightIndex, input.positionWS, half4(1.0, 1.0, 1.0, 1.0));
                    half lightAmount = saturate(dot(normalWS, light.direction))
                        * light.shadowAttenuation * light.distanceAttenuation;
                    color += albedo.rgb * light.color * lightAmount;
                LIGHT_LOOP_END
                #endif

                color += albedo.rgb * SampleSH(normalWS) * _AmbientStrength;

                // Borde brillante en el frente del desvanecido.
                half edge = 1.0 - saturate(dist / max(_EdgeWidth, 1e-4));
                color = lerp(color, _EdgeColor.rgb, edge * step(1e-4, _EdgeWidth));

                color = MixFog(color, input.fogFactor);
                return half4(color, 1.0);
            }
            ENDHLSL
        }

        // -------------------------------------------------------------------
        // Sombras (la sombra también se desvanece con el mismo patrón)
        // -------------------------------------------------------------------
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull [_Cull]

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
                float3 positionOS : TEXCOORD0;
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
                output.positionOS = input.positionOS.xyz;
                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                ClipVanish(input.positionOS, input.positionCS.xy);
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
            Cull [_Cull]

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
                float3 positionOS : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings Vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.positionOS = input.positionOS.xyz;
                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                ClipVanish(input.positionOS, input.positionCS.xy);
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
            Cull [_Cull]

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
                float3 positionOS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings Vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.positionOS = input.positionOS.xyz;
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                ClipVanish(input.positionOS, input.positionCS.xy);
                return half4(normalize(input.normalWS), 0.0);
            }
            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
