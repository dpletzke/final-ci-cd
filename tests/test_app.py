# tests/test_app.py
import pytest

from app.app import app as flask_app


@pytest.fixture
def client():
    """Return a Flask test client configured for testing."""
    flask_app.config["TESTING"] = True
    with flask_app.test_client() as test_client:
        yield test_client


def test_home_get(client):
    """GET / returns 200 and an HTML page."""
    response = client.get("/")
    assert response.status_code == 200
    assert b"<!DOCTYPE html>" in response.data


def test_health_endpoint(client):
    """GET /health returns 200 with body 'OK'."""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.data == b"OK"


def test_predict_api_returns_positive_float(client):
    """POST /predict_api with valid data returns a positive float."""
    payload = {
        "data": {
            "CRIM": 0.00632,
            "ZN": 18.0,
            "INDUS": 2.31,
            "CHAS": 0,
            "NOX": 0.538,
            "RM": 6.575,
            "AGE": 65.2,
            "DIS": 4.09,
            "RAD": 1,
            "TAX": 296.0,
            "PTRATIO": 15.3,
            "B": 396.9,
            "LSTAT": 4.98,
        }
    }
    response = client.post("/predict_api", json=payload)
    assert response.status_code == 200
    result = response.get_json()
    assert isinstance(result, float)
    assert result > 0


def test_predict_api_known_value(client):
    """First Boston dataset row should predict between 30 and 35."""
    payload = {
        "data": {
            "CRIM": 0.00632,
            "ZN": 18.0,
            "INDUS": 2.31,
            "CHAS": 0,
            "NOX": 0.538,
            "RM": 6.575,
            "AGE": 65.2,
            "DIS": 4.09,
            "RAD": 1,
            "TAX": 296.0,
            "PTRATIO": 15.3,
            "B": 396.9,
            "LSTAT": 4.98,
        }
    }
    response = client.post("/predict_api", json=payload)
    result = response.get_json()
    assert 30.0 < result < 35.0


def test_predict_form_returns_prediction(client):
    """POST /predict renders a page containing the predicted value."""
    form_data = {
        "CRIM": "0.00632",
        "ZN": "18.0",
        "INDUS": "2.31",
        "CHAS": "0",
        "NOX": "0.538",
        "RM": "6.575",
        "AGE": "65.2",
        "DIS": "4.09",
        "RAD": "1",
        "TAX": "296.0",
        "PTRATIO": "15.3",
        "B": "396.9",
        "LSTAT": "4.98",
    }
    response = client.post("/predict", data=form_data)
    assert response.status_code == 200
    assert b"32" in response.data
