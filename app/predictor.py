"""ML prediction logic for Boston House Pricing."""

import os
import pickle

import mlflow
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

_MLFLOW_URI = os.environ.get("MLFLOW_TRACKING_URI", "")
_ENVIRONMENT = os.environ.get("ENVIRONMENT", "local")

if _MLFLOW_URI:
    mlflow.set_tracking_uri(_MLFLOW_URI)
    mlflow.set_experiment("boston-house-predictions")


def _load_models():
    """Load and return the regression model and scaler from the models directory."""
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    with open(os.path.join(base_dir, "models", "regmodel.pkl"), "rb") as model_file:
        regmodel = pickle.load(model_file)
    with open(os.path.join(base_dir, "models", "scaling.pkl"), "rb") as scaler_file:
        scalar = pickle.load(scaler_file)
    return regmodel, scalar


_regmodel, _scalar = _load_models()


def _log_prediction(features: list, prediction: float, source: str) -> None:
    """Log a prediction run to MLflow if a tracking URI is configured."""
    if not _MLFLOW_URI:
        return
    try:
        with mlflow.start_run():
            mlflow.log_params(dict(zip(FEATURE_ORDER, features)))
            mlflow.log_metric("predicted_price", prediction)
            mlflow.set_tags({"environment": _ENVIRONMENT, "source": source})
    except Exception:  # pylint: disable=broad-except
        pass  # MLflow logging is non-critical — never break a prediction


def predict_from_list(features: list, source: str = "api") -> float:
    """Return the predicted price given 13 feature values in FEATURE_ORDER."""
    scaled = _scalar.transform(np.array(features).reshape(1, -1))
    result = round(float(_regmodel.predict(scaled)[0]), 2)
    _log_prediction(features, result, source)
    return result


def predict_from_dict(data: dict) -> float:
    """Return the predicted price given a dict with FEATURE_ORDER keys."""
    features = [float(data[f]) for f in FEATURE_ORDER]
    return predict_from_list(features, source="api")
