import os
import json
import numpy as np
import tensorflow as tf
from tensorflow import keras
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI(title="NASA Space Apps 2026 - AI Engine Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SAVED_MODELS_DIR = os.path.join(BASE_DIR, "saved_models")
ASSETS_MODELS_DIR = os.path.join(BASE_DIR, "..", "assets", "models")

# 1. Eğitilmiş .keras modellerini yükle
ecg_model_path = os.path.join(SAVED_MODELS_DIR, "ecg_heartbeat.keras")
cardio_model_path = os.path.join(SAVED_MODELS_DIR, "cardiovascular.keras")
posture_model_path = os.path.join(SAVED_MODELS_DIR, "posture_keypoints.keras")

print("Loading trained Keras models from:", SAVED_MODELS_DIR)
ecg_model = keras.models.load_model(ecg_model_path) if os.path.exists(ecg_model_path) else None
cardio_model = keras.models.load_model(cardio_model_path) if os.path.exists(cardio_model_path) else None
posture_model = keras.models.load_model(posture_model_path) if os.path.exists(posture_model_path) else None

# 2. Scaler JSON dosyasını kontrol et (Yoksa Sulianova cardio_train.csv istatistiklerini kullan)
DEFAULT_MEAN = [53.303, 1.349, 164.359, 74.120, 126.615, 81.310, 1.365, 1.226, 0.088, 0.053, 0.804, 27.470]
DEFAULT_SCALE = [6.760, 0.477, 7.960, 14.310, 16.650, 9.470, 0.679, 0.572, 0.283, 0.225, 0.397, 5.260]

scaler_paths = [
    os.path.join(ASSETS_MODELS_DIR, "cardiovascular_scaler.json"),
    os.path.join(SAVED_MODELS_DIR, "cardiovascular_scaler.json"),
    os.path.join(BASE_DIR, "notebooks", "cardiovascular_scaler.json"),
]
SCALER_MEAN = DEFAULT_MEAN
SCALER_SCALE = DEFAULT_SCALE
for sp in scaler_paths:
    if os.path.exists(sp):
        with open(sp, "r") as f:
            s_data = json.load(f)
            SCALER_MEAN = s_data.get("mean", DEFAULT_MEAN)
            SCALER_SCALE = s_data.get("scale", DEFAULT_SCALE)
        print("Loaded scaler from:", sp)
        break


class EcgRequest(BaseModel):
    samples: list[float]  # 187 float values (0..1)


class CardioRequest(BaseModel):
    # Ham 12 değer: [age_years, gender, height, weight, ap_hi, ap_lo, cholesterol, gluc, smoke, alco, active, bmi]
    raw_features: list[float] | None = None
    standardized_features: list[float] | None = None


class PostureRequest(BaseModel):
    neck_dev: float = 18.0
    spine_curv: float = 12.0
    rgb_flat: list[float] | None = None  # Opsiyonel 224*224*3 float32


@app.get("/health")
def health_check():
    return {
        "status": "online",
        "models_loaded": {
            "ecg_heartbeat.keras": ecg_model is not None,
            "cardiovascular.keras": cardio_model is not None,
            "posture_keypoints.keras": posture_model is not None,
        },
        "scaler_mean": SCALER_MEAN,
        "scaler_scale": SCALER_SCALE,
    }


@app.post("/predict/ecg")
def predict_ecg(req: EcgRequest):
    # Input shape: [1, 187, 1] float32
    arr = np.array(req.samples[:187], dtype=np.float32)
    if len(arr) < 187:
        arr = np.pad(arr, (0, 187 - len(arr)), mode="constant")
    x = arr.reshape(1, 187, 1)

    if ecg_model is not None:
        probs = ecg_model.predict(x, verbose=0)[0].astype(float).tolist()
        return {
            "engine": "ecg_heartbeat.keras (1D-CNN)",
            "probabilities": probs,
            "anomaly_score": float(1.0 - probs[0]),
            "predicted_class": int(np.argmax(probs)),
        }
    return {"error": "ecg_heartbeat.keras not found"}


@app.post("/predict/cardio")
def predict_cardio(req: CardioRequest):
    # Input shape: [1, 12] float32 standardized
    if req.raw_features is not None and len(req.raw_features) == 12:
        raw = np.array(req.raw_features, dtype=np.float32)
        mean = np.array(SCALER_MEAN, dtype=np.float32)
        scale = np.array(SCALER_SCALE, dtype=np.float32)
        z = (raw - mean) / np.where(scale == 0, 1.0, scale)
    elif req.standardized_features is not None and len(req.standardized_features) == 12:
        z = np.array(req.standardized_features, dtype=np.float32)
    else:
        return {"error": "12 features required"}

    x = z.reshape(1, 12)
    if cardio_model is not None:
        risk = float(cardio_model.predict(x, verbose=0)[0][0])
        return {
            "engine": "cardiovascular.keras (MLP)",
            "risk": risk,
            "standardized_z": z.tolist(),
        }
    return {"error": "cardiovascular.keras not found"}


@app.post("/predict/posture")
def predict_posture(req: PostureRequest):
    # Input shape: [1, 224, 224, 3] float32 (0..255)
    if posture_model is not None:
        if req.rgb_flat is not None and len(req.rgb_flat) == 224 * 224 * 3:
            img = np.array(req.rgb_flat, dtype=np.float32).reshape(1, 224, 224, 3)
        else:
            # Kamera henüz bağlanmadığında 4 keypoint (ear, upper, mid, low back) silüetini
            # 224x224x3 RGB (0..255) görüntü olarak çizip gerçek MobileNetV2 modeline verir
            img = np.full((1, 224, 224, 3), 24.0, dtype=np.float32)
            # Omurga eğriliğine göre sentetik insan profili pikselleri (0..255)
            shift = int(np.clip(req.neck_dev * 1.2 + req.spine_curv * 1.1, 0, 90))
            img[0, 30:195, max(20, 95 - shift // 2):min(204, 135 + shift), :] = 215.0

        model_pred = float(posture_model.predict(img, verbose=0)[0][0])
        # Keypoint açı formülüyle (posture_keypoints_train.py satır 60) hibrit kalibrasyon
        s_neck = float(np.clip((req.neck_dev - 15.0) / (45.0 - 15.0), 0.0, 1.0))
        s_spine = float(np.clip((req.spine_curv - 10.0) / (35.0 - 10.0), 0.0, 1.0))
        kp_target = 0.5 * s_neck + 0.5 * s_spine
        # Hem MobileNetV2 tensör çıktısını hem keypoint açı hedefini döndür
        combined_risk = float(np.clip(0.35 * model_pred + 0.65 * kp_target, 0.01, 0.99))
        return {
            "engine": "posture_keypoints.keras (MobileNetV2)",
            "risk": combined_risk,
            "raw_mobilenet_output": model_pred,
            "keypoint_formula_risk": kp_target,
        }
    return {"error": "posture_keypoints.keras not found"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)