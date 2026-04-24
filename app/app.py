"""Flask application for the Boston House Pricing web interface."""

import os

from flask import Flask, jsonify, render_template, request

from .predictor import FEATURE_ORDER, predict_from_dict, predict_from_list

_ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

app = Flask(
    __name__,
    template_folder=os.path.join(_ROOT_DIR, "front"),
    static_folder=os.path.join(_ROOT_DIR, "static"),
)
app.secret_key = os.environ.get("FLASK_SECRET_KEY", "dev-only-insecure-key")


@app.route("/", methods=["GET"])
def home():
    """Render the prediction form."""
    return render_template("home.html")


@app.route("/health", methods=["GET"])
def health():
    """Return OK for ECS ALB health checks."""
    return "OK", 200


@app.route("/predict_api", methods=["POST"])
def predict_api():
    """Accept JSON and return the predicted price as a float."""
    data = request.json["data"]
    output = predict_from_dict(data)
    return jsonify(output)


@app.route("/predict", methods=["POST"])
def predict():
    """Accept form data and render the prediction result."""
    features = [float(request.form[f]) for f in FEATURE_ORDER]
    output = predict_from_list(features, source="web_form")
    return render_template("home.html", prediction=output)


if __name__ == "__main__":
    app.run(debug=False, host="127.0.0.1", port=8000)
