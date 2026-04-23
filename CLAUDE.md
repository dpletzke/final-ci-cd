# CLAUDE.md — Boston House Pricing

Contexto del proyecto para Claude Code. Este archivo se carga automáticamente al inicio
de cada conversación, en cualquier máquina.

---

## Qué es este proyecto

Trabajo final de la materia **CI/CD** en la **Universidad EAFIT** (2026).
Aplicación Flask de predicción de precios de vivienda (Boston Housing dataset) con
pipeline CI/CD completo: GitHub Actions → Docker Hub → AWS ECS Fargate via Terraform.

**Repositorio:** `github.com/AlexanderPelaezJimenez/final-ci-cd`
**Rama principal:** `main` (Trunk-Based Development)

---

## Estado actual del proyecto

### Completado (Fase A — CI)
- App Flask como paquete `app/` con `predictor.py` separado
- 13 tests unitarios + tests Selenium de aceptación y humo
- Calidad: Black ✅ | Pylint 10.00/10 ✅ | Flake8 ✅ | Cobertura 95% ✅
- Dockerfile (python:3.12-slim, Gunicorn, puerto 8000)
- `pytest.ini`, `.flake8`, `.dockerignore`, `.gitignore`

### Pendiente (Fase B — CD)

| Paso | Tarea | Archivo |
|------|-------|---------|
| 7 | Crear configuración de SonarCloud | `sonar-project.properties` |
| 9 | Reemplazar workflow legacy de Heroku con pipeline de 7 jobs | `.github/workflows/main.yaml` |
| 10 | Crear infraestructura Terraform (ECS Fargate + ALB) | `infra/main.tf`, `infra/variables.tf`, `infra/outputs.tf` |
| 11 | Agregar Jobs 2–7 al workflow (staging + prod) | `.github/workflows/main.yaml` |
| 12 | Configurar Secrets y Variables en GitHub | Manual |
| 13 | Verificar pipeline completo | Manual |

> El código completo de todos los archivos pendientes está en `Docs/pasos_a_seguir_v1.md`.
> Las decisiones de arquitectura están documentadas en `Docs/decisiones_de_arquitectura.md`.

---

## Arquitectura del pipeline final (7 jobs)

```
push a main
     │
Job 1: build-test-publish
  Black → Pylint → Flake8 → pytest → SonarCloud → Docker Hub
     │
Job 2: deploy-tf-staging      (Terraform apply staging)
Job 3: update-service-staging (aws ecs update-service + wait)
Job 4: test-staging           (Selenium acceptance tests vs ALB staging)
     │ (solo si Job 4 pasa)
Job 5: deploy-tf-prod         (Terraform apply production)
Job 6: update-service-prod    (aws ecs update-service + wait)
Job 7: smoke-test-prod        (Selenium smoke tests vs ALB producción)
```

---

## Decisiones clave de arquitectura

| Decisión | Elección | Alternativa descartada |
|----------|----------|----------------------|
| Branching | Trunk-Based Development | Gitflow |
| Runtime | AWS ECS Fargate | EC2, Lambda |
| IaC | Terraform | CloudFormation, CDK |
| Registro Docker | Docker Hub | Amazon ECR |
| CI/CD | GitHub Actions | Jenkins, CircleCI |
| Servidor WSGI | Gunicorn (4 workers) | Flask dev server |
| Calidad de código | Black + Pylint + Flake8 + SonarCloud | Solo flake8 |

> Ver razonamiento completo en `Docs/decisiones_de_arquitectura.md`.

---

## Secrets requeridos en GitHub Actions

| Secret | Descripción |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | AWS Academy (expira cada 4h — renovar con Start Lab) |
| `AWS_SECRET_ACCESS_KEY` | AWS Academy |
| `AWS_SESSION_TOKEN` | AWS Academy |
| `SONAR_TOKEN` | SonarCloud → My Account → Security |
| `DOCKERHUB_TOKEN` | Docker Hub → Account → Security |
| `SECRET_KEY` | `python -c "import secrets; print(secrets.token_hex(32))"` |

| Variable | Ejemplo |
|----------|---------|
| `DOCKERHUB_USERNAME` | usuario de Docker Hub |
| `TF_STATE_BUCKET` | nombre único del bucket S3 |
| `LAB_ROLE_ARN` | ARN del LabRole en AWS Academy |
| `VPC_ID` | ID de la VPC por defecto |
| `SUBNET_IDS` | IDs de 2 subredes públicas separadas por coma |

---

## Comandos útiles

```bash
# Correr la app localmente
python -m app.app

# Tests unitarios (sin Selenium)
pytest --ignore=tests/test_acceptance_app.py --ignore=tests/test_smoke_app.py

# Calidad de código
black app --check
pylint app
flake8 app
```

---

## Convenciones del proyecto

- Los archivos `.tf` de Terraform van en `infra/` (los estados se ignoran en `.gitignore`)
- Los tests de Selenium solo corren en CI (requieren `APP_BASE_URL` y Chrome en el runner)
- Cada push a `main` dispara el pipeline completo — los secrets de AWS deben estar vigentes
- `Docs/` contiene documentación de desarrollo (no se ignora en git)
