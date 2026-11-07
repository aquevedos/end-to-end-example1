#!/usr/bin/env bash
####################################################################################
# Script de Eliminación / Undeploy Universal MVP (Terraform Destroy + Limpieza)
# Uso:
#   Opción A (Automático tomando tu sesión actual de gcloud):
#     ./undeploy-mvp.sh
#
#   Opción B (Pasando correo y project_id explícitamente):
#     ./undeploy-mvp.sh "cliente@gmail.com" "mi-proyecto-gcp-123"
####################################################################################
set -euo pipefail

# 1. Detecta automáticamente la ruta donde está este repositorio
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${REPO_DIR}/terraform"

# 2. Detección inteligente de correo, project_id y project_number
RAW_ARG0="${1:-}"
RAW_ARG1="${2:-}"
RAW_ARG2="${3:-}"

GCP_ACCOUNT_NAME=""
PROJECT_ID=""
PROJECT_NUMBER=""

if [[ -n "${RAW_ARG0}" && -z "${RAW_ARG1}" ]]; then
  if [[ "${RAW_ARG0}" == *"@"* ]]; then
    GCP_ACCOUNT_NAME="${RAW_ARG0}"
    PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
  else
    PROJECT_ID="${RAW_ARG0}"
    GCP_ACCOUNT_NAME="$(gcloud config get-value account 2>/dev/null || true)"
  fi
elif [[ -n "${RAW_ARG0}" && -n "${RAW_ARG1}" ]]; then
  if [[ "${RAW_ARG0}" != *"@"* && "${RAW_ARG1}" == *"@"* ]]; then
    PROJECT_ID="${RAW_ARG0}"
    GCP_ACCOUNT_NAME="${RAW_ARG1}"
  else
    GCP_ACCOUNT_NAME="${RAW_ARG0}"
    PROJECT_ID="${RAW_ARG1}"
  fi
  PROJECT_NUMBER="${RAW_ARG2}"
else
  GCP_ACCOUNT_NAME="$(gcloud config get-value account 2>/dev/null || true)"
  PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
fi

if [[ -z "${GCP_ACCOUNT_NAME}" || -z "${PROJECT_ID}" ]]; then
  echo "❌ Error: Debes autenticarte en gcloud o pasar los parámetros:"
  echo "   ./undeploy-mvp.sh [tu-correo@gmail.com] [tu-project-id]"
  exit 1
fi

export CLOUDSDK_CORE_ACCOUNT="${GCP_ACCOUNT_NAME}"
export CLOUDSDK_CORE_PROJECT="${PROJECT_ID}"

# 4. Obtiene el Project Number si no fue provisto
if [[ -z "${PROJECT_NUMBER}" ]]; then
  PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --account="${GCP_ACCOUNT_NAME}" --format="value(projectNumber)" 2>/dev/null || true)"
fi

STATE_ARG=()
STATE_LABEL="terraform.tfstate (por defecto)"
if [[ -f "${TF_DIR}/terraform.${PROJECT_ID}.tfstate" ]]; then
  STATE_ARG=("-state=terraform.${PROJECT_ID}.tfstate")
  STATE_LABEL="terraform.${PROJECT_ID}.tfstate (aislado para ${PROJECT_ID})"
fi

echo "=================================================================="
echo "🧹 Iniciando UNDEPLOY (Eliminación de recursos MVP en GCP)"
echo "=================================================================="
echo "📂 Ruta Terraform  : ${TF_DIR}"
echo "👤 Cuenta GCP      : ${GCP_ACCOUNT_NAME}"
echo "🆔 Project ID      : ${PROJECT_ID}"
echo "🔢 Project Number  : ${PROJECT_NUMBER}"
echo "💾 Estado Terraform: ${STATE_LABEL}"
echo "=================================================================="

# 5. Limpia recursos anidados de Dataform (Workspaces y Notebooks creados vía REST API) con ?force=true
echo "🔄 Limpiando repositorios y workspaces anidados de Dataform..."
ACCESS_TOKEN="$(gcloud auth print-access-token --account="${GCP_ACCOUNT_NAME}" 2>/dev/null || true)"
if [[ -n "${ACCESS_TOKEN}" ]]; then
  export GOOGLE_OAUTH_ACCESS_TOKEN="${ACCESS_TOKEN}"
  curl -s -X DELETE \
    --header "Authorization: Bearer ${ACCESS_TOKEN}" \
    "https://dataform.googleapis.com/v1beta1/projects/${PROJECT_ID}/locations/us-central1/repositories/dataform_golden_demo/workspaces/demo_flow" >/dev/null 2>&1 || true

  # Lista todos los repositorios de Dataform en us-central1 y los borra con ?force=true para evitar bloqueos por recursos anidados
  REPOS=$(curl -s --header "Authorization: Bearer ${ACCESS_TOKEN}" \
    "https://dataform.googleapis.com/v1beta1/projects/${PROJECT_ID}/locations/us-central1/repositories" \
    | grep -o "\"projects/${PROJECT_ID}/locations/us-central1/repositories/[^\"]*\"" | tr -d '"' || true)

  for REPO_NAME in ${REPOS}; do
    curl -s -X DELETE \
      --header "Authorization: Bearer ${ACCESS_TOKEN}" \
      "https://dataform.googleapis.com/v1beta1/${REPO_NAME}?force=true" >/dev/null 2>&1 || true
  done
