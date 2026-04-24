# Pasos a seguir v1 — Migración de boston_house_pricing al stack CI/CD del proyecto ejemplo

Este documento describe, en orden de ejecución, todos los cambios que deben realizarse sobre el proyecto `boston_house_pricing` para llevarlo al mismo nivel del proyecto de ejemplo `proyecto-ejemplo-ci-cd`. El objetivo final es tener un pipeline CI/CD completo con: calidad de código, tests unitarios/aceptación/humo, SonarCloud, imagen Docker en Docker Hub, e infraestructura en AWS ECS Fargate gestionada con Terraform.

---

## 0. Tabla comparativa — Estado actual

| Componente | proyecto-ejemplo | boston_house_pricing | Estado |
|---|:---:|:---:|---|
| Paquete `app/` con `__init__.py` | ✅ | ✅ | Completado |
| Módulo de lógica separado (`predictor.py`) | ✅ `calculadora.py` | ✅ `predictor.py` | Completado |
| Endpoint `/health` | ✅ | ✅ | Completado |
| Tests unitarios (`tests/`) | ✅ | ✅ 15 tests | Completado |
| Tests de aceptación con Selenium | ✅ | ✅ | Completado |
| Tests de humo con Selenium | ✅ | ✅ | Completado |
| `pytest.ini` con coverage + HTML | ✅ | ✅ | Completado |
| Black (formateador) | ✅ | ✅ | Completado |
| Pylint (linter) | ✅ | ✅ 10.00/10 | Completado |
| Flake8 (linter) | ✅ | ✅ | Completado |
| `.flake8` con configuración | ✅ | ✅ | Completado |
| `.dockerignore` | ✅ | ✅ | Completado |
| Dockerfile optimizado (port 8000 fijo) | ✅ | ✅ | Completado |
| `requirements.txt` con herramientas dev | ✅ | ✅ | Completado |
| `.gitignore` con entradas de Terraform | ✅ | ✅ | Completado |
| `sonar-project.properties` | ✅ | ✅ | Completado |
| Infraestructura Terraform (`infra/`) | ✅ | ✅ | **Completado** |
| MLflow tracking server (monitoreo ML) | ❌ No lo usa | ✅ | **Completado (valor agregado)** |
| Pipeline CI/CD completo (GitHub Actions) | ✅ 7 jobs | ✅ 7 jobs | **Completado** |
| Docker Hub como registro de imágenes | ✅ | ✅ | Completado |
| Entorno Staging (ECS Fargate) | ✅ | ✅ | **Completado** |
| Entorno Production (ECS Fargate) | ✅ | ✅ | **Completado** |
| Secrets AWS + SonarCloud + DockerHub | ✅ | ✅ | **Completado** |
| `Procfile` (Heroku) | ❌ No lo usa | ❌ Eliminado | Completado |

---

## Visión general del pipeline final

```
push a main
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│ Job 1: build-test-publish (CI)                              │
│  ├── Setup Python 3.12                                       │
│  ├── pip install -r requirements.txt                         │
│  ├── black app --check                                       │
│  ├── pylint app --fail-under=9                               │
│  ├── flake8 app                                              │
│  ├── pytest (solo unitarios, con coverage)                   │
│  ├── Upload artefactos (report.html, htmlcov/)               │
│  ├── SonarCloud Scan                                         │
│  └── Build + Push imagen Docker → Docker Hub                 │
└───────────────────┬─────────────────────────────────────────┘
                    │ (solo push a main)
                    ▼
┌─────────────────────────────────────────────────────────────┐
│ Job 2: deploy-tf-staging                                    │
│  ├── AWS credentials (con session token)                     │
│  ├── Crear/verificar bucket S3 para estado Terraform         │
│  ├── terraform init  (key: staging/terraform.tfstate)        │
│  └── terraform apply -var="docker_image_uri=..." staging     │
└───────────────────┬─────────────────────────────────────────┘
                    ▼
┌─────────────────────────────────────────────────────────────┐
│ Job 3: update-service-staging                               │
│  └── aws ecs update-service --force-new-deployment          │
│      + aws ecs wait services-stable                          │
└───────────────────┬─────────────────────────────────────────┘
                    ▼
┌─────────────────────────────────────────────────────────────┐
│ Job 4: test-staging (pruebas de aceptación con Selenium)    │
│  └── pytest tests/test_acceptance_app.py                    │
│      (contra la URL del ALB de staging)                      │
└───────────────────┬─────────────────────────────────────────┘
                    ▼ (solo si test-staging pasa)
┌─────────────────────────────────────────────────────────────┐
│ Job 5: deploy-tf-prod                                       │
│  └── terraform apply -var="..." production                   │
└───────────────────┬─────────────────────────────────────────┘
                    ▼
┌─────────────────────────────────────────────────────────────┐
│ Job 6: update-service-prod                                  │
│  └── aws ecs update-service --force-new-deployment prod      │
└───────────────────┬─────────────────────────────────────────┘
                    ▼
┌─────────────────────────────────────────────────────────────┐
│ Job 7: smoke-test-prod (pruebas de humo con Selenium)       │
│  └── pytest tests/test_smoke_app.py                         │
│      (contra la URL del ALB de producción)                   │
└─────────────────────────────────────────────────────────────┘
```

