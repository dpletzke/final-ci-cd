"""ML prediction logic for Boston House Pricing."""

import os
import pickle

import numpy as np

FEATURE_ORDER = [
    "CRIM",
    "ZN",
    "INDUS",
    "CHAS",
    "NOX",
    "RM",
    "AGE",
    "DIS",
    "RAD",
    "TAX",
    "PTRATIO",
    "B",
    "LSTAT",
]


def _load_models():
    """Load and return the regression model and scaler from the models directory."""
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    with open(os.path.join(base_dir, "models", "regmodel.pkl"), "rb") as model_file:
        regmodel = pickle.load(model_file)
    with open(os.path.join(base_dir, "models", "scaling.pkl"), "rb") as scaler_file:
        scalar = pickle.load(scaler_file)
    return regmodel, scalar


_regmodel, _scalar = _load_models()


def predict_from_list(features: list) -> float:
    """Return the predicted price given 13 feature values in FEATURE_ORDER."""
    scaled = _scalar.transform(np.array(features).reshape(1, -1))
    return round(float(_regmodel.predict(scaled)[0]), 2)


def predict_from_dict(data: dict) -> float:
    """Return the predicted price given a dict with FEATURE_ORDER keys."""
    features = [float(data[f]) for f in FEATURE_ORDER]
    return predict_from_list(features)
