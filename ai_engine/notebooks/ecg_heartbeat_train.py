# =============================================================
# Module A - ECG Heartbeat (MIT-BIH) 1D-CNN -> ecg_heartbeat.tflite
# Run in Google Colab (one cell per "# %%" block).
# Classes: 0=N (normal), 1=S (supraventricular), 2=V (ventricular),
#          3=F (fusion), 4=Q (unknown)
# =============================================================

# %% 1. Setup & data
import os, json, numpy as np, pandas as pd, tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers
from sklearn.model_selection import train_test_split
from sklearn.utils.class_weight import compute_class_weight
from sklearn.metrics import classification_report, confusion_matrix

SEED = 42
np.random.seed(SEED); tf.random.set_seed(SEED)

try:
    import kagglehub
    path = kagglehub.dataset_download("shayanfazeli/heartbeat")
except Exception:
    # Fallback: upload mitbih_train.csv / mitbih_test.csv manually
    #from google.colab import files
    files.upload()
    path = "."

train_df = pd.read_csv(os.path.join(path, "mitbih_train.csv"), header=None)
test_df  = pd.read_csv(os.path.join(path, "mitbih_test.csv"),  header=None)

X_all = train_df.iloc[:, :187].values.astype("float32")
y_all = train_df.iloc[:, 187].values.astype("int32")
X_test = test_df.iloc[:, :187].values.astype("float32")
y_test = test_df.iloc[:, 187].values.astype("int32")

# Signals are already min-max scaled to [0, 1] -> no scaler needed in Flutter.
X_train, X_val, y_train, y_val = train_test_split(
    X_all, y_all, test_size=0.15, stratify=y_all, random_state=SEED)

X_train, X_val, X_test = [x[..., None] for x in (X_train, X_val, X_test)]  # (N,187,1)
print("Train class counts:", np.bincount(y_train))

# %% 2. Class imbalance -> class weights (sqrt-damped to avoid over-correcting)
cw = compute_class_weight("balanced", classes=np.arange(5), y=y_train)
class_weight = {i: float(np.sqrt(w)) for i, w in enumerate(cw)}
print("Class weights:", class_weight)

# %% 3. Light 1D-CNN
def build_model():
    inp = keras.Input(shape=(187, 1), name="ecg_input")
    x = layers.Conv1D(32, 5, padding="same")(inp)
    x = layers.BatchNormalization()(x); x = layers.ReLU()(x)
    x = layers.MaxPooling1D(2)(x)
    x = layers.Conv1D(64, 5, padding="same")(x)
    x = layers.BatchNormalization()(x); x = layers.ReLU()(x)
    x = layers.MaxPooling1D(2)(x)
    x = layers.Conv1D(128, 3, padding="same")(x)
    x = layers.BatchNormalization()(x); x = layers.ReLU()(x)
    x = layers.GlobalAveragePooling1D()(x)
    x = layers.Dense(64, activation="relu")(x)
    x = layers.Dropout(0.3)(x)
    out = layers.Dense(5, activation="softmax", name="rhythm_probs")(x)
    return keras.Model(inp, out, name="ecg_1dcnn")

model = build_model()
model.compile(optimizer=keras.optimizers.Adam(1e-3),
              loss="sparse_categorical_crossentropy",
              metrics=["accuracy"])
model.summary()

# %% 4. Train
callbacks = [
    keras.callbacks.EarlyStopping(monitor="val_loss", patience=6, restore_best_weights=True),
    keras.callbacks.ReduceLROnPlateau(monitor="val_loss", factor=0.5, patience=3),
]
model.fit(X_train, y_train, validation_data=(X_val, y_val),
          epochs=40, batch_size=256, class_weight=class_weight,
          callbacks=callbacks, verbose=2)

# %% 5. Evaluate
probs = model.predict(X_test, batch_size=512)
y_pred = probs.argmax(1)
names = ["N", "S", "V", "F", "Q"]
print(classification_report(y_test, y_pred, target_names=names, digits=4))
print(confusion_matrix(y_test, y_pred))

# Heart-region anomaly probability = 1 - P(Normal)
anomaly_prob = 1.0 - probs[:, 0]
print("Mean anomaly prob (normal beats):", anomaly_prob[y_test == 0].mean())
print("Mean anomaly prob (abnormal beats):", anomaly_prob[y_test != 0].mean())

# %% 6. Export to TFLite (dynamic-range quantization)
model.save("ecg_heartbeat.keras")
converter = tf.lite.TFLiteConverter.from_keras_model(model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
tflite_model = converter.convert()
with open("ecg_heartbeat.tflite", "wb") as f:
    f.write(tflite_model)
print(f"TFLite size: {len(tflite_model)/1024:.1f} KB")

# Metadata for Flutter
meta = {
    "input_shape": [1, 187, 1], "input_dtype": "float32",
    "output_shape": [1, 5], "labels": names,
    "normalization": "none (signal already min-max scaled to 0..1)",
    "anomaly_score": "1 - output[0]",
}
with open("ecg_heartbeat_meta.json", "w") as f:
    json.dump(meta, f, indent=2)

# %% 7. Verify TFLite vs Keras
interp = tf.lite.Interpreter(model_content=tflite_model)
interp.allocate_tensors()
inp_d, out_d = interp.get_input_details()[0], interp.get_output_details()[0]
print("input:", inp_d["shape"], inp_d["dtype"], "| output:", out_d["shape"])

n = 2000
correct = 0
for i in range(n):
    interp.set_tensor(inp_d["index"], X_test[i:i+1])
    interp.invoke()
    correct += int(interp.get_tensor(out_d["index"]).argmax() == y_test[i])
print(f"TFLite accuracy on {n} test beats: {correct/n:.4f}")

os.makedirs("assets/models", exist_ok=True)
with open("assets/models/ecg_heartbeat.tflite", "wb") as f:
    f.write(tflite_model)

# =============================================================
# FLUTTER (tflite_flutter) matching:
#   final interpreter = await Interpreter.fromAsset('models/ecg_heartbeat.tflite');
#   // input  : [1, 187, 1] float32, values already 0..1 (no scaling)
#   // output : [1, 5]      float32 softmax (N,S,V,F,Q)
#   var input  = [List.generate(187, (i) => [beat[i]])];   // beat: List<double> len 187
#   var output = [List.filled(5, 0.0)];
#   interpreter.run(input, output);
#   final anomalyProb = 1.0 - output[0][0];   // heart-region risk
#   final rhythmClass = output[0].indexOf(output[0].reduce(max));
# Note: resample/segment live ECG to 187 samples per beat and min-max
# scale each beat to 0..1 before inference, same as MIT-BIH preprocessing.
# =============================================================