fi

# 6. Desactiva protección de borrado en tablas BigQuery previas (en GCP y en el estado local de Terraform) y limpia dataset suscrito por curl
bq update --deletion_protection=false "${PROJECT_ID}:taxi_dataset.taxi_trips_with_col_sec" 2>/dev/null || true
bq update --deletion_protection=false "${PROJECT_ID}:taxi_dataset.taxi_trips_streaming" 2>/dev/null || true
bq rm -r -f -d "${PROJECT_ID}:ghcn_daily" 2>/dev/null || true

if terraform -chdir="${TF_DIR}" state list "${STATE_ARG[@]}" 2>/dev/null | grep -q "module.resources.google_bigquery_table."; then
  echo "🔄 Sincronizando deletion_protection=false en el estado de Terraform..."
  terraform -chdir="${TF_DIR}" apply -auto-approve \
    "${STATE_ARG[@]}" \
    -target="module.resources.google_bigquery_table.default" \
    -target="module.resources.google_bigquery_table.taxi_trips_streaming" \
    -var="gcp_account_name=${GCP_ACCOUNT_NAME}" \
    -var="project_id=${PROJECT_ID}" \
    -var="project_number=${PROJECT_NUMBER}" >/dev/null 2>&1 || true
fi

# 7. Evita que Terraform desactive las APIs base del proyecto o quite permisos IAM al usuario dueño del proyecto
if terraform -chdir="${TF_DIR}" state list "${STATE_ARG[@]}" 2>/dev/null | grep -q "module.apis-batch-enable"; then
  echo "🔄 Conservando APIs base activas en el proyecto (evitando errores de dependencia entre APIs)..."
  terraform -chdir="${TF_DIR}" state rm "${STATE_ARG[@]}" "module.apis-batch-enable" >/dev/null 2>&1 || true
fi

if terraform -chdir="${TF_DIR}" state list "${STATE_ARG[@]}" 2>/dev/null | grep -q "module.service-account.google_project_iam_member.gcp_account_owner"; then
  terraform -chdir="${TF_DIR}" state rm "${STATE_ARG[@]}" "module.service-account.google_project_iam_member.gcp_account_owner" >/dev/null 2>&1 || true
fi

if terraform -chdir="${TF_DIR}" state list "${STATE_ARG[@]}" 2>/dev/null | grep -q "module.service-account.google_project_iam_member.impersonation_account_owner"; then
  terraform -chdir="${TF_DIR}" state rm "${STATE_ARG[@]}" "module.service-account.google_project_iam_member.impersonation_account_owner" >/dev/null 2>&1 || true
fi

# 8. Intento de Terraform Destroy (ignora errores de estado incompleto para proceder al barrido directo)
set +e
terraform -chdir="${TF_DIR}" destroy -auto-approve \
  "${STATE_ARG[@]}" \
  -var="gcp_account_name=${GCP_ACCOUNT_NAME}" \
  -var="project_id=${PROJECT_ID}" \
  -var="project_number=${PROJECT_NUMBER}"
set -e

# 9. Barrido Exhaustivo Directo en GCP (Elimina cualquier recurso huérfano fuera del tfstate)
echo "=================================================================="
echo "🧹 Realizando barrido directo en GCP para eliminar recursos huérfanos..."
echo "=================================================================="

# 9.1 BigQuery Datasets
echo "📊 Eliminando datasets de BigQuery..."
DEMO_DATASETS=(
  "taxi_dataset"
  "thelook_ecommerce"
  "rideshare_lakehouse_raw"
  "rideshare_lakehouse_enriched"
  "rideshare_lakehouse_curated"
  "rideshare_llm_raw"
  "rideshare_llm_enriched"
  "rideshare_llm_curated"
  "nyc_rideshare_data_nyc_rideshare_tables"
  "aws_omni_biglake"
  "azure_omni_biglake"
  "ghcn_daily"
)
for ds in "${DEMO_DATASETS[@]}"; do
  bq rm -r -f -d "${PROJECT_ID}:${ds}" 2>/dev/null || true
done

# 9.2 BigQuery Connections y Data Policies
echo "🔗 Eliminando conexiones y data policies de BigQuery..."
bq rm --connection --location=us -f "projects/${PROJECT_NUMBER}/locations/us/connections/cloud-function" 2>/dev/null || true
bq rm --connection --location=us -f "cloud-function" 2>/dev/null || true
gcloud beta bigquery data-policies delete Hash_Rule --location=us --project="${PROJECT_ID}" --quiet 2>/dev/null || true

# 9.3 Cloud Functions y Cloud Run
echo "⚡ Eliminando Cloud Functions y Cloud Run..."
gcloud functions delete bigquery_external_function --region=us-central1 --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud functions delete rideshare_plus_function --region=us-central1 --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud run services delete demo-rest-api-service --region=us-central1 --project="${PROJECT_ID}" --quiet 2>/dev/null || true

