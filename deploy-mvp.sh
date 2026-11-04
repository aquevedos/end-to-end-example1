#!/usr/bin/env bash
####################################################################################
# Script de Despliegue Universal MVP (Cualquier ruta, correo y proyecto de GCP)
# Uso:
#   Opción A (Automático tomando tu sesión actual de gcloud):
#     ./deploy-mvp.sh
#
#   Opción B (Pasando correo y project_id explícitamente):
#     ./deploy-mvp.sh "cliente@gmail.com" "mi-proyecto-gcp-123"
####################################################################################
set -euo pipefail

# 1. Detecta automáticamente la ruta donde está descargado este repositorio
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${REPO_DIR}/terraform"

# 2. Obtiene correo (del 1er argumento o automáticamente de gcloud)
GCP_ACCOUNT_NAME="${1:-$(gcloud config get-value account 2>/dev/null)}"

# 3. Obtiene Project ID (del 2do argumento o automáticamente de gcloud)
PROJECT_ID="${2:-$(gcloud config get-value project 2>/dev/null)}"

if [[ -z "${GCP_ACCOUNT_NAME}" || -z "${PROJECT_ID}" ]]; then
  echo "❌ Error: Debes autenticarte en gcloud o pasar los parámetros:"
  echo "   ./deploy-mvp.sh <tu-correo@gmail.com> <tu-project-id>"
  exit 1
fi

# 4. Obtiene automáticamente el Project Number a partir del Project ID
PROJECT_NUMBER="${3:-$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)" 2>/dev/null)}"

if [[ -z "${PROJECT_NUMBER}" ]]; then
  echo "❌ Error: No se pudo obtener el project_number del proyecto '${PROJECT_ID}'."
  echo "   Verifica que el proyecto exista y que tu cuenta '${GCP_ACCOUNT_NAME}' tenga acceso."
  exit 1
fi

echo "=================================================================="
echo "🚀 Desplegando MVP Data Analytics Golden Demo en GCP"
echo "=================================================================="
echo "📂 Ruta del código : ${TF_DIR}"
echo "👤 Cuenta GCP      : ${GCP_ACCOUNT_NAME}"
echo "🆔 Project ID      : ${PROJECT_ID}"
echo "🔢 Project Number  : ${PROJECT_NUMBER}"
echo "=================================================================="

# 5. Ejecuta Terraform Init y Apply usando la ruta dinámica
terraform -chdir="${TF_DIR}" init

terraform -chdir="${TF_DIR}" apply \
  -var="gcp_account_name=${GCP_ACCOUNT_NAME}" \
  -var="project_id=${PROJECT_ID}" \
  -var="project_number=${PROJECT_NUMBER}"
