# =============================================================
# Module B - Cardiovascular risk (cardio_train.csv) -> cardiovascular.tflite
# Run in Google Colab (one cell per "# %%" block).
#
# OUTPUT FILES -> WHERE THEY GO:
#   cardiovascular.tflite         -> astronaut_health_monitor/assets/models/
#   cardiovascular_scaler.json    -> astronaut_health_monitor/assets/models/
#   cardiovascular.keras          -> astronaut_health_monitor/ai_engine/saved_models/  (NOT in assets)
#   cardiovascular_train.py       -> astronaut_health_monitor/ai_engine/notebooks/
# =============================================================

# %% 1. Setup & data
import os, json, numpy as np, pandas as pd, tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import classification_report, roc_auc_score

SEED = 42
np.random.seed(SEED); tf.random.set_seed(SEED)

try:
    import kagglehub
    path = kagglehub.dataset_download("sulianova/cardiovascular-disease-dataset")
except Exception:
   # from google.colab import files
    files.upload()          # upload cardio_train.csv
    path = "."

df = pd.read_csv(os.path.join(path, "cardio_train.csv"), sep=";")
print("Raw shape:", df.shape)

# %% 2. Cleaning
df["age_years"] = df["age"] / 365.25            # age is in days in the dataset
df = df[(df["ap_hi"].between(70, 250)) &
        (df["ap_lo"].between(40, 200)) &
        (df["ap_hi"] > df["ap_lo"]) &
        (df["height"].between(120, 220)) &
        (df["weight"].between(30, 200))].copy()
df["bmi"] = df["weight"] / (df["height"] / 100) ** 2
print("Clean shape:", df.shape)

# Feature ORDER matters - Flutter must build the input vector in this exact order.
FEATURES = ["age_years", "gender", "height", "weight", "ap_hi", "ap_lo",
            "cholesterol", "gluc", "smoke", "alco", "active", "bmi"]
X = df[FEATURES].values.astype("float32")
y = df["cardio"].values.astype("float32")

# %% 3. Split + scale (fit scaler on train only)
X_tr, X_te, y_tr, y_te = train_test_split(X, y, test_size=0.2, stratify=y, random_state=SEED)
X_tr, X_val, y_tr, y_val = train_test_split(X_tr, y_tr, test_size=0.15, stratify=y_tr, random_state=SEED)

scaler = StandardScaler().fit(X_tr)
X_tr, X_val, X_te = [scaler.transform(a).astype("float32") for a in (X_tr, X_val, X_te)]

# Scaler params for Flutter: z = (x - mean) / scale, applied to ALL 12 features
with open("cardiovascular_scaler.json", "w") as f:
    json.dump({
        "features": FEATURES,
        "mean": scaler.mean_.tolist(),
        "scale": scaler.scale_.tolist(),
        "input_shape": [1, len(FEATURES)],
        "output": "risk probability 0.0-1.0 (sigmoid)",
        "notes": "age_years = age_days/365.25; gender 1=female 2=male; "
                 "cholesterol/gluc 1=normal 2=above 3=well above; smoke/alco/active 0/1; "
                 "bmi = weight / (height_m^2)",
    }, f, indent=2)

# %% 4. Model (small MLP)
model = keras.Sequential([
    keras.Input(shape=(len(FEATURES),), name="cardio_input"),
    layers.Dense(64, activation="relu"),
    layers.BatchNormalization(),
    layers.Dropout(0.3),
    layers.Dense(32, activation="relu"),
    layers.Dropout(0.2),
    layers.Dense(1, activation="sigmoid", name="risk"),
], name="cardio_mlp")
model.compile(optimizer=keras.optimizers.Adam(1e-3),
              loss="binary_crossentropy",
              metrics=["accuracy", keras.metrics.AUC(name="auc")])
model.summary()

# %% 5. Train
model.fit(X_tr, y_tr, validation_data=(X_val, y_val), epochs=60, batch_size=256,
          callbacks=[keras.callbacks.EarlyStopping(monitor="val_auc", mode="max",
                                                   patience=8, restore_best_weights=True),
                     keras.callbacks.ReduceLROnPlateau(monitor="val_loss", factor=0.5, patience=3)],
          verbose=2)

# %% 6. Evaluate
p = model.predict(X_te, batch_size=1024).ravel()
print("ROC-AUC:", round(roc_auc_score(y_te, p), 4))
print(classification_report(y_te, (p > 0.5).astype(int), digits=4))

# %% 7. Export to TFLite
model.save("cardiovascular.keras")      # -> ai_engine/saved_models/
converter = tf.lite.TFLiteConverter.from_keras_model(model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
tflite_model = converter.convert()
with open("cardiovascular.tflite", "wb") as f:
    f.write(tflite_model)
print(f"TFLite size: {len(tflite_model)/1024:.1f} KB")

# %% 8. Verify TFLite vs Keras (raw -> scaled -> inference)
interp = tf.lite.Interpreter(model_content=tflite_model)
interp.allocate_tensors()
i_d, o_d = interp.get_input_details()[0], interp.get_output_details()[0]
print("input:", i_d["shape"], i_d["dtype"], "| output:", o_d["shape"])

n = 2000
tfl = np.zeros(n)
for i in range(n):
    interp.set_tensor(i_d["index"], X_te[i:i+1])
    interp.invoke()
    tfl[i] = interp.get_tensor(o_d["index"])[0, 0]
print("Max |keras - tflite|:", np.abs(tfl - p[:n]).max())
print("TFLite accuracy:", ((tfl > 0.5) == y_te[:n]).mean())


import os
import shutil

# Hedef klasörü oluştur (yoksa)
target_dir = os.path.join("assets", "models")
os.makedirs(target_dir, exist_ok=True)

# 1. Modeli doğrudan hedef klasöre kaydet
tflite_path = os.path.join(target_dir, "cardiovascular.tflite")
with open(tflite_path, "wb") as f:
    f.write(tflite_model)
print(f"Model kaydedildi: {tflite_path}")

# 2. Eğer kodun üst kısımlarında scaler json dosyası oluşturulduysa onu da hedef klasöre taşı
for json_name in ["cardio_scaler.json", "cardiovascular_scaler.json", "scaler_params.json"]:
    if os.path.exists(json_name):
        shutil.move(json_name, os.path.join(target_dir, json_name))
        print(f"Scaler dosyası taşındı: {os.path.join(target_dir, json_name)}")
# =============================================================
# FLUTTER (tflite_flutter) matching:
#   final interpreter = await Interpreter.fromAsset('models/cardiovascular.tflite');
#   final s = jsonDecode(await rootBundle.loadString('assets/models/cardiovascular_scaler.json'));
#   // raw values in THIS order:
#   // [age_years, gender, height, weight, ap_hi, ap_lo, cholesterol, gluc, smoke, alco, active, bmi]
#   final z = List.generate(12, (i) => (raw[i] - s['mean'][i]) / s['scale'][i]);
#   var input  = [z];                    // shape [1, 12] float32
#   var output = [[0.0]];                // shape [1, 1]
#   interpreter.run(input, output);
#   final risk = output[0][0];           // 0.0 - 1.0 cardiovascular risk
# pubspec.yaml -> flutter: assets: [assets/models/, assets/3d/]
# =============================================================