from fastapi import FastAPI
from pydantic import BaseModel
import numpy as np
import keras

app = FastAPI()

ecg_model = keras.models.load_model("saved_models/ecg_heartbeat.keras")
cardio_model = keras.models.load_model("saved_models/cardiovascular.keras")
posture_model = keras.models.load_model("saved_models/posture_keypoints.keras")

class EcgPayload(BaseModel):
    samples: list[float]

class CardioPayload(BaseModel):
    features: list[float]

@app.post("/predict/ecg")
def predict_ecg(data: EcgPayload):
    x = np.array(data.samples, dtype=np.float32).reshape(1, 187, 1)
    probs = ecg_model.predict(x, verbose=0)[0].tolist()
    return {"probabilities": probs}

@app.post("/predict/cardio")
def predict_cardio(data: CardioPayload):
    x = np.array(data.features, dtype=np.float32).reshape(1, 12)
    risk = float(cardio_model.predict(x, verbose=0)[0][0])
    return {"risk": risk}