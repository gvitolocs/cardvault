# ORT JNI looks up these by name on session.run(). R8 dropping TensorInfo
# aborts the process: "JNI DETECTED ERROR ... java_class == null".
-keep class ai.onnxruntime.** { *; }
-keepclassmembers class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**
-keep class com.qualcomm.** { *; }
-dontwarn com.qualcomm.**

-keep class org.tensorflow.lite.** { *; }
-keep class org.tensorflow.lite.gpu.** { *; }
-dontwarn org.tensorflow.lite.**

-keep class com.pokoin.trainingai.trainingai_card_scanner.MiloQnnGpu { *; }
-keep class com.pokoin.trainingai.trainingai_card_scanner.MiloQnnPrepService { *; }
-keep class com.pokoin.trainingai.trainingai_card_scanner.LaunchActivity { *; }
