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

# 2. Obtiene correo (del 1er argumento o automáticamente de gcloud)
GCP_ACCOUNT_NAME="${1:-$(gcloud config get-value account 2>/dev/null)}"

# 3. Obtiene Project ID (del 2do argumento o automáticamente de gcloud)
PROJECT_ID="${2:-$(gcloud config get-value project 2>/dev/null)}"

if [[ -z "${GCP_ACCOUNT_NAME}" || -z "${PROJECT_ID}" ]]; then
  echo "❌ Error: Debes autenticarte en gcloud o pasar los parámetros:"
  echo "   ./undeploy-mvp.sh <tu-correo@gmail.com> <tu-project-id>"
  exit 1
fi

# 4. Obtiene automáticamente el Project Number a partir del Project ID
PROJECT_NUMBER="${3:-$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)" 2>/dev/null)}"

echo "=================================================================="
echo "🧹 Iniciando UNDEPLOY (Eliminación de recursos MVP en GCP)"
echo "=================================================================="
echo "📂 Ruta Terraform  : ${TF_DIR}"
echo "👤 Cuenta GCP      : ${GCP_ACCOUNT_NAME}"
echo "🆔 Project ID      : ${PROJECT_ID}"
echo "🔢 Project Number  : ${PROJECT_NUMBER}"
echo "=================================================================="

# 5. Limpia recursos anidados de Dataform (Workspaces y Notebooks creados vía REST API) con ?force=true
echo "🔄 Limpiando repositorios y workspaces anidados de Dataform..."
ACCESS_TOKEN="$(gcloud auth print-access-token 2>/dev/null || true)"
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

if terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep -q "module.resources.google_bigquery_table."; then
  echo "🔄 Sincronizando deletion_protection=false en el estado de Terraform..."
  terraform -chdir="${TF_DIR}" apply -auto-approve \
    -target="module.resources.google_bigquery_table.default" \
    -target="module.resources.google_bigquery_table.taxi_trips_streaming" \
    -var="gcp_account_name=${GCP_ACCOUNT_NAME}" \
    -var="project_id=${PROJECT_ID}" \
    -var="project_number=${PROJECT_NUMBER}" >/dev/null 2>&1 || true
fi

# 7. Evita que Terraform desactive las APIs base del proyecto o quite permisos IAM al usuario dueño del proyecto
if terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep -q "module.apis-batch-enable"; then
  echo "🔄 Conservando APIs base activas en el proyecto (evitando errores de dependencia entre APIs)..."
  terraform -chdir="${TF_DIR}" state rm "module.apis-batch-enable" >/dev/null 2>&1 || true
fi

if terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep -q "module.service-account.google_project_iam_member.gcp_account_owner"; then
  terraform -chdir="${TF_DIR}" state rm "module.service-account.google_project_iam_member.gcp_account_owner" >/dev/null 2>&1 || true
fi

if terraform -chdir="${TF_DIR}" state list 2>/dev/null | grep -q "module.service-account.google_project_iam_member.impersonation_account_owner"; then
  terraform -chdir="${TF_DIR}" state rm "module.service-account.google_project_iam_member.impersonation_account_owner" >/dev/null 2>&1 || true
fi

# 8. Ejecuta Terraform Destroy
terraform -chdir="${TF_DIR}" destroy \
  -var="gcp_account_name=${GCP_ACCOUNT_NAME}" \
  -var="project_id=${PROJECT_ID}" \
  -var="project_number=${PROJECT_NUMBER}"

echo "✅ Todos los recursos del MVP han sido eliminados correctamente."
