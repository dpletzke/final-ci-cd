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

## Estado actual del proyecto (actualizado 2026-04-23)

### ✅ Completado — Fase A (CI — Job 1)

- App Flask como paquete `app/` con `predictor.py` separado
- 13 tests unitarios + tests Selenium de aceptación y humo
- Calidad: Black ✅ | Pylint 10.00/10 ✅ | Flake8 ✅ | Cobertura 95% ✅
- Dockerfile (python:3.12-slim, Gunicorn, puerto 8000)
- `pytest.ini`, `.flake8`, `.dockerignore`, `.gitignore`
- `sonar-project.properties` creado y funcionando (`projectKey=AlexanderPelaezJimenez_final-ci-cd`)
- `.github/workflows/main.yaml` — Job 1 CI completo y pasando en GitHub Actions
- Docker Hub publicando imagen con tags `:latest` y `:<git-sha>` en cada push a `main`
- SonarCloud Quality Gate pasando — se resolvió Blocker S8392 y Hotspot CSRF

### Secrets y variables ya configurados en GitHub ✅
| Tipo | Nombre | Estado |
|------|--------|--------|
| Secret | `SONAR_TOKEN` | ✅ Configurado |
| Secret | `DOCKERHUB_TOKEN` | ✅ Configurado |
| Variable | `DOCKERHUB_USERNAME` | ✅ Configurado |
| Variable | `SONAR_HOST_URL` | ✅ Configurado |

### ❌ Pendiente — Fase B (CD — Jobs 2–7)

| Paso | Tarea | Archivo |
|------|-------|---------|
| 10 | Crear infraestructura Terraform (ECS Fargate + ALB) | `infra/main.tf`, `infra/variables.tf`, `infra/outputs.tf` |
| 11 | Agregar Jobs 2–7 al workflow (staging + prod) | `.github/workflows/main.yaml` |
| 12 | Configurar Secrets/Variables AWS en GitHub (manual) | Ver tabla abajo |
| 13 | Verificar pipeline completo end-to-end | Manual |

### Secrets y variables pendientes para Fase CD ❌
| Tipo | Nombre | Descripción |
|------|--------|-------------|
| Secret | `AWS_ACCESS_KEY_ID` | AWS Academy → Start Lab → AWS Details (expira cada 4h) |
| Secret | `AWS_SECRET_ACCESS_KEY` | Mismo lugar |
| Secret | `AWS_SESSION_TOKEN` | Mismo lugar (renovar con Start Lab antes de cada run) |
| Secret | `SECRET_KEY` | `python -c "import secrets; print(secrets.token_hex(32))"` |
| Variable | `TF_STATE_BUCKET` | Nombre único del bucket S3 para estado Terraform |
| Variable | `LAB_ROLE_ARN` | ARN del LabRole en AWS Academy → IAM → Roles |
| Variable | `VPC_ID` | ID de la VPC por defecto en AWS → VPC → Your VPCs |
| Variable | `SUBNET_IDS` | IDs de 2 subredes públicas separadas por coma |

> El código completo de los archivos Terraform y Jobs 2–7 está listo en `Docs/pasos_a_seguir_v1.md` (Pasos 10 y 11).

---

## Próximo paso para continuar

**Empezar por el Paso 10:** crear los tres archivos en `infra/`:
- `infra/variables.tf`
- `infra/outputs.tf`
- `infra/main.tf`

El contenido completo ya está documentado en `Docs/pasos_a_seguir_v1.md` sección "Paso 10".
Después del Paso 10 viene el Paso 11 (Jobs 2–7 en el workflow) y luego configurar los secrets AWS.

---

## Arquitectura del pipeline final (7 jobs)

```
push a main
     │
Job 1: build-test-publish   ← COMPLETADO Y PASANDO
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

## Problemas ya resueltos (no repetir)

- **Test aceptación `result_text` vacío** → se cambió `presence_of_element_located` por `visibility_of_element_located` en `tests/test_acceptance_app.py` (la animación CSS `fadeIn` causaba race condition)
- **SonarCloud Blocker S8392** → `host="0.0.0.0"` cambiado a `host="127.0.0.1"` en bloque `__main__` de `app/app.py` (no afecta Gunicorn en CI/prod)
- **SonarCloud Hotspot CSRF** → marcado como "Safe" en el dashboard de SonarCloud (app sin autenticación ni operaciones sensibles)
- **GitHub push protection** bloqueó un push por token Docker Hub en `Docs/llaves_secrets_etc.md` → archivo excluido con `git rm --cached` y añadido a `.gitignore`

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
