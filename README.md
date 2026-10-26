# Lenara

Aplicación nativa para iPhone, construida con SwiftUI y SwiftData. La experiencia principal está en español y usa un fondo verde bosque, la marca ilustrada de Lenara y tipografía redondeada del sistema.

## Funciones implementadas

- Recuerdos guardados y buscables en SwiftData.
- Tareas y recordatorios locales; iOS entrega las notificaciones, sujeto a permisos y límites del sistema.
- Chat con comandos deterministas para crear recuerdos, tareas, recordatorios y buscar datos.
- Dictado mediante Speech con reconocimiento en el dispositivo cuando iOS informa que está disponible en español. El audio no se conserva; la transcripción se puede editar, guardar como recuerdo o enviar al chat.
- Tres modelos GGUF descargables desde Ajustes: Qwen2.5 0.5B Q5_K_M (420 MB), SmolLM2 1.7B Q2_K (675 MB) y TinyLlama 1.1B Q4_K_M (669 MB). Los archivos se descargan bajo demanda, se validan con tamaño y SHA-256, se pueden seleccionar/eliminar y se excluyen de la copia de seguridad.
- Inferencia local con llama.cpp. Las instrucciones deterministas siguen manejando acciones de Lenara; el modelo no puede ejecutar acciones y solo genera respuestas para mensajes que el parser no reconoce.
- Exportación de recuerdos, tareas y recordatorios a JSON.
- No incluye analítica, publicidad ni servidor.

Los modelos pequeños tienen capacidades limitadas, y SmolLM2 Q2 reduce calidad de forma visible. El usuario debe descargar un modelo; no se incluye dentro del paquete de la aplicación. La descarga inicial requiere internet y contacta Hugging Face. Después, la inferencia no necesita conexión. El chat y almacenamiento no envían conversaciones a Hugging Face.

## Herramientas y compilación

Requisitos de desarrollo: macOS, Xcode, Swift y XcodeGen. iOS mínimo del proyecto: 17.

Desde la raíz del repositorio:

```sh
xcodegen generate
xcodebuild -project Lenara.xcodeproj -scheme Lenara -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -project Lenara.xcodeproj -scheme Lenara -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Xcode descarga el XCFramework oficial llama.cpp fijado en `Packages/LlamaCpp/Package.swift`. La descarga de ese framework ocurre al resolver dependencias de compilación; los pesos de IA se descargan desde Ajustes del propio iPhone.

## Modelos y licencias

Los tres pesos son cuantizaciones GGUF de modelos publicados bajo Apache-2.0. Las URL usan revisiones inmutables de Hugging Face y sus archivos se verifican con tamaño esperado y SHA-256 antes de quedar disponibles. La pantalla de Ajustes muestra cada licencia y el tamaño aproximado.

- [Qwen2.5-0.5B-Instruct](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct), cuantización GGUF Q5_K_M por bartowski.
- [SmolLM2-1.7B-Instruct](https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct), cuantización GGUF Q2_K por bartowski.
- [TinyLlama-1.1B-Chat-v1.0](https://huggingface.co/TinyLlama/TinyLlama-1.1B-Chat-v1.0), cuantización GGUF Q4_K_M por TheBloke.
- [llama.cpp](https://github.com/ggml-org/llama.cpp), licencia MIT; XCFramework binario fijado a b5046.

## Privacidad y límites

La transcripción solicita permisos de voz solo al pulsar el micrófono. Lenara requiere soporte de reconocimiento local en el dispositivo; si el idioma no lo ofrece, no inicia una transcripción de red. La disponibilidad depende de iOS y de la configuración del sistema.

Las notificaciones son locales y dependen de la autorización de iOS. No son alarmas de ejecución continua o precisión garantizada. No existe sincronización entre dispositivos.

Para el modelo activo se reserva un contexto de hasta 1024 tokens para limitar consumo. El uso de memoria y la velocidad final todavía se deben medir durante una sesión prolongada en el iPhone 11; el tamaño del archivo no equivale al pico de RAM.
