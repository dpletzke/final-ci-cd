# tests/test_predictor.py
from unittest.mock import MagicMock, patch

import pytest

from app.predictor import FEATURE_ORDER, predict_from_dict, predict_from_list

_SAMPLE = [
    0.00632,
    18.0,
    2.31,
    0,
    0.538,
    6.575,
    65.2,
    4.09,
    1,
    296.0,
    15.3,
    396.9,
    4.98,
]
_SAMPLE_DICT = dict(zip(FEATURE_ORDER, _SAMPLE))


def test_feature_order_has_13_elements():
    """FEATURE_ORDER must contain exactly 13 features."""
    assert len(FEATURE_ORDER) == 13


def test_feature_order_contains_expected_names():
    """Spot-check key feature names."""
    assert "CRIM" in FEATURE_ORDER
    assert "RM" in FEATURE_ORDER
    assert "LSTAT" in FEATURE_ORDER
    assert "AGE" in FEATURE_ORDER


def test_predict_from_list_returns_float():
    """predict_from_list must return a float."""
    result = predict_from_list(_SAMPLE)
    assert isinstance(result, float)


def test_predict_from_list_positive():
    """Predicted price must be positive."""
    assert predict_from_list(_SAMPLE) > 0


def test_predict_known_value():
    """First Boston dataset row should predict between 30 and 35."""
    result = predict_from_list(_SAMPLE)
    assert 30.0 < result < 35.0


def test_predict_from_dict_equals_from_list():
    """Both interfaces must return the same value for the same input."""
    assert predict_from_list(_SAMPLE) == predict_from_dict(_SAMPLE_DICT)


def test_more_rooms_higher_price():
    """Increasing RM (rooms) should increase the predicted price."""
    low_rm = _SAMPLE.copy()
    high_rm = _SAMPLE.copy()
    rm_idx = FEATURE_ORDER.index("RM")
    low_rm[rm_idx] = 4.0
    high_rm[rm_idx] = 8.0
    assert predict_from_list(high_rm) > predict_from_list(low_rm)


def test_high_crime_lower_price():
    """Increasing CRIM (crime rate) should decrease the predicted price."""
    low_crime = _SAMPLE.copy()
    high_crime = _SAMPLE.copy()
    crim_idx = FEATURE_ORDER.index("CRIM")
    low_crime[crim_idx] = 0.00632
    high_crime[crim_idx] = 88.976
    assert predict_from_list(low_crime) > predict_from_list(high_crime)


def test_mlflow_logging_called_when_uri_configured():
    """predict_from_list logs to MLflow when MLFLOW_TRACKING_URI is set."""
    mock_run = MagicMock()
    mock_run.__enter__ = lambda s: s
    mock_run.__exit__ = MagicMock(return_value=False)

    with patch("app.predictor._MLFLOW_URI", "http://fake-mlflow:5000/"), patch(
        "mlflow.start_run", return_value=mock_run
    ), patch("mlflow.log_params") as mock_params, patch(
        "mlflow.log_metric"
    ) as mock_metric, patch(
        "mlflow.set_tags"
    ):
        result = predict_from_list(_SAMPLE, source="web_form")
        assert result > 0
        mock_params.assert_called_once()
        mock_metric.assert_called_once_with("predicted_price", result)


def test_mlflow_failure_does_not_break_prediction():
    """predict_from_list returns a value even if MLflow logging raises."""
    with patch("app.predictor._MLFLOW_URI", "http://fake-mlflow:5000/"), patch(
        "mlflow.start_run", side_effect=Exception("MLflow unavailable")
    ):
        result = predict_from_list(_SAMPLE)
        assert isinstance(result, float)
        assert result > 0
