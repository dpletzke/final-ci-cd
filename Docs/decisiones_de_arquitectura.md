# Decisiones de Arquitectura — Boston House Pricing

Documento vivo que registra las decisiones arquitectónicas del proyecto usando el formato
**ADR (Architecture Decision Record)**. Cada decisión incluye el contexto que la motivó,
la alternativa elegida y las consecuencias esperadas.

> **Convención de estado:**
> `Aceptada` — vigente | `Reemplazada` — superada por otra ADR | `Deprecada` — ya no aplica

---

## Índice

| ID | Título | Estado | Fecha |
|----|--------|--------|-------|
| [ADR-001](#adr-001) | Estructura de la aplicación como paquete Python | Aceptada | 2026-04-21 |
| [ADR-002](#adr-002) | Separación de lógica ML en módulo independiente | Aceptada | 2026-04-21 |
| [ADR-003](#adr-003) | Servidor WSGI: Gunicorn sobre Flask dev server | Aceptada | 2026-04-21 |
| [ADR-004](#adr-004) | Contenedorización con Docker (python:3.12-slim) | Aceptada | 2026-04-21 |
| [ADR-005](#adr-005) | Registro de imágenes: Docker Hub | Aceptada | 2026-04-21 |
| [ADR-006](#adr-006) | Infraestructura en AWS ECS Fargate + ALB | Aceptada | 2026-04-21 |
| [ADR-007](#adr-007) | Infraestructura como Código con Terraform | Aceptada | 2026-04-21 |
| [ADR-008](#adr-008) | Estado de Terraform en S3 | Aceptada | 2026-04-21 |
| [ADR-009](#adr-009) | Pipeline CI/CD con GitHub Actions | Aceptada | 2026-04-21 |
| [ADR-010](#adr-010) | Estrategia de calidad de código: Black + Pylint + Flake8 + SonarCloud | Aceptada | 2026-04-21 |
| [ADR-011](#adr-011) | Estrategia de testing: unitarios + aceptación + humo | Aceptada | 2026-04-21 |
| [ADR-012](#adr-012) | Estrategia de ramificación: Trunk-Based Development | Aceptada | 2026-04-22 |

---

## Visión general de la arquitectura

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DESARROLLADOR                                │
│                                                                     │
│   feature branch  →  PR  →  merge a main                           │
└─────────────────────────┬───────────────────────────────────────────┘
                          │ push a main
                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    GITHUB ACTIONS (CI/CD)                           │
│                                                                     │
│  Job 1: build-test-publish                                          │
│    Black → Pylint → Flake8 → pytest → SonarCloud → Docker Hub      │
│                          │                                          │
│  Job 2-3: deploy-tf-staging + update-service-staging               │
│    Terraform apply (staging) → aws ecs update-service              │
│                          │                                          │
│  Job 4: test-staging                                                │
│    Selenium acceptance tests contra ALB staging                     │
│                          │  (solo si Job 4 pasa)                   │
│  Job 5-6: deploy-tf-prod + update-service-prod                     │
│    Terraform apply (prod) → aws ecs update-service                 │
│                          │                                          │
│  Job 7: smoke-test-prod                                             │
│    Selenium smoke tests contra ALB producción                       │
└─────────────────────────┬───────────────────────────────────────────┘
                          │
          ┌───────────────┴───────────────┐
          ▼                               ▼
┌─────────────────┐             ┌─────────────────┐
│  AWS ECS Fargate│             │  AWS ECS Fargate│
│  STAGING        │             │  PRODUCTION     │
│                 │             │                 │
│  ALB → Task     │             │  ALB → Task     │
│  (boston:sha)   │             │  (boston:sha)   │
│  puerto 8000    │             │  puerto 8000    │
└─────────────────┘             └─────────────────┘
          │                               │
          └───────────────┬───────────────┘
                          ▼
                ┌──────────────────┐
                │  Docker Hub      │
                │  usuario/repo:sha│
                │  usuario/repo:   │
                │  latest          │
                └──────────────────┘
```

---

## ADR-001

### Estructura de la aplicación como paquete Python

**Estado:** Aceptada | **Fecha:** 2026-04-21

#### Contexto

El proyecto original tenía un único `app.py` en la raíz del repositorio. Esta estructura
plana no permite importaciones relativas, dificulta las pruebas unitarias aisladas y es
incompatible con el comando `gunicorn app.app:app` que referencia el módulo por ruta.

#### Decisión

Organizar la aplicación como un paquete Python dentro del directorio `app/`, con un
archivo `__init__.py` que lo marca como paquete importable.

```
app/
├── __init__.py     ← marca el directorio como paquete
├── app.py          ← rutas Flask
└── predictor.py    ← lógica de predicción ML
```

#### Consecuencias

- `pytest` puede importar los módulos sin manipular `sys.path`
- Gunicorn referencia el entry point como `app.app:app`
- `pytest.ini` define `pythonpath = .` para que el paquete sea encontrado desde la raíz
- Se elimina el `app.py` de la raíz para evitar conflictos de nombres

---

## ADR-002

### Separación de lógica ML en módulo independiente

**Estado:** Aceptada | **Fecha:** 2026-04-21

#### Contexto

Mezclar la carga del modelo, el escalado y la predicción dentro de las rutas Flask
acopla la lógica de negocio al framework web, haciendo imposible probar la predicción
sin levantar un cliente HTTP.

#### Decisión

Extraer toda la lógica de Machine Learning a `app/predictor.py`, que expone una función
pura `predict(features: list) -> float`. Las rutas Flask en `app/app.py` solo
orquestan: reciben input, llaman a `predict()` y formatean la respuesta.

#### Consecuencias

- `tests/test_predictor.py` puede probar la lógica ML directamente sin cliente HTTP
- `tests/test_app.py` puede probar las rutas con mocks del predictor si fuera necesario
- La sustitución futura del modelo (cambio de algoritmo o framework) no toca las rutas
- Los modelos se cargan una sola vez al importar el módulo (no en cada request)

---

## ADR-003

### Servidor WSGI: Gunicorn sobre Flask dev server

**Estado:** Aceptada | **Fecha:** 2026-04-21

#### Contexto

El servidor de desarrollo integrado de Flask (`flask run`) no está diseñado para producción:
es single-threaded, no maneja señales del SO correctamente y tiene advertencias explícitas
de los propios autores de Flask sobre su uso en producción.

#### Decisión

Usar **Gunicorn** como servidor WSGI de producción con 4 workers, vinculado al puerto 8000.

```
gunicorn --workers=4 --bind=0.0.0.0:8000 app.app:app
```

#### Consecuencias

- 4 workers permiten manejar hasta 4 requests concurrentes sin bloqueo
- El puerto 8000 es consistente entre desarrollo local, Docker y ECS
- El health check del ALB apunta siempre a `host:8000/health`
- El `CMD` del Dockerfile usa formato JSON para evitar que el shell absorba señales SIGTERM

---

## ADR-004

### Contenedorización con Docker (python:3.12-slim)

**Estado:** Aceptada | **Fecha:** 2026-04-21

#### Contexto

La aplicación necesita ejecutarse de forma reproducible en cualquier entorno (local,
CI y ECS Fargate). Las diferencias de versiones de Python y dependencias del SO son
una fuente frecuente de bugs difíciles de reproducir.

#### Decisión

Construir una imagen Docker basada en `python:3.12-slim` con las siguientes optimizaciones:

```dockerfile
COPY requirements.txt .          # primero, para aprovechar caché de capas
RUN pip install --no-cache-dir   # reduce tamaño de imagen
EXPOSE 8000
CMD ["gunicorn", ...]            # formato JSON: no usa shell
```

#### Alternativas consideradas

| Alternativa | Motivo de descarte |
|---|---|
| `python:3.12` (full) | ~400 MB extra sin beneficio funcional |
| `python:3.12-alpine` | Problemas de compatibilidad con NumPy/scikit-learn (musl libc) |
| `distroless` | Mayor complejidad de construcción; sin ganancia significativa en este contexto |

#### Consecuencias

- Imagen final ~200 MB (slim vs ~600 MB en imagen full)
- El `.dockerignore` excluye `tests/`, `notebooks/`, `Docs/`, `infra/` y archivos de coverage
- La imagen es portable: misma imagen se despliega en staging y producción, solo cambia la variable de entorno

---

## ADR-005

### Registro de imágenes: Docker Hub

**Estado:** Aceptada | **Fecha:** 2026-04-21

#### Contexto

La imagen Docker construida en CI debe almacenarse en un registro accesible tanto desde
GitHub Actions (para publicar) como desde AWS ECS (para desplegar).

#### Decisión

Usar **Docker Hub** como registro de imágenes, publicando con doble tag:

```
usuario/boston_house_pricing:latest          ← siempre apunta al último build de main
usuario/boston_house_pricing:<git-sha>       ← inmutable, referenciado por Terraform
```

#### Alternativas consideradas

| Alternativa | Motivo de descarte |
|---|---|
| Amazon ECR | Requiere autenticar ECS con IAM específico; más complejo con AWS Academy (credenciales efímeras) |
| GitHub Container Registry | Menos familiar; integración con ECS menos documentada |

#### Consecuencias

- El tag `<git-sha>` garantiza trazabilidad: cada deploy apunta a un commit exacto
- Terraform recibe el URI completo como variable `docker_image_uri`
- El secret `DOCKERHUB_TOKEN` debe estar configurado en GitHub Actions

---

## ADR-006

### Infraestructura en AWS ECS Fargate + ALB

**Estado:** Aceptada | **Fecha:** 2026-04-21

#### Contexto

La aplicación necesita ejecutarse en la nube con alta disponibilidad, sin gestión de
servidores y con un punto de entrada HTTP público. El entorno disponible es AWS Academy.

#### Decisión

Usar **AWS ECS Fargate** como plataforma de ejecución de contenedores y un
**Application Load Balancer (ALB)** como punto de entrada HTTP.

```
Internet → ALB (puerto 80) → Target Group → ECS Task (puerto 8000)
```

Configuración del Task:
- CPU: 256 (0.25 vCPU)
- Memoria: 512 MB
- Red: `awsvpc` con IP pública asignada
- Logs: CloudWatch Logs (retención 7 días)

#### Alternativas consideradas

| Alternativa | Motivo de descarte |
|---|---|
| EC2 | Requiere gestión del SO, parches, SSH; más fricción operativa |
| Lambda | Cold starts incompatibles con Flask + Gunicorn; límite de 15 min por request |
| App Runner | Menos control sobre networking; no disponible en todas las regiones de Academy |
| Elastic Beanstalk | Abstracción opaca; dificulta el aprendizaje de los componentes individuales |

#### Consecuencias

- El health check del ALB apunta a `GET /health` (HTTP 200)
- El ECS Service tiene `desired_count = 1` (suficiente para el proyecto académico)
- `lifecycle { ignore_changes = [desired_count] }` evita que Terraform revierta escalados manuales
- Los Security Groups limitan: ALB solo acepta puerto 80; ECS Task solo acepta desde el ALB en puerto 8000

---

## ADR-007

### Infraestructura como Código con Terraform

**Estado:** Aceptada | **Fecha:** 2026-04-21

#### Contexto

La infraestructura debe ser reproducible, versionable y desplegable de forma automatizada
desde el pipeline de CI/CD para dos entornos (staging y producción) con configuraciones
simétricas pero aisladas.

#### Decisión

Usar **Terraform** con un único conjunto de archivos en `infra/` parametrizado por la
variable `environment_name` (`staging` | `production`). El estado se almacena en S3
con claves diferentes por entorno (`staging/terraform.tfstate`, `production/terraform.tfstate`).

#### Alternativas consideradas

| Alternativa | Motivo de descarte |
|---|---|
| AWS CloudFormation | Sintaxis verbose; menos portable fuera de AWS |
| AWS CDK | Requiere Node.js; curva de aprendizaje adicional |
| Pulumi | Menos adopción en el mercado; sin ventaja clara para este caso |

#### Consecuencias

- Un solo `terraform apply` crea o actualiza todos los recursos del entorno
- El parámetro `-var="environment_name=staging"` diferencia los dos entornos
- Los nombres de recursos incluyen el entorno: `boston-staging-cluster`, `boston-production-alb`, etc.
- `terraform_wrapper: false` en el action de GitHub evita que los outputs incluyan metadata extra

---

## ADR-008

### Estado de Terraform en S3

**Estado:** Aceptada | **Fecha:** 2026-04-21

#### Contexto

Terraform necesita un backend remoto para almacenar su estado. Sin backend remoto, el
estado se guarda en `terraform.tfstate` local, que no persiste entre ejecuciones del
runner de GitHub Actions (el runner es efímero).

#### Decisión

Usar un **bucket S3** como backend remoto con versionamiento habilitado. El pipeline
verifica si el bucket existe antes de inicializar Terraform y lo crea si no existe.

```
Bucket: <TF_STATE_BUCKET>  (variable de repositorio en GitHub)
Keys:
  staging/terraform.tfstate
  production/terraform.tfstate
```

#### Consecuencias

- El estado persiste entre ejecuciones del pipeline
- El versionamiento de S3 permite recuperar estados anteriores si un apply falla
- No se usa DynamoDB para locking (no disponible fácilmente en AWS Academy); aceptable dado que solo un pipeline escribe el estado
- El nombre del bucket debe ser único globalmente en S3

---

## ADR-009

### Pipeline CI/CD con GitHub Actions

**Estado:** Aceptada | **Fecha:** 2026-04-21

#### Contexto

El proyecto necesita automatizar: validación de código, tests, análisis estático,
construcción de imagen Docker y despliegue a dos entornos en AWS.

#### Decisión

Usar **GitHub Actions** con un workflow de 7 jobs encadenados en `.github/workflows/main.yaml`.

```
build-test-publish
      │
deploy-tf-staging → update-service-staging → test-staging
                                                    │
                                            deploy-tf-prod → update-service-prod → smoke-test-prod
```

El trigger de despliegue (Jobs 2–7) solo se activa en `push` a `main`, no en Pull Requests.

#### Alternativas consideradas

| Alternativa | Motivo de descarte |
|---|---|
| Jenkins | Requiere servidor propio; overhead operativo injustificado para este proyecto |
| CircleCI | De pago para equipos; sin ventaja sobre GitHub Actions integrado |
| GitLab CI | Requiere migrar el repositorio fuera de GitHub |

#### Consecuencias

- Los secrets de AWS Academy expiran cada 4 horas; deben actualizarse antes de cada run de CD
- `workflow_dispatch` permite disparar el pipeline manualmente desde la UI de GitHub
- Los artefactos de test (report.html, htmlcov/) se publican como artifacts del workflow con `if: always()`

---

## ADR-010

### Estrategia de calidad de código: Black + Pylint + Flake8 + SonarCloud

**Estado:** Aceptada | **Fecha:** 2026-04-21

#### Contexto

El código debe cumplir estándares de estilo, ausencia de errores lógicos y cobertura
de tests verificable de forma automatizada en cada push.

#### Decisión

Aplicar cuatro capas de calidad en el Job 1 del pipeline:

| Herramienta | Rol | Falla el pipeline si... |
|---|---|---|
| **Black** | Formateador | El código no está formateado según Black |
| **Pylint** | Linter semántico | Score < 9.0 / 10 |
| **Flake8** | Linter de estilo PEP 8 | Hay violaciones de estilo |
| **SonarCloud** | Análisis estático continuo | Quality Gate falla |

#### Consecuencias

- `max-line-length = 88` en `.flake8` para consistencia con el límite de Black
- Pylint y Flake8 generan reportes de texto que SonarCloud consume para enriquecer su análisis
- El objetivo de Pylint es 10.00/10 (actualmente alcanzado)
- SonarCloud requiere `sonar-project.properties` en la raíz y el secret `SONAR_TOKEN` en GitHub

---

## ADR-011

### Estrategia de testing: unitarios + aceptación + humo

**Estado:** Aceptada | **Fecha:** 2026-04-21

#### Contexto

La aplicación tiene dos capas verificables independientemente: la lógica ML (predictor)
y las rutas HTTP (Flask). Además, los entornos de staging y producción necesitan
validación funcional post-despliegue.

#### Decisión

Tres niveles de tests con responsabilidades distintas:

```
tests/
├── test_app.py            ← 5 tests   — rutas Flask (pytest + cliente de test Flask)
├── test_predictor.py      ← 8 tests   — lógica ML pura (sin HTTP)
├── test_acceptance_app.py ←           — flujo completo en staging (Selenium)
└── test_smoke_app.py      ←           — verificación mínima en prod (Selenium)
```

| Nivel | Cuándo corre | Contra qué |
|---|---|---|
| Unitarios | Job 1 (siempre) | App local en memoria |
| Aceptación | Job 4 | ALB de staging (URL real) |
| Humo | Job 7 | ALB de producción (URL real) |

Los tests de Selenium leen `APP_BASE_URL` del entorno — el pipeline inyecta la URL del
ALB como output de Terraform.

#### Consecuencias

- Cobertura actual: **95%** sobre el paquete `app/`
- Los tests de Selenium no se ejecutan localmente (requieren Chrome + URL pública)
- `pytest.ini` ignora `test_acceptance_app.py` y `test_smoke_app.py` en la ejecución local
- Un `sleep 30` antes de los tests de Selenium absorbe el tiempo de warm-up del contenedor en ECS

---

## ADR-012

### Estrategia de ramificación: Trunk-Based Development

**Estado:** Aceptada | **Fecha:** 2026-04-22

#### Contexto

El equipo necesita elegir entre Gitflow y Trunk-Based Development como estrategia de
ramificación. El pipeline de CI/CD ya está diseñado para dispararse en cada push a `main`.

#### Decisión

Adoptar **Trunk-Based Development**: `main` es la única rama de larga duración.
Todo el trabajo nuevo se hace en feature branches de corta duración (horas, no días)
que se integran a `main` mediante Pull Request.

```
                    feature/sonar-config  feature/infra-terraform
                         ●──●                   ●──●──●
                        /    \                 /       \
main   ●───────────────●──────●───────────────●─────────●──────▶
       │               │      │               │         │
     push            PR+    push            PR+       push
                     merge                  merge
                       │                     │
                    CI/CD                 CI/CD
                  (7 jobs)              (7 jobs)
```

#### Por qué no Gitflow

| Criterio | Gitflow | Trunk-Based |
|---|---|---|
| Compatibilidad con el pipeline actual | Requiere rediseño del trigger | Nativo — pipeline dispara en push a main |
| Entornos de validación | Rama `release` como proxy de staging | Job de staging en el pipeline — más confiable |
| Tamaño del equipo | Equipos grandes con releases paralelos | Equipos pequeños con entrega continua |
| Frecuencia de integración | Baja (acumula cambios en develop) | Alta (cada PR integra a main) |
| Riesgo de merge conflicts | Alto | Bajo |

#### Consecuencias

- Las feature branches deben ser cortas: idealmente un día o menos antes de abrir PR
- Cada merge a `main` dispara el pipeline completo de 7 jobs (CI + CD a staging + CD a prod)
- Los secrets de AWS deben estar actualizados antes de cada push que deba hacer CD
- No existe rama `develop` ni `release`; el pipeline *es* la puerta de calidad

---

*Documento actualizado el 2026-04-22 | Universidad EAFIT — Materia CI/CD*
