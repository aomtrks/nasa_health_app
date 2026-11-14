# =============================================================
# Module C (v3) - Image-based posture risk -> posture_keypoints.tflite
# MobileNetV2 regressor: IMAGE -> ergonomic risk (0-1).
# Target per image = risk computed from that image's annotated keypoints
# (neck-vs-trunk angle, spine curvature). Dataset has no good/bad labels.
#
# OUTPUT FILES -> WHERE THEY GO:
#   posture_keypoints.tflite       -> astronaut_health_monitor/assets/models/
#   posture_keypoints_meta.json    -> astronaut_health_monitor/assets/models/
#   posture_keypoints.keras        -> astronaut_health_monitor/ai_engine/saved_models/
#   posture_keypoints_train.py     -> astronaut_health_monitor/ai_engine/notebooks/
# =============================================================

# %% 1. Setup & download
import os, glob, json, numpy as np, tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers
from sklearn.model_selection import train_test_split

SEED = 42
np.random.seed(SEED); tf.random.set_seed(SEED)

LOCAL = r"C:\Users\ACER\nasa_health_app\ai_engine\datasets\posture_keypoints"
if os.path.exists(LOCAL):
    path = LOCAL
else:
    import kagglehub
    path = kagglehub.dataset_download("melsmm/posture-keypoints-detection")
for root, dirs, fs in os.walk(path):
    print(root.replace(path, "."), "|", len(fs), "files", fs[:3])

# %% 2. CONFIG
IMG_SIZE = 224
# Dataset has 4 side-view spine keypoints (verified by plotting):
#   0 = ear/head, 1 = upper back/shoulder, 2 = mid-back, 3 = lower back
K_EXPECTED = 4

# %% 3. Pair images with their keypoint labels
imgs = [f for e in ("jpg", "jpeg", "png") for f in glob.glob(os.path.join(path, "**", f"*.{e}"), recursive=True)]
lbls = {os.path.splitext(os.path.basename(f))[0]: f
        for f in glob.glob(os.path.join(path, "**", "*.txt"), recursive=True)}
print("Images:", len(imgs), "| label files:", len(lbls))

def load_person(label_fp, w, h):
    """Largest person in a YOLO-pose label file -> keypoints (K,2) in pixels."""
    best, best_area = None, -1
    for line in open(label_fp).read().strip().splitlines():
        v = line.split()
        if len(v) < 8: continue
        bw, bh = float(v[3]), float(v[4])
        rest = np.array(v[5:], dtype="float32")
        step = 3 if len(rest) % 3 == 0 else 2
        kp = rest.reshape(-1, step)[:, :2].copy()
        if kp.max() <= 1.5:                      # normalised -> pixels
            kp[:, 0] *= w; kp[:, 1] *= h
        if bw * bh > best_area: best, best_area = kp, bw * bh
    return best

# %% 4. Risk target from angles (rotation-invariant: no "vertical" needed, fine for microgravity)
def angle_between(u, v):
    cos = np.dot(u, v) / (np.linalg.norm(u) * np.linalg.norm(v) + 1e-6)
    return np.degrees(np.arccos(np.clip(cos, -1, 1)))

def risk_score(kp):
    head, upper, mid, low = kp[0], kp[1], kp[2], kp[3]
    neck_dev = angle_between(upper - low, head - upper)     # head/neck bend relative to trunk
    spine_curv = angle_between(mid - low, upper - mid)      # slouch / spinal curvature
    s = lambda a, ok, bad: float(np.clip((a - ok) / (bad - ok), 0, 1))   # placeholder thresholds
    return 0.5 * s(neck_dev, 15, 45) + 0.5 * s(spine_curv, 10, 35)

paths, targets = [], []
for f in imgs:
    stem = os.path.splitext(os.path.basename(f))[0]
    if stem not in lbls: continue
    im = tf.io.decode_image(tf.io.read_file(f), channels=3, expand_animations=False)
    h, w = int(im.shape[0]), int(im.shape[1])
    kp = load_person(lbls[stem], w, h)
    if kp is None: continue
    assert len(kp) == K_EXPECTED, f"Expected {K_EXPECTED} keypoints, got {len(kp)}."
    paths.append(f); targets.append(risk_score(kp))
targets = np.array(targets, dtype="float32")
print("Usable images:", len(paths), "| risk mean/std:", targets.mean().round(3), targets.std().round(3))
assert len(paths) > 20, "Image/label pairing failed - check folder layout printed above."
assert targets.std() > 0.05, "Risk labels ~constant - check thresholds."

