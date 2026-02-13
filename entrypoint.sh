#!/usr/bin/env bash
#
# Docker entrypoint for the DAI scoring pipeline container.
#
# Loads a scoring pipeline .zip, installs its model-specific whl,
# and starts the HTTP scoring server.
#
# Usage:
#   docker run -p 9090:9090 \
#       -e DRIVERLESS_AI_LICENSE_KEY="<key>" \
#       -v /path/to/pipeline.zip:/scoring/pipeline.zip \
#       h2o-python-scoring-pipeline-docker-base
#
# Environment variables:
#   DRIVERLESS_AI_LICENSE_KEY   DAI license key (base64)
#   DRIVERLESS_AI_LICENSE_FILE  Path to DAI license file (alternative to KEY)
#   SCORING_PORT                HTTP server port (default: 9090)

set -eo pipefail

PIPELINE_ZIP="${1:-/scoring/pipeline.zip}"
SCORING_PORT="${SCORING_PORT:-9090}"
ENV_DIR="/scoring/env"

# --------------------------------------------------------------------------
# Validate inputs
# --------------------------------------------------------------------------
if [ ! -f "$PIPELINE_ZIP" ]; then
    echo "Error: Scoring pipeline zip not found at '$PIPELINE_ZIP'"
    echo ""
    echo "Mount a pipeline zip file:"
    echo "  docker run -v /path/to/pipeline.zip:/scoring/pipeline.zip ..."
    echo ""
    echo "Or pass the path as an argument:"
    echo "  docker run <image> /path/to/pipeline.zip"
    exit 1
fi

if [ -z "$DRIVERLESS_AI_LICENSE_KEY" ] && [ -z "$DRIVERLESS_AI_LICENSE_FILE" ]; then
    echo "Warning: Neither DRIVERLESS_AI_LICENSE_KEY nor DRIVERLESS_AI_LICENSE_FILE is set."
    echo "The scoring pipeline requires a valid Driverless AI license."
fi

# --------------------------------------------------------------------------
# Load the scoring pipeline (extract zip + install scoring whl)
# --------------------------------------------------------------------------
echo "Loading scoring pipeline from $PIPELINE_ZIP..."
bash /scoring/load_pipeline.sh "$PIPELINE_ZIP"

# --------------------------------------------------------------------------
# Start the HTTP scoring server
# --------------------------------------------------------------------------
cd /scoring/pipeline

source "$ENV_DIR/bin/activate"

export SKLEARN_ALLOW_DEPRECATED_SKLEARN_PACKAGE_INSTALL=True
export TMPDIR="/tmp/dai_tmp"
export TMP_DIR="$TMPDIR"
mkdir -p "$TMPDIR"

# Disable H2O-3 recipe server (requires Java, not needed for scoring)
export DRIVERLESS_AI_ENABLE_H2O_RECIPES="${DRIVERLESS_AI_ENABLE_H2O_RECIPES:-0}"
export dai_enable_h2o_recipes="${dai_enable_h2o_recipes:-0}"
export dai_enable_custom_recipes="${dai_enable_custom_recipes:-0}"

PYTHON="$(realpath "$ENV_DIR/bin/python")"
LD_LIBRARY_PATH="$($PYTHON -c "from sysconfig import get_paths; import os; info = get_paths(); print(os.path.dirname(info['stdlib']))")"${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export LD_LIBRARY_PATH

echo "Starting HTTP scoring server on port $SCORING_PORT..."
exec $PYTHON http_server.py --port="$SCORING_PORT"
