"""Prometheus metrics for the Boston House Pricing app."""

import time

from flask import Response, g, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram
from prometheus_client import generate_latest

HTTP_REQUESTS = Counter(
    "boston_http_requests_total",
    "Total HTTP requests served by the Flask app.",
    ["method", "endpoint", "status"],
)

HTTP_REQUEST_LATENCY = Histogram(
    "boston_http_request_duration_seconds",
    "HTTP request latency in seconds.",
    ["method", "endpoint"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10),
)

PREDICTIONS = Counter(
    "boston_prediction_total",
    "Total predictions served by source and environment.",
    ["source", "environment"],
)

MLFLOW_LOG_FAILURES = Counter(
    "boston_mlflow_log_failures_total",
    "Total MLflow prediction logging failures.",
    ["environment"],
)

PREDICTED_PRICE = Gauge(
    "boston_predicted_price",
    "Latest predicted price observed by source and environment.",
    ["source", "environment"],
)


def _endpoint_name() -> str:
    """Return a stable low-cardinality endpoint label."""
    if request.endpoint:
        return request.endpoint
    return "unknown"


def init_metrics(app):
    """Register Prometheus hooks and the /metrics endpoint on a Flask app."""

    @app.before_request
    def _start_timer():
        g.metrics_start_time = time.perf_counter()

    @app.after_request
    def _record_request(response):
        if request.path == "/metrics":
            return response

        latency = time.perf_counter() - getattr(
            g, "metrics_start_time", time.perf_counter()
        )
        endpoint = _endpoint_name()
        method = request.method
        status = str(response.status_code)

        HTTP_REQUESTS.labels(method=method, endpoint=endpoint, status=status).inc()
        HTTP_REQUEST_LATENCY.labels(method=method, endpoint=endpoint).observe(latency)
        return response

    @app.route("/metrics", methods=["GET"])
    def metrics():
        """Expose Prometheus metrics."""
        return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)