# %% 5. tf.data pipeline
tr_p, te_p, tr_y, te_y = train_test_split(paths, targets, test_size=0.2, random_state=SEED)
tr_p, va_p, tr_y, va_y = train_test_split(tr_p, tr_y, test_size=0.15, random_state=SEED)

def load(p, y):
    im = tf.io.decode_image(tf.io.read_file(p), channels=3, expand_animations=False)
    im = tf.image.resize(im, (IMG_SIZE, IMG_SIZE))
    im.set_shape((IMG_SIZE, IMG_SIZE, 3))
    return tf.cast(im, tf.float32), y            # 0..255 RGB

def aug(im, y):                                  # flip keeps risk (angles are symmetric)
    im = tf.image.random_flip_left_right(im)
    im = tf.image.random_brightness(im, 25.0)
    im = tf.image.random_contrast(im, 0.8, 1.2)
    return tf.clip_by_value(im, 0, 255), y

def ds(p, y, train):
    d = tf.data.Dataset.from_tensor_slices((p, y)).map(load, num_parallel_calls=tf.data.AUTOTUNE)
    if train: d = d.shuffle(512, seed=SEED).map(aug, num_parallel_calls=tf.data.AUTOTUNE)
    return d.batch(16).prefetch(tf.data.AUTOTUNE)

train_ds, val_ds, test_ds = ds(tr_p, tr_y, True), ds(va_p, va_y, False), ds(te_p, te_y, False)

# %% 6. Model: MobileNetV2 (alpha 0.35), preprocessing INSIDE the model
base = keras.applications.MobileNetV2(input_shape=(IMG_SIZE, IMG_SIZE, 3), alpha=0.35,
                                      include_top=False, weights="imagenet")
base.trainable = False
inp = keras.Input(shape=(IMG_SIZE, IMG_SIZE, 3), name="image_input")       # float32 0..255
x = layers.Rescaling(1 / 127.5, offset=-1)(inp)                            # -> [-1, 1]
x = base(x, training=False)
x = layers.GlobalAveragePooling2D()(x)
x = layers.Dropout(0.3)(x)
out = layers.Dense(1, activation="sigmoid", name="posture_risk")(x)
model = keras.Model(inp, out, name="posture_mobilenet")

stop = keras.callbacks.EarlyStopping(monitor="val_loss", patience=8, restore_best_weights=True)
model.compile(keras.optimizers.Adam(1e-3), loss="mse", metrics=["mae"])
model.fit(train_ds, validation_data=val_ds, epochs=30, callbacks=[stop], verbose=2)

base.trainable = True                                                       # fine-tune top layers
for l in base.layers[:-30]: l.trainable = False
model.compile(keras.optimizers.Adam(1e-5), loss="mse", metrics=["mae"])
model.fit(train_ds, validation_data=val_ds, epochs=20, callbacks=[stop], verbose=2)
print("Test [loss, mae]:", model.evaluate(test_ds, verbose=0))

# %% 7. Export
model.save("posture_keypoints.keras")
conv = tf.lite.TFLiteConverter.from_keras_model(model)
conv.optimizations = [tf.lite.Optimize.DEFAULT]
tfl = conv.convert()
open("posture_keypoints.tflite", "wb").write(tfl)
json.dump({"input_shape": [1, IMG_SIZE, IMG_SIZE, 3], "input_dtype": "float32",
           "input_range": "RGB pixel values 0..255 (rescaling is inside the model)",
           "output_shape": [1, 1], "risk_score": "output[0] in 0..1 (higher = worse posture)",
           "keypoints": "0 ear, 1 upper back, 2 mid back, 3 lower back (training targets only)"},
          open("posture_keypoints_meta.json", "w"), indent=2)

it = tf.lite.Interpreter(model_content=tfl); it.allocate_tensors()
i_d, o_d = it.get_input_details()[0], it.get_output_details()[0]
errs = []
for xb, yb in test_ds.unbatch().take(50):
    it.set_tensor(i_d["index"], xb.numpy()[None]); it.invoke()
    errs.append(abs(it.get_tensor(o_d["index"])[0, 0] - float(yb)))
print("TFLite MAE vs target:", np.mean(errs), "| size KB:", len(tfl) / 1024)



# FLUTTER: camera frame -> resize to 224x224 RGB -> float32 values 0..255 (NO extra normalisation)
#   input [1,224,224,3] -> output [1,1] = posture risk 0..1 (spine / musculoskeletal region)