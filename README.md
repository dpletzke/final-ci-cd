# Trabajo Final CI/CD — Boston House Price Prediction

Aplicación web de predicción de precios de vivienda desarrollada como proyecto final de la materia **CI/CD** en la **Universidad EAFIT**. El modelo de regresión lineal fue entrenado sobre el dataset *Boston Housing* y se sirve mediante una API REST construida con Flask, con pipeline de integración y entrega continua vía GitHub Actions y contenedores Docker.

---

## Estructura del proyecto

```
boston_house_pricing/
├── .github/
│   └── workflows/
│       └── main.yaml          <- Pipeline CI/CD
│
├── app/                       <- Paquete Python de la aplicación
│   ├── __init__.py            <- Marca el directorio como paquete
│   ├── app.py                 <- Rutas Flask (/, /health, /predict, /predict_api)
│   └── predictor.py           <- Lógica de predicción ML (separada de las rutas)
│
├── models/                    <- Artefactos del modelo entrenado
│   ├── regmodel.pkl           <- Modelo de regresión lineal serializado
│   └── scaling.pkl            <- StandardScaler serializado
│
├── tests/                     <- Suite de pruebas
│   ├── test_app.py            <- Tests unitarios de rutas Flask (5 tests)
│   ├── test_predictor.py      <- Tests unitarios de lógica ML (8 tests)
│   ├── test_acceptance_app.py <- Tests de aceptación Selenium (staging)
│   └── test_smoke_app.py      <- Tests de humo Selenium (producción)
│
├── front/                     <- Templates HTML (Flask)
│   └── home.html              <- Interfaz web de predicción
│
├── static/                    <- Assets estáticos
│   └── images/
│       └── Logo_EAFIT.svg.png
│
├── notebooks/                 <- Exploración y entrenamiento del modelo
│   └── notebook.ipynb
│
├── .dockerignore              <- Archivos excluidos de la imagen Docker
├── .flake8                    <- Configuración de Flake8 (max-line-length=88)
├── Dockerfile                 <- Imagen Docker (Python 3.12-slim, puerto 8000)
├── pytest.ini                 <- Configuración de pytest + cobertura
├── requirements.txt           <- Dependencias Python (app + herramientas dev)
└── README.md
```

---

## Stack tecnológico

| Capa | Tecnología |
|---|---|
| Modelo ML | scikit-learn 1.6.1 — Regresión Lineal |
| Backend | Flask 3.1.1 |
| Servidor WSGI | Gunicorn 23.0.0 |
| Contenedor | Docker (Python 3.12-slim) |
| Registro de imágenes | Docker Hub |
| CI/CD | GitHub Actions |
| Infraestructura (target) | AWS ECS Fargate + ALB (vía Terraform) |
| Calidad de código | Black · Pylint · Flake8 |
| Testing | pytest · pytest-cov · Selenium |
| Análisis estático | SonarCloud |

---

## Requisitos previos

- Python 3.12+
- pip
- (Opcional) Docker para correr la imagen localmente

---

## Instalación y ejecución local

**1. Clonar el repositorio**
```bash
git clone <url-del-repositorio>
cd boston_house_pricing
```

**2. Crear y activar un entorno virtual**
```bash
python -m venv venv
source venv/Scripts/activate   # Windows (Git Bash)
source venv/bin/activate        # macOS / Linux
```

**3. Instalar las dependencias**
```bash
pip install -r requirements.txt
```

**4. Ejecutar la aplicación**
```bash
python -m app.app
```

La aplicación estará disponible en `http://localhost:8000`.

> También se puede lanzar con Gunicorn directamente:
> `gunicorn --workers=4 --bind=0.0.0.0:8000 app.app:app`

---

## Endpoints

### `GET /`
Renderiza el formulario de predicción en el navegador.

### `GET /health`
Health check para el ALB de AWS ECS. Devuelve `OK` con HTTP 200.

### `POST /predict`
Recibe los 13 atributos vía formulario HTML y devuelve la predicción renderizada en la página.

### `POST /predict_api`
Recibe un JSON y devuelve la predicción como número.

**Request:**
```json
{
  "data": {
    "CRIM": 0.00632, "ZN": 18.0, "INDUS": 2.31, "CHAS": 0,
    "NOX": 0.538, "RM": 6.575, "AGE": 65.2, "DIS": 4.09,
    "RAD": 1, "TAX": 296.0, "PTRATIO": 15.3, "B": 396.9, "LSTAT": 4.98
  }
}
```

**Response:** `32.37` *(precio en miles de USD, base 1978)*

---

## Pruebas y calidad de código

### Ejecutar los tests unitarios
```bash
pytest --ignore=tests/test_acceptance_app.py --ignore=tests/test_smoke_app.py
```

