# Implementación de Monitoreo con MLflow

Dashboard de monitoreo de predicciones ML para el pipeline CI/CD — Universidad EAFIT 2026.

---

## Por qué MLflow para este proyecto

El proyecto ya tiene CI/CD completo, pero no tiene visibilidad sobre el comportamiento del
modelo en producción. MLflow resuelve exactamente eso:

| Necesidad | Lo que da MLflow |
|-----------|-----------------|
| Ver cada predicción que llega | **Tracking de runs** — cada llamada a `/predict` es un run |
| Detectar si los inputs cambian con el tiempo | **Log de parámetros** — los 13 features por request |
| Monitorear el rango de precios predichos | **Log de métricas** — precio predicho como métrica |
| Dashboard visual en el navegador | **MLflow UI** — servida desde el tracking server |
| Persitencia entre deployments | **S3 como artifact store** — ya tenemos S3 en el stack |

---

## Arquitectura propuesta

```
┌─────────────────────────────────────────────────────────┐
│  Usuario → ALB (staging/prod) → ECS Flask App           │
│                │                                         │
│                │ mlflow.start_run()                      │
│                │ mlflow.log_params(features)             │
│                ▼ mlflow.log_metric("predicted_price")    │
│  ┌─────────────────────────────────────────────────┐    │
│  │  MLflow Tracking Server (ECS Fargate)           │    │
│  │  - Backend: SQLite en /tmp (efímero, para demo) │    │
│  │  - Artifacts: S3 bucket dedicado                │    │
│  │  - Puerto: 5000                                 │    │
│  │  - Expuesto vía ALB → Dashboard en navegador    │    │
│  └─────────────────────────────────────────────────┘    │
│                │                                         │
│                ▼                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │  S3 Bucket: mlflow-artifacts-<proyecto>         │    │
│  │  experiments/ runs/ artifacts/ modelos/         │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

**Nota sobre la persistencia:** Se usa SQLite efímero (en el contenedor) para el backend
de metadatos y S3 para artefactos. Si el task de MLflow se reinicia, los runs anteriores
desaparecen del UI pero los artefactos persisten en S3. Para un proyecto académico de
demostración esto es suficiente. Una solución productiva usaría RDS como backend.

---

## Qué se registra por cada predicción

Cada llamada a `/predict` o `/predict_api` genera un MLflow run con:

| Tipo | Nombre | Ejemplo |
|------|--------|---------|
| **Param** | `CRIM` | `0.00632` |
| **Param** | `ZN` | `18.0` |
| **Param** | `INDUS` | `2.31` |
| **Param** | `CHAS` | `0` |
| **Param** | `NOX` | `0.538` |
| **Param** | `RM` | `6.575` |
| **Param** | `AGE` | `65.2` |
| **Param** | `DIS` | `4.09` |
| **Param** | `RAD` | `1` |
| **Param** | `TAX` | `296.0` |
| **Param** | `PTRATIO` | `15.3` |
| **Param** | `B` | `396.9` |
| **Param** | `LSTAT` | `4.98` |
| **Metric** | `predicted_price` | `32.37` |
| **Tag** | `environment` | `production` |
| **Tag** | `source` | `web_form` o `api` |

---

## Pasos de implementación

### Paso 1 — Agregar MLflow a `requirements.txt`

Añadir una línea al final:

```
mlflow==2.13.0
```

> `2.13.0` es la última versión estable compatible con Python 3.12 y scikit-learn 1.6.

---

### Paso 2 — Modificar `app/predictor.py`

Agregar logging de MLflow en las funciones de predicción. El tracking URI se configura
desde una variable de entorno para que en local no necesite servidor.

```python
"""ML prediction logic for Boston House Pricing."""

import os
import pickle

import mlflow
import numpy as np

