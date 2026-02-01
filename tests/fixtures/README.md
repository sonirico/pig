# Fixtures para tests de integración

Imágenes mínimas y deterministas para probar `pig` sin regresiones.

- **sample_1x1.png** – PNG 1×1 (73 B). Para `inspect` y smoke.
- **sample_5x5.png** – PNG 5×5. Para `crop` (ej. 2×2 desde (1,1)).
- **sample_10x10.png** – PNG 10×10. Para `crop` y `scale`.

No añadir imágenes grandes; mantener fixtures pequeños y versionados para que los tests sean rápidos y reproducibles.

**Regresión por checksum**: cuando quieras fijar la salida de un comando (ej. crop), genera una vez la salida correcta, anota su SHA256 y en el test compara: `sha256sum tests/out/crop_2x2.png` vs el hash esperado en el script.