### Ejecutar todos los checks de calidad
```bash
# Formateo (Black)
black app --check

# Linting (Pylint) — objetivo: score >= 9.0
pylint app

# Estilo PEP 8 (Flake8)
flake8 app
```

> Los tests de aceptación (`test_acceptance_app.py`) y humo (`test_smoke_app.py`) usan
> Selenium y requieren una instancia de la app corriendo. Se ejecutan en el pipeline de CI/CD
> contra los entornos de staging y producción respectivamente, usando la variable de entorno
> `APP_BASE_URL`.

### Resultados locales actuales
| Check | Resultado |
|---|---|
| Black | ✅ Sin cambios |
| Pylint | ✅ 10.00/10 |
| Flake8 | ✅ Sin errores |
| pytest (13 tests unitarios) | ✅ 13/13 PASSED |
| Cobertura | ✅ 95% |

---

## Variables del modelo

| Variable | Descripción | Rango |
|---|---|---|
| CRIM | Tasa de criminalidad per cápita | 0.006 – 88.976 |
| ZN | % de terreno residencial para lotes > 25,000 ft² | 0 – 100 |
| INDUS | % de hectáreas de negocio no minorista | 0.46 – 27.74 |
| CHAS | Limita con el río Charles (1 = sí, 0 = no) | 0 o 1 |
| NOX | Concentración de óxidos de nitrógeno (ppm × 10) | 0.385 – 0.871 |
| RM | Promedio de habitaciones por vivienda | 3.56 – 8.78 |
| AGE | % de unidades construidas antes de 1940 | 2.9 – 100 |
| DIS | Distancia ponderada a centros de empleo | 1.13 – 12.13 |
| RAD | Índice de acceso a autopistas radiales | 1 – 24 |
| TAX | Tasa de impuesto sobre la propiedad (por $10,000) | 187 – 711 |
| PTRATIO | Ratio alumnos/maestro por ciudad | 12.6 – 22.0 |
| B | Índice demográfico 1000×(Bk−0.63)² | 0.32 – 396.9 |
| LSTAT | % de población de menor estatus socioeconómico | 1.73 – 37.97 |

---

## Pipeline CI/CD

### Estado actual — Pipeline en progreso

El pipeline objetivo es de **7 jobs** organizado en dos fases:

```
push a main
     │
     ▼
Job 1: build-test-publish  ← Black + Pylint + Flake8 + pytest + SonarCloud + Docker Hub
     │
     ▼
Job 2: deploy-tf-staging   ← Terraform apply (staging en AWS ECS Fargate)
     │
     ▼
Job 3: update-service-staging  ← aws ecs update-service + wait
     │
     ▼
Job 4: test-staging        ← pytest tests/test_acceptance_app.py (contra staging ALB)
     │
     ▼
Job 5: deploy-tf-prod      ← Terraform apply (producción en AWS ECS Fargate)
     │
     ▼
Job 6: update-service-prod ← aws ecs update-service + wait
     │
     ▼
Job 7: smoke-test-prod     ← pytest tests/test_smoke_app.py (contra prod ALB)
```

> El workflow actual (`.github/workflows/main.yaml`) todavía usa el pipeline legacy de Heroku.
> La migración al pipeline completo de 7 jobs es el próximo paso pendiente de implementación.

### Secrets requeridos en GitHub (pipeline completo)

| Secret | Descripción |
|---|---|
| `AWS_ACCESS_KEY_ID` | Credencial de acceso programático AWS |
| `AWS_SECRET_ACCESS_KEY` | Clave secreta AWS |
| `AWS_SESSION_TOKEN` | Token de sesión AWS Academy (se renueva cada 4 h) |
| `SONAR_TOKEN` | Token de análisis de SonarCloud |
| `DOCKERHUB_TOKEN` | Token de acceso a Docker Hub |
| `SECRET_KEY` | Clave secreta de Flask |

### Variables de repositorio requeridas

| Variable | Ejemplo | Descripción |
|---|---|---|
| `DOCKERHUB_USERNAME` | `alejandropelaez` | Usuario de Docker Hub |
| `TF_STATE_BUCKET` | `boston-tf-state-12345` | Bucket S3 para estado de Terraform |
| `LAB_ROLE_ARN` | `arn:aws:iam::123456789012:role/LabRole` | ARN del rol IAM de AWS Academy |
| `VPC_ID` | `vpc-0abc12345` | ID de la VPC por defecto |
| `SUBNET_IDS` | `subnet-aaa111,subnet-bbb222` | IDs de subredes públicas (separadas por coma) |

---

## Universidad EAFIT · Materia CI/CD · 2025
