#!/usr/bin/env bash
####################################################################################
# Script de Despliegue Universal y Modular MVP (Cualquier ruta, correo y proyecto)
#
# Formas de uso:
#   1. Despliegue base rápido (usa tu cuenta y proyecto activos de gcloud):
#      ./deploy-mvp.sh
#
#   2. Despliegue en OTRO correo y OTRO proyecto (aislando su estado automáticamente):
#      ./deploy-mvp.sh "otro-correo@dominio.com" "otro-project-id"
#
#   3. Encender Cloud Composer y/o Colab Runtime (al inicio o en una 2da ejecución):
#      ./deploy-mvp.sh --with-composer
#      ./deploy-mvp.sh --with-colab
#      ./deploy-mvp.sh --all
#      ./deploy-mvp.sh "otro-correo@dominio.com" "otro-project-id" --all
####################################################################################
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${REPO_DIR}/terraform"

ENABLE_COMPOSER="${ENABLE_COMPOSER:-false}"
ENABLE_COLAB_RUNTIME="${ENABLE_COLAB_RUNTIME:-false}"
POS_ARGS=()

for arg in "$@"; do
  case "${arg}" in
    --with-composer)
      ENABLE_COMPOSER="true"
      ;;
    --with-colab)
      ENABLE_COLAB_RUNTIME="true"
      ;;
    --all)
      ENABLE_COMPOSER="true"
      ENABLE_COLAB_RUNTIME="true"
      ;;
    *)
      POS_ARGS+=("${arg}")
      ;;
  esac
done

GCP_ACCOUNT_NAME="${POS_ARGS[0]:-$(gcloud config get-value account 2>/dev/null || true)}"
PROJECT_ID="${POS_ARGS[1]:-$(gcloud config get-value project 2>/dev/null || true)}"

if [[ "${GCP_ACCOUNT_NAME}" == "otro-correo@dominio.com" || "${PROJECT_ID}" == "otro-proyecto-id" ]]; then
  echo "⚠️  Usaste los textos de ejemplo ('otro-correo@dominio.com' / 'otro-proyecto-id')."
  echo "👉 Reemplázalos por el correo y el Project ID reales de GCP donde quieres desplegar, por ejemplo:"
  echo "   ./deploy-mvp.sh \"admin@anitaquevedo.altostrat.com\" \"end-to-end-testing-513621\""
  exit 1
fi

if [[ -z "${GCP_ACCOUNT_NAME}" || -z "${PROJECT_ID}" ]]; then
  echo "❌ Error: Debes autenticarte en gcloud o pasar los parámetros:"
  echo "   ./deploy-mvp.sh <tu-correo-real@dominio.com> <tu-project-id-real> [--with-composer] [--with-colab] [--all]"
  exit 1
fi

export CLOUDSDK_CORE_ACCOUNT="${GCP_ACCOUNT_NAME}"
export CLOUDSDK_CORE_PROJECT="${PROJECT_ID}"
export CLOUDSDK_BILLING_QUOTA_PROJECT=""
export CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT=""

# 1. Verifica que exista un token OAuth realmente válido para ese correo (validando contra tokeninfo)
ACCESS_TOKEN="$(gcloud auth print-access-token --account="${GCP_ACCOUNT_NAME}" 2>/dev/null || true)"
TOKEN_VALID="$(curl -s "https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=${ACCESS_TOKEN}" | grep -o '"issued_to"' || true)"

if [[ -z "${ACCESS_TOKEN}" || -z "${TOKEN_VALID}" ]]; then
  echo "🔑 Iniciando sesión en gcloud para '${GCP_ACCOUNT_NAME}'..."
  gcloud auth login "${GCP_ACCOUNT_NAME}"
  ACCESS_TOKEN="$(gcloud auth print-access-token --account="${GCP_ACCOUNT_NAME}" 2>/dev/null || true)"
fi

