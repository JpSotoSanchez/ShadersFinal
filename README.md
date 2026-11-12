# ShadersFinal

Showcase de shaders en Unity 6000.5.7f1 con URP.

## Shaders

Están en `Assets/Shaders`. Para usar uno: crear un material, elegir el shader en el menú `Showcase/` y arrastrarlo al objeto.

| Shader | Menú | Notas |
| --- | --- | --- |
| Toon + Borderlands + Dither | `Showcase/Toon Borderlands Dither` | Se ve mejor en mallas con normales suaves. |
| Espada láser | `Showcase/Laser Sword Vanish` | Para un cilindro o cápsula. Brilla más con Bloom. |
| Dither + Vanish | `Showcase/Dither Vanish` | Sigue proyectando sombra mientras desaparece. |

El slider **Vanish** desvanece el objeto (0 = visible, 1 = desaparecido). Para animarlo, activar **Animar vanish solo** en el material o animar la propiedad desde la ventana Animation.