---

## Fase A — Integración Continua (CI) — Equivalente al Entregable 2

### ✅ Paso 1 — Reestructurar la aplicación como paquete Python

**Estado: COMPLETADO**

Se creó la estructura `app/` con los siguientes archivos:
- `app/__init__.py` — vacío, marca el directorio como paquete Python
- `app/predictor.py` — lógica de predicción ML extraída de `app.py`, carga los modelos con context managers
- `app/app.py` — rutas Flask con paths absolutos, endpoint `/health`, lectura de formulario por nombre de campo

También se eliminaron:
- `app.py` de la raíz (reemplazado por `app/app.py`)
- `Procfile` (era exclusivo de Heroku)

Se corrigió un bug en `front/home.html`: el campo AGE tenía `name="Age"` en lugar de `name="AGE"`, lo que causaría un `KeyError` al leer `request.form["AGE"]`.

---

### ✅ Paso 2 — Actualizar `requirements.txt`

**Estado: COMPLETADO**

El `requirements.txt` actual incluye todas las herramientas necesarias:

```txt
Flask==3.1.1
gunicorn==23.0.0
scikit-learn==1.6.1
pandas==2.1.4
numpy==1.26.4
matplotlib==3.10.3
seaborn==0.13.2
black
pylint
flake8
pytest
pytest-cov
pytest-html
coverage
selenium
webdriver-manager
```

---

### ✅ Paso 3 — Mejorar el `Dockerfile` y crear `.dockerignore`

**Estado: COMPLETADO**

El `Dockerfile` actual usa:
- Imagen base `python:3.12-slim`
- Copia `requirements.txt` primero (aprovecha caché de Docker)
- `--no-cache-dir` para reducir tamaño
- Puerto fijo `8000`
- CMD en formato JSON: `["gunicorn", "--workers=4", "--bind=0.0.0.0:8000", "app.app:app"]`

El `.dockerignore` excluye: `.git`, venvs, `__pycache__`, `notebooks`, `Docs`, `infra`, `tests`, archivos de coverage y reportes.

---

### ✅ Paso 4 — Crear `pytest.ini`

**Estado: COMPLETADO**

```ini
[pytest]
pythonpath = .
addopts = -v --color=yes --tb=short --cov=app --cov-report=term-missing --cov-report=html --cov-report=xml --cov-branch --html=report.html --self-contained-html
testpaths = tests
norecursedirs = .git venv env ci-cd-env .* _* build dist htmlcov .github infra notebooks
```

---

### ✅ Paso 5 — Escribir los tests

**Estado: COMPLETADO — 13/13 tests unitarios PASSED, cobertura 95%**

Archivos creados en `tests/`:

- **`test_app.py`** (5 tests) — rutas Flask: GET /, GET /health, POST /predict_api tipo y valor, POST /predict formulario
- **`test_predictor.py`** (8 tests) — lógica ML: FEATURE_ORDER, tipos de retorno, valor conocido, monotonías (RM y CRIM)
- **`test_acceptance_app.py`** — tests de aceptación Selenium contra staging (requiere `APP_BASE_URL` y Chrome)
- **`test_smoke_app.py`** — tests de humo Selenium contra producción (requiere `APP_BASE_URL` y Chrome)

Los tests de Selenium se ejecutan exclusivamente en el pipeline de CI/CD, no localmente.

---

### ✅ Paso 6 — Configurar herramientas de calidad de código

**Estado: COMPLETADO**

- **Black:** código formateado al estilo Black (doble comilla, 88 chars, comas finales en colecciones multilinea)
- **Pylint:** score **10.00/10** — docstrings en todos los módulos y funciones, sin imports no usados, context managers para I/O
- **Flake8:** sin errores — configurado en `.flake8` con `max-line-length = 88`