if [[ -z "${ACCESS_TOKEN}" ]]; then
  echo "❌ Error: No se pudo obtener el token de acceso para '${GCP_ACCOUNT_NAME}'."
  exit 1
fi
export GOOGLE_OAUTH_ACCESS_TOKEN="${ACCESS_TOKEN}"

# 2. Obtiene el Project Number (1ro del 3er argumento si se pasó, 2do de gcloud, 3ro vía API REST directa con curl)
PROJECT_NUMBER="${POS_ARGS[2]:-}"

if [[ -z "${PROJECT_NUMBER}" ]]; then
  PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --account="${GCP_ACCOUNT_NAME}" --format="value(projectNumber)" 2>/dev/null || true)"
fi

if [[ -z "${PROJECT_NUMBER}" ]]; then
  CRM_RESP="$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID}" || true)"
  PROJECT_NUMBER="$(echo "${CRM_RESP}" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('projectNumber',''))" 2>/dev/null || true)"
fi

if [[ -z "${PROJECT_NUMBER}" ]]; then
  echo "❌ Error: No se pudo encontrar el Project ID '${PROJECT_ID}' con la cuenta '${GCP_ACCOUNT_NAME}'."
  echo "🔎 Detalle devuelto por Google Cloud:"
  gcloud projects describe "${PROJECT_ID}" --account="${GCP_ACCOUNT_NAME}" 2>&1 || true
  echo ""
  echo "📋 Proyectos disponibles actualmente para '${GCP_ACCOUNT_NAME}':"
  gcloud projects list --account="${GCP_ACCOUNT_NAME}" --format="table(projectId,name,projectNumber)" || true
  echo ""
  echo "💡 Tip: También puedes pasar el Project Number directamente como 3er parámetro:"
  echo "   ./deploy-mvp.sh \"${GCP_ACCOUNT_NAME}\" \"${PROJECT_ID}\" \"158808485666\""
  exit 1
fi

# 3. Aislamiento modular de estado (tfstate) por proyecto
STATE_ARG=()
STATE_LABEL="terraform.tfstate (por defecto)"
if [[ -f "${TF_DIR}/terraform.tfstate" ]]; then
  EXISTING_STATE_PROJECT="$(python3 -c "import json; d=json.load(open('${TF_DIR}/terraform.tfstate')); print(d.get('outputs',{}).get('project_id',{}).get('value',''))" 2>/dev/null || true)"
  if [[ -n "${EXISTING_STATE_PROJECT}" && "${EXISTING_STATE_PROJECT}" != "${PROJECT_ID}" ]]; then
    STATE_FILE="terraform.${PROJECT_ID}.tfstate"
    STATE_ARG=("-state=${STATE_FILE}")
    STATE_LABEL="${STATE_FILE} (aislado para ${PROJECT_ID})"
  fi
fi

echo "=================================================================="
echo "🚀 Desplegando Data Analytics Golden Demo en GCP (Modo Modular)"
echo "=================================================================="
echo "📂 Ruta del código      : ${TF_DIR}"
echo "👤 Cuenta GCP           : ${GCP_ACCOUNT_NAME}"
echo "🆔 Project ID           : ${PROJECT_ID}"
echo "🔢 Project Number       : ${PROJECT_NUMBER}"
echo "🎼 Cloud Composer       : ${ENABLE_COMPOSER}"
echo "📓 Colab Runtime VM     : ${ENABLE_COLAB_RUNTIME}"
echo "💾 Estado Terraform     : ${STATE_LABEL}"
echo "=================================================================="

terraform -chdir="${TF_DIR}" init

terraform -chdir="${TF_DIR}" apply -auto-approve \
  "${STATE_ARG[@]}" \
  -var="gcp_account_name=${GCP_ACCOUNT_NAME}" \
  -var="project_id=${PROJECT_ID}" \
  -var="project_number=${PROJECT_NUMBER}" \
  -var="enable_composer=${ENABLE_COMPOSER}" \
  -var="enable_colab_runtime=${ENABLE_COLAB_RUNTIME}"
