#!/usr/bin/env bash
#
# Loads a new scoring pipeline from a .zip archive.
# Extracts the archive and installs ONLY the model-specific
# scoring_h2oai_experiment_*.whl into the pre-built virtualenv.
#
# All other dependencies must already be installed (via install_dependencies.sh).
#
# Usage: load_pipeline.sh <path-to-scoring-pipeline.zip>

set -eo pipefail
set -x

PIPELINE_ZIP="${1:?Usage: load_pipeline.sh <path-to-scoring-pipeline.zip>}"
ENV_DIR="/scoring/env"
PIPELINE_DIR="/scoring/pipeline"

# --------------------------------------------------------------------------
# Extract the archive
# --------------------------------------------------------------------------
rm -rf "$PIPELINE_DIR" /tmp/pipeline_extract
mkdir -p /tmp/pipeline_extract

echo "Extracting pipeline from $PIPELINE_ZIP..."
unzip -o "$PIPELINE_ZIP" -d /tmp/pipeline_extract

# The zip may contain files directly or inside a subdirectory.
# Find the scoring whl to locate the actual pipeline root.
SCORING_WHL="$(find /tmp/pipeline_extract -name 'scoring_h2oai_experiment*.whl' -print -quit)"
if [ -z "$SCORING_WHL" ]; then
    echo "Error: No scoring_h2oai_experiment*.whl found in the archive."
    exit 1
fi
EXTRACTED_DIR="$(dirname "$SCORING_WHL")"

mv "$EXTRACTED_DIR" "$PIPELINE_DIR"
rm -rf /tmp/pipeline_extract

# --------------------------------------------------------------------------
# Install the scoring module
# --------------------------------------------------------------------------
cd "$PIPELINE_DIR"

source "$ENV_DIR/bin/activate"
PYTHON="$(realpath "$ENV_DIR/bin/python")"

SCORING_WHL_FILE=$(ls scoring_h2oai_experiment*.whl)
MODULE_NAME=$(basename "$SCORING_WHL_FILE" | sed 's/-[0-9].*//')

echo "Installing scoring module ($MODULE_NAME)..."
$PYTHON -m pip install --no-deps "$SCORING_WHL_FILE"

if ! $PYTHON -c "import $MODULE_NAME" 2>/dev/null; then
    echo "Error: $MODULE_NAME failed to import after installation."
    exit 1
fi

deactivate

# --------------------------------------------------------------------------
# Cleanup: remove all .whl files except the scoring model
# --------------------------------------------------------------------------
echo "Cleaning up .whl files..."
find "$PIPELINE_DIR" -name '*.whl' ! -name 'scoring_h2oai_experiment*' -delete

echo "=== Pipeline loaded successfully ==="
