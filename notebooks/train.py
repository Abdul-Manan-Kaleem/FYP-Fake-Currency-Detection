import tensorflow as tf
from tensorflow.keras import layers, models
from tensorflow.keras.applications import MobileNetV3Small
import matplotlib.pyplot as plt

# ====== PATH ======
DATASET_PATH = "DataSet"

IMG_SIZE = (224, 224)
BATCH_SIZE = 32

# ====== LOAD DATA ======
train_ds = tf.keras.preprocessing.image_dataset_from_directory(
    DATASET_PATH + "/train",
    image_size=IMG_SIZE,
    batch_size=BATCH_SIZE
)

val_ds = tf.keras.preprocessing.image_dataset_from_directory(
    DATASET_PATH + "/val",
    image_size=IMG_SIZE,
    batch_size=BATCH_SIZE
)

test_ds = tf.keras.preprocessing.image_dataset_from_directory(
    DATASET_PATH + "/test",
    image_size=IMG_SIZE,
    batch_size=BATCH_SIZE
)

class_names = train_ds.class_names
print("Classes:", class_names)

# ====== PERFORMANCE ======
AUTOTUNE = tf.data.AUTOTUNE
train_ds = train_ds.cache().prefetch(buffer_size=AUTOTUNE)
val_ds = val_ds.cache().prefetch(buffer_size=AUTOTUNE)
test_ds = test_ds.cache().prefetch(buffer_size=AUTOTUNE)

# ====== DATA AUGMENTATION ======
data_augmentation = tf.keras.Sequential([
    layers.RandomFlip("horizontal"),
    layers.RandomRotation(0.05),
    layers.RandomZoom(0.1),
    layers.RandomBrightness(0.1),
])

# ====== BASE MODEL ======
base_model = MobileNetV3Small(
    input_shape=(224, 224, 3),
    include_top=False,
    weights='imagenet'
)

# ====== STAGE 1: FEATURE EXTRACTION ======
base_model.trainable = False

model = models.Sequential([
    data_augmentation,
    layers.Rescaling(1./255),
    base_model,
    layers.GlobalAveragePooling2D(),
    layers.BatchNormalization(),
    layers.Dense(128, activation='relu'),
    layers.Dropout(0.5),
    layers.Dense(1, activation='sigmoid')
])

model.compile(
    optimizer=tf.keras.optimizers.Adam(learning_rate=0.0001),
    loss='binary_crossentropy',
    metrics=['accuracy']
)

print("\nStage 1 Training...\n")

history1 = model.fit(
    train_ds,
    validation_data=val_ds,
    epochs=7
)

# ====== STAGE 2: SAFE FINE-TUNING ======
base_model.trainable = True

for layer in base_model.layers[:-10]:
    layer.trainable = False

model.compile(
    optimizer=tf.keras.optimizers.Adam(learning_rate=0.000001),
    loss='binary_crossentropy',
    metrics=['accuracy']
)

early_stop = tf.keras.callbacks.EarlyStopping(
    monitor='val_loss',
    patience=2,
    restore_best_weights=True
)

print("\nStage 2 Fine-tuning...\n")

history2 = model.fit(
    train_ds,
    validation_data=val_ds,
    epochs=5,
    callbacks=[early_stop]
)

# ====== EVALUATE ======
loss, acc = model.evaluate(test_ds)
print("Test Accuracy:", acc)

# ====== SAVE ======
model.save("currency_model.keras")

# ====== PLOT ======
plt.plot(history1.history['accuracy'] + history2.history['accuracy'], label='train')
plt.plot(history1.history['val_accuracy'] + history2.history['val_accuracy'], label='val')
plt.legend()
plt.title("Accuracy")
plt.show()