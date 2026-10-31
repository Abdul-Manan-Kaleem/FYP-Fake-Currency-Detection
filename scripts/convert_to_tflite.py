import tensorflow as tf
import os

model_path = os.path.join("model", "model.keras")
output_dir = os.path.join("app", "assets", "models")
output_path = os.path.join(output_dir, "currency_detector.tflite")

os.makedirs(output_dir, exist_ok=True)

print(f"Loading model from {model_path}...")
try:
    model = tf.keras.models.load_model(model_path)
    
    print("Converting to TensorFlow Lite...")
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    
    # Optionally, apply optimizations here
    # converter.optimizations = [tf.lite.Optimize.DEFAULT]
    
    tflite_model = converter.convert()
    
    with open(output_path, 'wb') as f:
        f.write(tflite_model)
        
    print(f"Success! TFLite model saved to {output_path}")
except Exception as e:
    print(f"Error converting model: {e}")