# 9.4 Pub/Sub Topics
echo "📬 Eliminando tópicos Pub/Sub..."
gcloud pubsub topics delete taxirides-realtime-mvp --project="${PROJECT_ID}" --quiet 2>/dev/null || true

# 9.5 Dataplex (Aspect Types, Zones y Lakes)
echo "🌊 Eliminando recursos Dataplex..."
gcloud dataplex aspect-types delete table-dq-tag-template --location=us-central1 --project="${PROJECT_ID}" --quiet 2>/dev/null || true

LAKES=$(gcloud dataplex lakes list --location=us-central1 --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null || true)
for lake in ${LAKES}; do
  LAKE_ID=$(basename "${lake}")
  ZONES=$(gcloud dataplex zones list --lake="${LAKE_ID}" --location=us-central1 --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null || true)
  for zone in ${ZONES}; do
    ZONE_ID=$(basename "${zone}")
    gcloud dataplex zones delete "${ZONE_ID}" --lake="${LAKE_ID}" --location=us-central1 --project="${PROJECT_ID}" --quiet 2>/dev/null || true
  done
  gcloud dataplex lakes delete "${LAKE_ID}" --location=us-central1 --project="${PROJECT_ID}" --quiet 2>/dev/null || true
done

# 9.6 Artifact Registry
echo "📦 Eliminando repositorios Artifact Registry..."
gcloud artifacts repositories delete artifact_registry_cloud_run_deploy --location=us-central1 --project="${PROJECT_ID}" --quiet 2>/dev/null || true

# 9.7 Dataproc & Datastream
echo "⚙️  Eliminando clusters Dataproc..."
gcloud dataproc clusters delete mycluster --region=us-central1 --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud datastream private-connections delete datastream_cloud-sql-private-connect --location=us-central1 --project="${PROJECT_ID}" --quiet 2>/dev/null || true

# 9.8 Service Accounts de la demo
echo "👤 Eliminando Service Accounts..."
DEMO_SAS=(
  "dataproc-service-account"
  "composer-service-account"
  "dataflow-service-account"
  "rideshare-plus-service-account"
  "${PROJECT_ID}"
)
for sa in "${DEMO_SAS[@]}"; do
  gcloud iam service-accounts delete "${sa}@${PROJECT_ID}.iam.gserviceaccount.com" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
done

# 9.9 IAM Custom Roles
echo "🛡️  Eliminando roles IAM personalizados..."
gcloud iam roles delete CustomConnectionDelegate --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud iam roles delete CustomDelegate --project="${PROJECT_ID}" --quiet 2>/dev/null || true

# 9.10 Red VPC, Subnets y Firewall
echo "🌐 Eliminando reglas de firewall, subnets y VPC vpc-main..."
RULES=$(gcloud compute firewall-rules list --project="${PROJECT_ID}" --filter="network:vpc-main" --format="value(name)" 2>/dev/null || true)
for rule in ${RULES}; do
  gcloud compute firewall-rules delete "${rule}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
done

ROUTERS=$(gcloud compute routers list --project="${PROJECT_ID}" --filter="network:vpc-main" --format="value(name,region)" 2>/dev/null || true)
while read -r r_name r_reg; do
  if [[ -n "${r_name}" ]]; then
    gcloud compute routers delete "${r_name}" --region="${r_reg}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
  fi
done <<< "${ROUTERS}"

SUBNETS=$(gcloud compute networks subnets list --project="${PROJECT_ID}" --network=vpc-main --format="value(name,region)" 2>/dev/null || true)
while read -r s_name s_reg; do
  if [[ -n "${s_name}" ]]; then
    gcloud compute networks subnets delete "${s_name}" --region="${s_reg}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
  fi
done <<< "${SUBNETS}"

gcloud compute networks delete vpc-main --project="${PROJECT_ID}" --quiet 2>/dev/null || true

# 9.11 Storage Buckets de la demo
echo "🪣 Eliminando Cloud Storage buckets de la demo..."
DEMO_BUCKETS=$(gcloud storage buckets list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null || true)
for b in ${DEMO_BUCKETS}; do
  if [[ "${b}" =~ (raw-|processed-|code-|rideshare-lakehouse|iceberg-|mt-|dags-|dataproc-|taxi-data-lake) ]]; then
    echo "   🗑️ Borrando bucket gs://${b}..."
    gcloud storage rm --recursive "gs://${b}" 2>/dev/null || true
  fi
done

# 9.12 Reseteo de archivos de estado local de Terraform
echo "💾 Reseteando estado local de Terraform..."
rm -f "${TF_DIR}/terraform.tfstate" "${TF_DIR}/terraform.tfstate.backup" "${TF_DIR}/terraform.${PROJECT_ID}.tfstate"* "${TF_DIR}/tf-output.json" "${TF_DIR}/terraform_apply.log"

echo "=================================================================="
echo "✅ ¡TODOS los recursos del MVP han sido eliminados por completo!"
echo "   El proyecto '${PROJECT_ID}' está limpio y listo para un nuevo despliegue."
echo "=================================================================="
