# 🚀 Guía de Despliegue Universal y Automatizado: `deploy-mvp.sh`

Esta guía detalla el funcionamiento, los pasos para desplegar en cualquier proyecto nuevo de **Google Cloud Platform (GCP)** y los mecanismos de auto-recuperación integrados en el script [`deploy-mvp.sh`](file:///Users/anitaquevedo/Documents/Cursos/Utec/end-to-end/end-to-end-example1/deploy-mvp.sh).

---

## 📌 1. ¿Qué es `deploy-mvp.sh`?

Es una versión modular, optimizada y blindada del despliegue del **Data Analytics Golden Demo** de Google Cloud. 

* **Despliegue Rápido y Económico (~10-15 minutos):** Provee la arquitectura central de datos:
  * **BigQuery & BigLake:** 12 Datasets analíticos, vistas lógicas, procedimientos almacenados y tablas Iceberg.
  * **Dataplex:** Lakehouse, zonas de almacenamiento (Raw, Curated) y gobernanza de datos.
  * **Dataform:** Pipelines ELT automatizados en SQLX y repositorios de código.
  * **Cloud Storage:** Buckets organizados para capas Raw, Processed y Code.
  * **Serverless & APIs:** Cloud Run (`demo-rideshare-plus-website`) y Cloud Functions Gen 2 (`demo-rest-api-service`).
  * **Redes y Seguridad:** VPC dedicada (`vpc-main`), subredes, firewall y Service Accounts con mínimo privilegio.
* **Componentes Opcionales:** Por defecto omite **Cloud Composer** (tarda 30-35 min y consume mayor costo) y **Colab VM**, los cuales puedes habilitar fácilmente con flags si los necesitas.

---

## 📋 2. Requisitos Previos

Antes de ejecutar el script en tu máquina (macOS / Linux), asegúrate de contar con:
1. **Herramientas de línea de comandos instaladas:**
   * `gcloud` (Google Cloud SDK)
   * `terraform` (v1.5+)
   * `jq`, `curl`, `python3`
2. **Sesión inicial autenticada en Google Cloud:**
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```
   > [!NOTE]
   > El comando `application-default login` (ADC) es vital: genera credenciales de larga duración que Terraform renueva automáticamente, evitando caídas por tokens que expiran a los 60 minutos.

---

## 🛠️ 3. Paso a Paso para Desplegar en un Proyecto Nuevo

### Paso 1: Crear el proyecto en Google Cloud
Puedes crearlo desde la consola web o directamente por terminal:
```bash
gcloud projects create "mi-nuevo-proyecto-123" --name="Demo Analitica"
```

### Paso 2: Ejecutar el despliegue
Desde la carpeta raíz del repositorio (`end-to-end-example1/`):

```bash
./deploy-mvp.sh "mi-nuevo-proyecto-123"
```

Si deseas especificar la cuenta de correo explícitamente:
```bash
./deploy-mvp.sh "tu-correo@gmail.com" "mi-nuevo-proyecto-123"
```

### Paso 3: (Opcional) Desplegar con Cloud Composer y/o Colab
Si para tu caso de uso necesitas la orquestación con Apache Airflow (Cloud Composer) o el entorno de notebooks persistente:
* **Solo Cloud Composer:** `./deploy-mvp.sh "mi-nuevo-proyecto-123" --with-composer`
* **Solo Colab Runtime:** `./deploy-mvp.sh "mi-nuevo-proyecto-123" --with-colab`
* **Todo Completo:** `./deploy-mvp.sh "mi-nuevo-proyecto-123" --all`

---

## 🛡️ 4. Automatizaciones Integradas (¿Por qué no falla?)

El script ejecuta automáticamente verificaciones para resolver los problemas típicos de GCP antes de que Terraform falle:

| Problema Típico de GCP | Solución Automática en `deploy-mvp.sh` |
| :--- | :--- |
| **Falta de Facturación (Billing):** Proyectos nuevos sin cuenta de cobro fallan al habilitar Compute Engine (*Error 400 UREQ_PROJECT_BILLING_NOT_FOUND*). | Detecta si el proyecto no tiene facturación, lista tus cuentas de cobro activas con `gcloud billing accounts list` y la vincula de inmediato con `gcloud billing projects link`. |
| **Token OAuth vencido (*Error 401*):** Los tokens de `gcloud` caducan a los 60 minutos (*ACCESS_TOKEN_TYPE_UNSUPPORTED*). | Valida la expiración del token antes de iniciar. Si venció, lo refresca y asegura que `application_default_credentials.json` esté activo. |
| **APIs Fundacionales apagadas:** Error al consultar IAM o Service Usage. | Pre-habilita directamente con `gcloud` las APIs críticas (`serviceusage`, `cloudresourcemanager`, `iam`, `iamcredentials`). |
| **Service Account de Despliegue inexistente:** Terraform usa impersonación y falla con *404 Account deleted* si la cuenta fue borrada. | Crea la cuenta `${PROJECT_ID}@...`, le asigna rol `roles/owner` y te otorga `roles/iam.serviceAccountTokenCreator`, pausando 10 segundos para propagación en IAM. |
| **Conflicto 409 (Service Account Already Exists):** La cuenta ya existía en GCP pero no en el estado local de Terraform. | Si ya existe, el script la importa dinámicamente con `terraform import` antes de ejecutar el apply. |
| **Conflicto 409 en Cloud Run / Cloud Functions:** Despliegues interrumpidos que dejan huérfano el servicio `demo-rest-api-service`. | En caso de error 409 durante el apply, el script borra los remanentes huérfanos de Cloud Run/Functions y reanuda el apply automáticamente. |
| **Colisión de Estados (`tfstate`):** Cambiar de proyecto sobrescribía o destruía recursos del proyecto anterior. | Aísla el estado en archivos independientes por ID: `terraform.<PROJECT_ID>.tfstate`. Cada proyecto tiene su propia vida útil. |

---

## ❓ 5. ¿Por qué no veo Cloud Composer, Dataproc o Dataflow encendidos en la consola?

Es normal no ver clústeres permanentes corriendo inmediatamente en la consola de Google Cloud para estos tres servicios. A continuación se explica la razón arquitectónica de cada uno:

### 🎼 A. Cloud Composer (Apache Airflow)
* **Estado en MVP:** Desactivado por defecto (`enable_composer = false`).
* **Motivo:** Crear un entorno de Composer 3 toma entre **25 y 35 minutos** (levanta un clúster privado de GKE, base de datos Cloud SQL y pods de Airflow) y genera un costo fijo continuo de ~$300–$400 USD mensuales incluso en reposo.
* **Qué sí se creó:** Se crearon la subred de Composer (`composer_subnet`), las Service Accounts de orquestación y el bucket de almacenamiento para los DAGs (`composer_dag_bucket_mvp`).
* **Cómo encenderlo:** Puedes activarlo en cualquier momento ejecutando:
  ```bash
  ./deploy-mvp.sh "tu-project-id" --with-composer
  ```
  *(Terraform conservará todo lo creado previamente y solo agregará Composer 3).*

### ⚡ B. Dataproc (Apache Spark / Hadoop)
* **Estado en la arquitectura:** En el código oficial de Google Cloud para esta demo, **los clústeres estáticos permanentes están deliberadamente comentados**:
  ```hcl
  # NOTE: This is now done in Airflow, but has kept for reference
  /*
  resource "google_dataproc_cluster" "mycluster" { ... }
  */
  ```
* **Motivo:** Mantener un clúster clásico fijo (1 nodo master + 4 workers `n1-standard-8`) encendido 24/7 sin procesar datos cuesta cientos de dólares al mes en Compute Engine.
* **Modelo Efímero y Serverless:**
  1. **Infraestructura lista:** Terraform ya desplegó la subred clásica (`dataproc_subnet`), la subred serverless (`dataproc_serverless_subnet`), el bucket de staging (`dataproc-...`) y la Service Account (`dataproc-service-account`) con roles de BigLake, Metastore y Cloud Storage.
  2. **Ejecución bajo demanda:** 
     * Puedes ejecutar jobs de PySpark directamente con **Dataproc Serverless (Spark Batches)** sin necesidad de gestionar máquinas virtuales.
     * O cuando se activa el DAG en Airflow/Composer, este crea un clúster temporal, procesa los datos y **lo destruye automáticamente al terminar** (*ephemeral cluster*).

### 🌊 C. Dataflow (Apache Beam)
* **Estado en la arquitectura:** Dataflow en Google Cloud es **100% Serverless**. No existen servidores fijos que ver encendidos en la consola mientras no haya un job en ejecución.
* **Qué se aprovisionó:** Terraform configuró la subred dedicada (`dataflow_subnet`), las reglas de firewall y la cuenta de servicio (`dataflow-service-account`). Cuando se envía un pipeline de streaming o batch, Dataflow levanta los trabajadores automáticamente en esa red y los apaga al terminar.

---

## 🧹 6. Cómo Eliminar Todo Limpiamente (Undeploy)

Cuando termines tu laboratorio o desees liberar costos en Google Cloud, ejecuta:

```bash
./undeploy-mvp.sh "mi-nuevo-proyecto-123"
```

El script [`undeploy-mvp.sh`](file:///Users/anitaquevedo/Documents/Cursos/Utec/end-to-end/end-to-end-example1/undeploy-mvp.sh) realiza un barrido integral:
1. Elimina repositorios y workspaces anidados de Dataform vía REST API.
2. Desactiva la protección de borrado (*deletion protection*) en las tablas de BigQuery.
3. Ejecuta `terraform destroy` sobre el archivo de estado de ese proyecto.
4. Realiza una limpieza profunda directa por API de Cloud Run, Cloud Functions, Dataplex Lakes, Datasets de BigQuery, VPC `vpc-main` y Buckets de Cloud Storage.
5. Elimina el archivo `terraform.<PROJECT_ID>.tfstate` local, dejando el entorno listo para un despliegue futuro desde cero.

---

## 🔍 7. Tabla Rápida de Comandos

```bash
# 1. Despliegue estándar (Recomendado)
./deploy-mvp.sh "tu-project-id"

# 2. Despliegue completo (con Composer y Colab)
./deploy-mvp.sh "tu-project-id" --all

# 3. Ver logs detallados en tiempo real (en otra pestaña de terminal)
tail -f terraform/terraform_apply.log

# 4. Eliminar todos los recursos del proyecto
./undeploy-mvp.sh "tu-project-id"
```