FEATURE_ORDER = [
    "CRIM", "ZN", "INDUS", "CHAS", "NOX", "RM",
    "AGE", "DIS", "RAD", "TAX", "PTRATIO", "B", "LSTAT",
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
```

**Cambio en `app/app.py`:** pasar `source="web_form"` en la ruta `/predict`:

```python
@app.route("/predict", methods=["POST"])
def predict():
    """Accept form data and render the prediction result."""
    features = [float(request.form[f]) for f in FEATURE_ORDER]
    output = predict_from_list(features, source="web_form")
    return render_template("home.html", prediction=output)
```

---

### Paso 3 — Agregar recursos Terraform para el MLflow Server

Añadir al final de `infra/main.tf`:

```hcl
# ─── MLflow Tracking Server ───────────────────────────────────────────────────

resource "aws_s3_bucket" "mlflow_artifacts" {
  bucket = "mlflow-artifacts-${var.project_name}-${var.environment_name}"
  tags   = { Environment = var.environment_name }
}

resource "aws_cloudwatch_log_group" "mlflow_logs" {
  name              = "/ecs/${var.project_name}-${var.environment_name}-mlflow"
  retention_in_days = 7
  tags              = { Environment = var.environment_name }
}

resource "aws_security_group" "mlflow_alb_sg" {
  name        = "${var.project_name}-mlflow-alb-sg-${var.environment_name}"
  description = "HTTP access to MLflow UI"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "mlflow_ecs_sg" {
  name        = "${var.project_name}-mlflow-ecs-sg-${var.environment_name}"
  description = "MLflow server container traffic"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.mlflow_alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "mlflow" {
  name               = "${var.project_name}-${var.environment_name}-mlflow-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.mlflow_alb_sg.id]
  subnets            = var.subnet_ids
}

resource "aws_lb_target_group" "mlflow_tg" {
  name        = "${var.project_name}-mlflow-tg-${var.environment_name}"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    port                = "5000"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 10
    matcher             = "200"
  }
}

resource "aws_lb_listener" "mlflow_http" {
  load_balancer_arn = aws_lb.mlflow.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mlflow_tg.arn
  }
}

resource "aws_ecs_task_definition" "mlflow" {
  family                   = "${var.project_name}-${var.environment_name}-mlflow"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  task_role_arn            = var.lab_role_arn
  execution_role_arn       = var.lab_role_arn

  container_definitions = jsonencode([
    {
      name  = "mlflow-server"
      image = "ghcr.io/mlflow/mlflow:v2.13.0"

      command = [
        "mlflow", "server",
        "--host", "0.0.0.0",
        "--port", "5000",
        "--default-artifact-root", "s3://${aws_s3_bucket.mlflow_artifacts.bucket}/artifacts",
        "--backend-store-uri", "sqlite:////tmp/mlflow.db"
      ]

      portMappings = [{ containerPort = 5000, protocol = "tcp" }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.mlflow_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "mlflow"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "mlflow" {
  name            = "${var.project_name}-${var.environment_name}-mlflow-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.mlflow.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.mlflow_ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.mlflow_tg.arn
    container_name   = "mlflow-server"
    container_port   = 5000
  }

  depends_on = [aws_lb_listener.mlflow_http]
}
```

Añadir al final de `infra/outputs.tf`:

```hcl
output "mlflow_url" {
  description = "URL del MLflow Tracking Server"
  value       = "http://${aws_lb.mlflow.dns_name}/"
}
```

---

### Paso 4 — Pasar variables de entorno a la tarea ECS de la app Flask

En `infra/main.tf`, en el `container_definitions` del task de la app Flask,
agregar dos variables de entorno junto al `FLASK_SECRET_KEY` existente:

```hcl
environment = [
  { name = "FLASK_SECRET_KEY", value = var.secret_key },
  { name = "MLFLOW_TRACKING_URI", value = "http://${aws_lb.mlflow.dns_name}/" },
  { name = "ENVIRONMENT",         value = var.environment_name }
]
```

---

### Paso 5 — Actualizar el pipeline de GitHub Actions

En `.github/workflows/main.yaml`, en los steps de `Terraform Apply` de los jobs
`deploy-tf-staging` y `deploy-tf-prod`, agregar la lectura del output del MLflow server
y pasarlo como output del job. No se necesita un job separado — el `terraform apply`
ya despliega el MLflow server junto con la app porque está en el mismo `main.tf`.

Añadir al step `Get Terraform Outputs (Staging)`:

```yaml
- name: Get Terraform Outputs (Staging)
  id: get_tf_outputs
  working-directory: infra
  run: |
    ALB_URL=$(terraform output -raw alb_url)
    ECS_CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
    ECS_SERVICE_NAME=$(terraform output -raw ecs_service_name)
    MLFLOW_URL=$(terraform output -raw mlflow_url)
    echo "alb_url=${ALB_URL}" >> $GITHUB_OUTPUT
    echo "ecs_cluster_name=${ECS_CLUSTER_NAME}" >> $GITHUB_OUTPUT
    echo "ecs_service_name=${ECS_SERVICE_NAME}" >> $GITHUB_OUTPUT
    echo "mlflow_url=${MLFLOW_URL}" >> $GITHUB_OUTPUT
```

Añadir al summary del job para que la URL quede visible en el log de GitHub Actions:

```yaml
- name: Print Dashboard URLs
  run: |
    echo "### URLs del entorno" >> $GITHUB_STEP_SUMMARY
    echo "- **App:** ${{ steps.get_tf_outputs.outputs.alb_url }}" >> $GITHUB_STEP_SUMMARY
    echo "- **MLflow Dashboard:** ${{ steps.get_tf_outputs.outputs.mlflow_url }}" >> $GITHUB_STEP_SUMMARY
```

---

### Paso 6 — Verificar el monitoreo

Una vez desplegado, acceder al MLflow Dashboard via la URL del ALB del MLflow server.

**Lo que se verá en la UI:**

1. **Experiments** → `boston-house-predictions` (se crea automáticamente)
2. **Runs** → una fila por cada predicción realizada
3. **Columns:** timestamp, `predicted_price`, environment, source
4. **Charts:** seleccionar `predicted_price` para ver la distribución a lo largo del tiempo
5. **Compare runs:** seleccionar múltiples runs para comparar features de entrada

**Prueba rápida post-deploy:**

```bash
# Hacer algunas predicciones contra la app en producción para poblar el dashboard
curl -X POST http://<APP_ALB_URL>/predict_api \
  -H "Content-Type: application/json" \
  -d '{"data":{"CRIM":0.00632,"ZN":18,"INDUS":2.31,"CHAS":0,"NOX":0.538,"RM":6.575,"AGE":65.2,"DIS":4.09,"RAD":1,"TAX":296,"PTRATIO":15.3,"B":396.9,"LSTAT":4.98}}'

# Luego abrir el MLflow Dashboard en el navegador
open http://<MLFLOW_ALB_URL>/
```

---

## Resumen de cambios por archivo

| Archivo | Cambio |
|---------|--------|
| `requirements.txt` | Añadir `mlflow==2.13.0` |
| `app/predictor.py` | Añadir `_log_prediction()`, actualizar `predict_from_list()` y `predict_from_dict()` |
| `app/app.py` | Pasar `source="web_form"` en la ruta `/predict` |
| `infra/main.tf` | Añadir S3 bucket, ECS service, ALB y SG para MLflow server |
| `infra/outputs.tf` | Añadir output `mlflow_url` |
| `.github/workflows/main.yaml` | Leer y mostrar `mlflow_url` en los outputs de los jobs de Terraform |

---

## Consideraciones para el entregable

- El MLflow Dashboard es el "monitoring dashboard" pedido por el profesor
- Se puede mostrar en vivo haciendo predicciones y luego abriendo la UI
- La URL del dashboard debe quedar en el README junto a las URLs del ALB de la app
- El logging es **no-bloqueante**: si el servidor MLflow cae, las predicciones siguen funcionando

---

*Documento creado el 2026-04-24 | Universidad EAFIT — Materia CI/CD*