Para verificar localmente:
```bash
black app --check
pylint app
flake8 app
```

---

### ✅ Paso 7 — Configurar SonarCloud

**Estado: COMPLETADO** — `sonar-project.properties` creado con `projectKey=AlexanderPelaezJimenez_final-ci-cd` y `organization=alexanderpelaezjimenez`. Pipeline analizando correctamente, Quality Gate pasando. Se resolvieron dos issues: Blocker `S8392` (`host="0.0.0.0"` → `127.0.0.1`) y Hotspot CSRF marcado como "Safe" en el dashboard de SonarCloud.

**7.1 Crear cuenta y proyecto en SonarCloud:**
1. Ir a [sonarcloud.io](https://sonarcloud.io/) e iniciar sesión con la cuenta de GitHub
2. Crear una nueva organización vinculada al repositorio de GitHub
3. Crear un nuevo proyecto seleccionando el repositorio `boston_house_pricing`
4. Ir a **My Account → Security → Generate Tokens** → crear un token con nombre `SONAR_TOKEN`
5. Guardar el token (solo se muestra una vez)

**7.2 Crear `sonar-project.properties`** en la raíz del proyecto:

```properties
sonar.projectKey=<tu-usuario>_boston-house-pricing
sonar.organization=<tu-organizacion-sonar>
sonar.sources=app
sonar.python.version=3.12
sonar.python.pylint.reportPaths=pylint-report.txt
sonar.python.flake8.reportPaths=flake8-report.txt
sonar.coverage.exclusions=**/tests/**,app/__init__.py
sonar.python.coverage.reportPaths=coverage.xml
sonar.qualitygate.wait=true
sonar.qualitygate.timeout=300
```

> Reemplazar `<tu-usuario>` y `<tu-organizacion-sonar>` con los valores de tu cuenta de SonarCloud.

**7.3 Agregar el secret `SONAR_TOKEN` a GitHub:**
- Ir a GitHub → repositorio → **Settings → Secrets and variables → Actions → New repository secret**
- Nombre: `SONAR_TOKEN`, Valor: el token generado en el paso 7.1

---

### ✅ Paso 8 — Actualizar `.gitignore`

**Estado: COMPLETADO**

El `.gitignore` incluye:
- Archivos de coverage y reportes pytest (`htmlcov/`, `coverage.xml`, `.coverage`, `report.html`)
- Reportes de linters (`pylint-report.txt`, `flake8-report.txt`)
- Entradas de Terraform (`infra/.terraform/`, `*.tfvars`, etc.)
- `proyecto-ejemplo-ci-cd/` (referencia local)
- `Docs/` (documentación de desarrollo)

---

### ✅ Paso 9 — Reemplazar el workflow de CI en GitHub Actions

**Estado: COMPLETADO** — Pipeline CI (Job 1) desplegado y pasando en GitHub Actions (commit `234056b`). El workflow implementado sigue fielmente el ejemplo del Taller-Entregable-2, con tres adiciones propias del proyecto:
1. El step de acceptance tests incluye `--ignore=tests/test_smoke_app.py` (porque este proyecto tiene smoke tests separados)
2. El step SonarCloud incluye `SONAR_HOST_URL: ${{ vars.SONAR_HOST_URL }}` (configurado como variable de repositorio)
3. Se agrega el step `Set Job Outputs` al final para exponer `repo_name` e `image_tag` a los jobs de CD (Pasos 10–11)

El workflow real está en `.github/workflows/main.yaml`. El YAML a continuación es el borrador de referencia:

```yaml
name: CI/CD Pipeline — Boston House Pricing

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:

jobs:
  # ─────────────────────────────────────────────────────────────
  # Job 1: CI — Build, Test, Analyze, Publish Docker Image
  # ─────────────────────────────────────────────────────────────
  build-test-publish:
    runs-on: ubuntu-latest
    outputs:
      repo_name: ${{ steps.set_outputs.outputs.repo_name }}
      image_tag: ${{ steps.set_outputs.outputs.image_tag }}

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt

      - name: Run Black (Formatter check)
        run: black app --check

      - name: Run Pylint (Linter)
        run: pylint app --output-format=text --fail-under=9 > pylint-report.txt || true

      - name: Run Flake8 (Linter)
        run: flake8 app --output-file=flake8-report.txt || true

      - name: Run Unit Tests with pytest and Coverage
        run: |
          pytest --ignore=tests/test_acceptance_app.py --ignore=tests/test_smoke_app.py

      - name: Upload Test Reports Artifacts
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-reports
          path: |
            htmlcov/
            report.html

      - name: SonarCloud Scan
        uses: SonarSource/sonarqube-scan-action@v5.0.0
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}

      - name: Set up QEMU
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        uses: docker/setup-buildx-action@v3

      - name: Login to Docker Hub
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        uses: docker/login-action@v3
        with:
          username: ${{ vars.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Build and push Docker image
        id: docker_build_push
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        uses: docker/build-push-action@v5
        with:
          context: .
          file: ./Dockerfile
          push: true
          tags: |
            ${{ vars.DOCKERHUB_USERNAME }}/${{ github.event.repository.name }}:${{ github.sha }}
            ${{ vars.DOCKERHUB_USERNAME }}/${{ github.event.repository.name }}:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Set Job Outputs
        id: set_outputs
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        run: |
          echo "repo_name=${{ github.event.repository.name }}" >> $GITHUB_OUTPUT
          echo "image_tag=${{ github.sha }}" >> $GITHUB_OUTPUT
```

> **NOTA:** Este es solo el Job 1 (CI). Los jobs de CD (despliegue a AWS) se agregan en el Paso 11.

---

## Fase B — Entrega Continua (CD) — Equivalente al Entregable 3

### ✅ Paso 10 — Crear la infraestructura Terraform

**Estado: COMPLETADO** — La carpeta `infra/` contiene los tres archivos Terraform (`main.tf`, `variables.tf`, `outputs.tf`) que provisionan ECS Fargate + ALB para la app Flask y el servidor MLflow, con CloudWatch Logs, Security Groups y S3 para artefactos MLflow. El pipeline lo aplica automáticamente con `terraform apply` en los jobs 2 (staging) y 5 (producción).



Crear la carpeta `infra/` con tres archivos que definen toda la infraestructura AWS necesaria:
ECS Fargate + Application Load Balancer + Security Groups + CloudWatch Logs.

**10.1 `infra/variables.tf`**

```hcl
# infra/variables.tf

variable "environment_name" {
  description = "Nombre del entorno: staging o production."
  type        = string
  validation {
    condition     = contains(["staging", "production"], var.environment_name)
    error_message = "El entorno debe ser 'staging' o 'production'."
  }
}

variable "docker_image_uri" {
  description = "URI completo de la imagen Docker (ej: usuario/repo:sha)."
  type        = string
}

variable "lab_role_arn" {
  description = "ARN del rol IAM 'LabRole' de AWS Academy."
  type        = string
}

variable "vpc_id" {
  description = "ID de la VPC por defecto donde desplegar."
  type        = string
}

variable "subnet_ids" {
  description = "Lista de al menos 2 IDs de subredes públicas en diferentes AZs."
  type        = list(string)
}

variable "aws_region" {
  description = "Región de AWS."
  type        = string
  default     = "us-east-1"
}

variable "secret_key" {
  description = "Clave secreta para Flask. Nunca se imprime en logs."
  type        = string
  sensitive   = true
  default     = "dev-only-insecure-key"
}
```

**10.2 `infra/outputs.tf`**

```hcl
# infra/outputs.tf

output "alb_dns_name" {
  description = "DNS Name del Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_url" {
  description = "URL completa del ALB"
  value       = "http://${aws_lb.main.dns_name}/"
}

output "ecs_cluster_name" {
  description = "Nombre del ECS Cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Nombre del ECS Service"
  value       = aws_ecs_service.main.name
}
```

**10.3 `infra/main.tf`**

```hcl
# infra/main.tf

terraform {
  required_version = ">= 1.6.0"
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/boston-${var.environment_name}-task"
  retention_in_days = 7
  tags = { Environment = var.environment_name }
}

resource "aws_ecs_cluster" "main" {
  name = "boston-${var.environment_name}-cluster"
  tags = { Environment = var.environment_name }
}

resource "aws_security_group" "alb_sg" {
  name        = "boston-alb-sg-${var.environment_name}"
  description = "Permite trafico HTTP al ALB"
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

  tags = { Environment = var.environment_name }
}

resource "aws_security_group" "ecs_sg" {
  name        = "boston-ecs-sg-${var.environment_name}"
  description = "Permite trafico desde el ALB al contenedor"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Environment = var.environment_name }
}

resource "aws_lb" "main" {
  name               = "boston-${var.environment_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.subnet_ids
  tags = { Environment = var.environment_name }
}

resource "aws_lb_target_group" "ecs_tg" {
  name        = "boston-tg-${var.environment_name}"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "8000"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 15
    timeout             = 5
    matcher             = "200"
  }

  tags = { Environment = var.environment_name }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_tg.arn
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = "boston-${var.environment_name}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  task_role_arn            = var.lab_role_arn
  execution_role_arn       = var.lab_role_arn

  container_definitions = jsonencode([
    {
      name  = "boston-${var.environment_name}-container"
      image = var.docker_image_uri

      portMappings = [
        { containerPort = 8000, protocol = "tcp" }
      ]

      environment = [
        { name = "FLASK_SECRET_KEY", value = var.secret_key }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = { Environment = var.environment_name }
}

resource "aws_ecs_service" "main" {
  name            = "boston-${var.environment_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_tg.arn
    container_name   = "boston-${var.environment_name}-container"
    container_port   = 8000
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener.http]
  tags = { Environment = var.environment_name }
}
```

---

### ✅ Paso 11 — Completar el workflow de CD (agregar Jobs 2–7)

**Estado: COMPLETADO** — El archivo `.github/workflows/main.yaml` implementa los 7 jobs completos. Los jobs de CD (2–7) se agregaron al final del job `build-test-publish` y cubren despliegue en staging, tests de aceptación, despliegue en producción y tests de humo. El workflow también imprime las URLs del ALB y del dashboard de MLflow en el job summary de GitHub Actions.

El YAML de referencia de los jobs 2–7 es el siguiente:

```yaml
  # ─────────────────────────────────────────────────────────────
  # Job 2: Deploy Terraform Staging
  # ─────────────────────────────────────────────────────────────
  deploy-tf-staging:
    needs: build-test-publish
    runs-on: ubuntu-latest
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    outputs:
      alb_url_staging: ${{ steps.get_tf_outputs.outputs.alb_url }}
      cluster_name_staging: "boston-staging-cluster"
      service_name_staging: "boston-staging-service"

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-session-token: ${{ secrets.AWS_SESSION_TOKEN }}
          aws-region: us-east-1

      - name: Ensure Terraform State Bucket
        run: |
          if aws s3api head-bucket --bucket "${{ vars.TF_STATE_BUCKET }}" 2>/dev/null; then
            echo "Bucket de estado ya existe."
          else
            aws s3api create-bucket --bucket "${{ vars.TF_STATE_BUCKET }}" --region us-east-1
          fi
          aws s3api put-bucket-versioning \
            --bucket "${{ vars.TF_STATE_BUCKET }}" \
            --versioning-configuration Status=Enabled

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "~1.6"
          terraform_wrapper: false

      - name: Terraform Init (Staging)
        working-directory: infra
        run: |
          terraform init -reconfigure \
            -backend-config="bucket=${{ vars.TF_STATE_BUCKET }}" \
            -backend-config="key=staging/terraform.tfstate" \
            -backend-config="region=us-east-1"

      - name: Terraform Apply (Staging)
        working-directory: infra
        env:
          TF_VAR_environment_name: staging
          TF_VAR_lab_role_arn: ${{ vars.LAB_ROLE_ARN }}
          TF_VAR_vpc_id: ${{ vars.VPC_ID }}
          TF_VAR_secret_key: ${{ secrets.SECRET_KEY }}
        run: |
          IMAGE_URI="${{ vars.DOCKERHUB_USERNAME }}/${{ needs.build-test-publish.outputs.repo_name }}:${{ needs.build-test-publish.outputs.image_tag }}"
          SUBNET_LIST=$(echo "${{ vars.SUBNET_IDS }}" | \
            awk -F',' '{printf "["; for(i=1;i<=NF;i++){printf "\"%s\"%s",$i,(i<NF?",":"")}; printf "]"}')
          terraform apply -auto-approve \
            -var="docker_image_uri=${IMAGE_URI}" \
            -var="subnet_ids=${SUBNET_LIST}"

      - name: Get Terraform Outputs (Staging)
        id: get_tf_outputs
        working-directory: infra
        run: |
          ALB_URL=$(terraform output -raw alb_url)
          echo "alb_url=${ALB_URL}" >> $GITHUB_OUTPUT

  # ─────────────────────────────────────────────────────────────
  # Job 3: Forzar despliegue en ECS Staging
  # ─────────────────────────────────────────────────────────────
  update-service-staging:
    needs: [build-test-publish, deploy-tf-staging]
    runs-on: ubuntu-latest
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'

    steps:
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-session-token: ${{ secrets.AWS_SESSION_TOKEN }}
          aws-region: us-east-1

      - name: Force New Deployment ECS Staging
        run: |
          aws ecs update-service \
            --cluster ${{ needs.deploy-tf-staging.outputs.cluster_name_staging }} \
            --service ${{ needs.deploy-tf-staging.outputs.service_name_staging }} \
            --force-new-deployment \
            --region us-east-1
          aws ecs wait services-stable \
            --cluster ${{ needs.deploy-tf-staging.outputs.cluster_name_staging }} \
            --services ${{ needs.deploy-tf-staging.outputs.service_name_staging }} \
            --region us-east-1

  # ─────────────────────────────────────────────────────────────
  # Job 4: Pruebas de aceptación en Staging
  # ─────────────────────────────────────────────────────────────
  test-staging:
    needs: [update-service-staging, deploy-tf-staging]
    runs-on: ubuntu-latest
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install test dependencies
        run: pip install -r requirements.txt

      - name: Run Acceptance Tests against Staging
        env:
          APP_BASE_URL: ${{ needs.deploy-tf-staging.outputs.alb_url_staging }}
        run: |
          sleep 30
          pytest tests/test_acceptance_app.py

  # ─────────────────────────────────────────────────────────────
  # Job 5: Deploy Terraform Producción (solo si staging pasó)
  # ─────────────────────────────────────────────────────────────
  deploy-tf-prod:
    needs: [build-test-publish, test-staging]
    runs-on: ubuntu-latest
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    outputs:
      alb_url_prod: ${{ steps.get_tf_outputs.outputs.alb_url }}
      cluster_name_prod: "boston-production-cluster"
      service_name_prod: "boston-production-service"

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-session-token: ${{ secrets.AWS_SESSION_TOKEN }}
          aws-region: us-east-1

      - name: Ensure Terraform State Bucket
        run: |
          if aws s3api head-bucket --bucket "${{ vars.TF_STATE_BUCKET }}" 2>/dev/null; then
            echo "Bucket ya existe."
          else
            aws s3api create-bucket --bucket "${{ vars.TF_STATE_BUCKET }}" --region us-east-1
          fi
          aws s3api put-bucket-versioning \
            --bucket "${{ vars.TF_STATE_BUCKET }}" \
            --versioning-configuration Status=Enabled

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "~1.6"
          terraform_wrapper: false

      - name: Terraform Init (Production)
        working-directory: infra
        run: |
          terraform init -reconfigure \
            -backend-config="bucket=${{ vars.TF_STATE_BUCKET }}" \
            -backend-config="key=production/terraform.tfstate" \
            -backend-config="region=us-east-1"

      - name: Terraform Apply (Production)
        working-directory: infra
        env:
          TF_VAR_environment_name: production
          TF_VAR_lab_role_arn: ${{ vars.LAB_ROLE_ARN }}
          TF_VAR_vpc_id: ${{ vars.VPC_ID }}
          TF_VAR_secret_key: ${{ secrets.SECRET_KEY }}
        run: |
          IMAGE_URI="${{ vars.DOCKERHUB_USERNAME }}/${{ needs.build-test-publish.outputs.repo_name }}:${{ needs.build-test-publish.outputs.image_tag }}"
          SUBNET_LIST=$(echo "${{ vars.SUBNET_IDS }}" | \
            awk -F',' '{printf "["; for(i=1;i<=NF;i++){printf "\"%s\"%s",$i,(i<NF?",":"")}; printf "]"}')
          terraform apply -auto-approve \
            -var="docker_image_uri=${IMAGE_URI}" \
            -var="subnet_ids=${SUBNET_LIST}"

      - name: Get Terraform Outputs (Production)
        id: get_tf_outputs
        working-directory: infra
        run: |
          ALB_URL=$(terraform output -raw alb_url)
          echo "alb_url=${ALB_URL}" >> $GITHUB_OUTPUT

  # ─────────────────────────────────────────────────────────────
  # Job 6: Forzar despliegue en ECS Producción
  # ─────────────────────────────────────────────────────────────
  update-service-prod:
    needs: [build-test-publish, deploy-tf-prod]
    runs-on: ubuntu-latest
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'

    steps:
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-session-token: ${{ secrets.AWS_SESSION_TOKEN }}
          aws-region: us-east-1

      - name: Force New Deployment ECS Production
        run: |
          aws ecs update-service \
            --cluster ${{ needs.deploy-tf-prod.outputs.cluster_name_prod }} \
            --service ${{ needs.deploy-tf-prod.outputs.service_name_prod }} \
            --force-new-deployment \
            --region us-east-1
          aws ecs wait services-stable \
            --cluster ${{ needs.deploy-tf-prod.outputs.cluster_name_prod }} \
            --services ${{ needs.deploy-tf-prod.outputs.service_name_prod }} \
            --region us-east-1

  # ─────────────────────────────────────────────────────────────
  # Job 7: Pruebas de humo en Producción
  # ─────────────────────────────────────────────────────────────
  smoke-test-prod:
    needs: [update-service-prod, deploy-tf-prod]
    runs-on: ubuntu-latest
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install test dependencies
        run: pip install -r requirements.txt

      - name: Run Smoke Tests against Production
        env:
          APP_BASE_URL: ${{ needs.deploy-tf-prod.outputs.alb_url_prod }}
        run: |
          sleep 30
          pytest tests/test_smoke_app.py
```

---

### ✅ Paso 12 — Configurar Secrets y Variables en GitHub

**Estado: COMPLETADO** — Todos los secrets y variables necesarios para el pipeline completo (CI + CD) están configurados en el repositorio de Daniel.

**Configurados ✅:**
- Secrets: `SONAR_TOKEN`, `DOCKERHUB_TOKEN`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `SECRET_KEY`
- Variables: `DOCKERHUB_USERNAME`, `SONAR_HOST_URL`, `TF_STATE_BUCKET`, `LAB_ROLE_ARN`, `VPC_ID`, `SUBNET_IDS`

> **CRÍTICO:** Los secrets de AWS Academy **expiran cada 4 horas**. Deben actualizarse en GitHub cada vez que se haga Start Lab antes de correr el pipeline de CD.

Ir a GitHub → repositorio → **Settings → Secrets and variables → Actions**.

**Secrets (valores sensibles):**

| Secret | Cómo obtenerlo | Descripción |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | AWS Academy → Start Lab → AWS Details → CLI credentials | Credencial de acceso programático |
| `AWS_SECRET_ACCESS_KEY` | Mismo lugar | Clave secreta de acceso |
| `AWS_SESSION_TOKEN` | Mismo lugar (se renueva cada 4 horas con Start Lab) | Token de sesión temporal |
| `SONAR_TOKEN` | SonarCloud → My Account → Security → Generate Token | Token de análisis de SonarCloud |
| `DOCKERHUB_TOKEN` | Docker Hub → Account → Security → New Access Token | Token de acceso a Docker Hub |
| `SECRET_KEY` | `python -c "import secrets; print(secrets.token_hex(32))"` | Clave secreta de Flask |

**Variables de repositorio (vars, no secretas):**

| Variable | Ejemplo | Descripción |
|---|---|---|
| `DOCKERHUB_USERNAME` | `alejandropelaez` | Tu usuario de Docker Hub |
| `TF_STATE_BUCKET` | `boston-tf-state-12345` | Nombre único del bucket S3 para el estado de Terraform |
| `LAB_ROLE_ARN` | `arn:aws:iam::123456789012:role/LabRole` | ARN del rol LabRole (en AWS Academy → IAM → Roles) |
| `VPC_ID` | `vpc-0abc12345` | ID de la VPC por defecto (en AWS → VPC → Your VPCs) |
| `SUBNET_IDS` | `subnet-aaa111,subnet-bbb222` | IDs de al menos 2 subredes públicas separadas por coma |

> **CRÍTICO:** Los secrets de AWS Academy **expiran cada 4 horas**. Deben actualizarse en GitHub cada vez que se haga Start Lab antes de correr el pipeline.

---

### ✅ Paso 13 — Verificar el pipeline completo

**Estado: COMPLETADO** — El pipeline de 7 jobs corre exitosamente en GitHub Actions. Los tests de aceptación pasan contra staging y los tests de humo pasan contra producción antes de confirmar el despliegue.

**Checklist de verificación local antes del primer push:**

```bash
# 1. Activar el entorno virtual
source venv/Scripts/activate  # Windows Git Bash

# 2. Instalar dependencias
pip install -r requirements.txt

# 3. Verificar Black (debe pasar sin output)
black app --check

# 4. Verificar Pylint (objetivo: score >= 9.0)
pylint app

# 5. Verificar Flake8 (objetivo: sin errores)
flake8 app

# 6. Correr todos los tests unitarios
pytest --ignore=tests/test_acceptance_app.py --ignore=tests/test_smoke_app.py

# 7. Verificar que la app corre correctamente
python -m app.app
# Abrir http://localhost:8000 y probar el formulario
```

**Checklist de verificación en GitHub Actions:**

1. El Job 1 (CI) debe pasar completamente antes de hacer el primer deploy
2. Verificar que la imagen aparece en Docker Hub con el tag del SHA del commit
3. Verificar que SonarCloud recibe el análisis y el Quality Gate pasa
4. Verificar que el bucket de S3 para el estado de Terraform se creó
5. Verificar que los recursos de Staging aparecen en la consola de AWS (ECS → Clusters)
6. Abrir la URL del ALB de staging y confirmar que la app responde
7. Verificar que los acceptance tests pasan en staging antes del deploy a producción
8. Verificar que los smoke tests pasan en producción

---

## ✅ Paso 14 — Integración de MLflow para monitoreo de predicciones

**Estado: COMPLETADO** — Se integró MLflow 3.11.1 como dashboard de monitoreo de predicciones en tiempo real. Cada llamada a `predict_from_list()` registra un run en MLflow con los 13 parámetros de entrada, la métrica `predicted_price`, y los tags `environment` y `source`.

**Cambios realizados:**
- `requirements.txt` — agregado `mlflow==3.11.1` (compatible con gunicorn==23.0.0; MLflow 2.x no lo era)
- `app/predictor.py` — agregada integración MLflow: `_MLFLOW_URI`, `_ENVIRONMENT`, `_log_prediction()`; la función `predict_from_list()` acepta parámetro `source`
- `app/app.py` — la ruta `/predict` pasa `source="web_form"` a `predict_from_list()`
- `infra/main.tf` — agregado servidor MLflow completo: S3 bucket para artefactos, ALB propio, ECS Fargate con imagen `ghcr.io/mlflow/mlflow:v3.11.1`, SQLite backend
- `infra/outputs.tf` — agregada salida `mlflow_url`
- `.github/workflows/main.yaml` — jobs 2 y 5 ahora capturan y publican la URL del dashboard MLflow
- `tests/test_predictor.py` — agregados 2 tests con mocks: uno verifica que se llama a MLflow cuando hay URI configurada, otro verifica que un fallo de MLflow no rompe la predicción

**Persistencia de los runs en AWS:** los metadatos (parámetros, métricas) se almacenan en SQLite dentro del contenedor ECS y se pierden al reiniciar o redesplegar el servicio. Los artefactos se guardan en S3 y sí persisten. Para persistencia completa se requeriría RDS, fuera del alcance de este proyecto.

---

## Resumen de archivos — Estado final

| Archivo | Acción | Estado |
|---|---|---|
| `app/__init__.py` | CREAR | ✅ Completado |
| `app/app.py` | CREAR (movido desde raíz) + agregar `source="web_form"` | ✅ Completado |
| `app/predictor.py` | CREAR + integración MLflow | ✅ Completado |
| `tests/test_app.py` | CREAR | ✅ Completado |
| `tests/test_predictor.py` | CREAR + 2 tests MLflow mock | ✅ Completado |
| `tests/test_smoke_app.py` | CREAR | ✅ Completado |
| `tests/test_acceptance_app.py` | CREAR | ✅ Completado |
| `pytest.ini` | CREAR | ✅ Completado |
| `.flake8` | CREAR | ✅ Completado |
| `.dockerignore` | CREAR | ✅ Completado |
| `requirements.txt` | MODIFICAR (agregar mlflow==3.11.1) | ✅ Completado |
| `Dockerfile` | MODIFICAR | ✅ Completado |
| `.gitignore` | MODIFICAR | ✅ Completado |
| `front/home.html` | CORREGIR (`name="Age"` → `name="AGE"`) | ✅ Completado |
| `app.py` (raíz) | ELIMINAR | ✅ Completado |
| `Procfile` | ELIMINAR | ✅ Completado |
| `sonar-project.properties` | CREAR | ✅ Completado |
| `infra/main.tf` | CREAR (app + MLflow server) | ✅ Completado |
| `infra/variables.tf` | CREAR | ✅ Completado |
| `infra/outputs.tf` | CREAR (incluye mlflow_url) | ✅ Completado |
| `.github/workflows/main.yaml` | REEMPLAZAR (7 jobs completos + MLflow URLs) | ✅ Completado |


# Archivos de referencia

https://github.com/danielr9911/cicd-workshops/blob/main/Taller-Entregable-2.md

https://github.com/danielr9911/cicd-workshops/blob/main/Taller-Entregable3.md



---

*Documento actualizado el 2026-04-24 | Universidad EAFIT — Materia CI/CD*
