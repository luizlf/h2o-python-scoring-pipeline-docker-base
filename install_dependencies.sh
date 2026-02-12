#!/usr/bin/env bash
#
# Installs all DAI scoring pipeline shared dependencies into a virtualenv.
# Run during Docker image build. Installs everything EXCEPT the model-specific
# scoring_h2oai_experiment_*.whl file.
#
# This replicates the pip install logic from run_example.sh / run_http_server.sh
# for non-GPU (CPU-only) deployments.

set -eo pipefail
set -x

PIPELINE_DIR="/scoring/reference-pipeline"
ENV_DIR="/scoring/env"

cd "$PIPELINE_DIR"

export SKLEARN_ALLOW_DEPRECATED_SKLEARN_PACKAGE_INSTALL=True
export TMPDIR="/tmp/dai_tmp"
export TMP_DIR="$TMPDIR"
mkdir -p "$TMPDIR"

# --------------------------------------------------------------------------
# Create virtualenv
# --------------------------------------------------------------------------
virtualenv -p python3.8 --never-download --copies \
    --app-data /scoring/env_app_data_dir \
    --setuptools embed --pip embed --wheel embed "$ENV_DIR" \
    || virtualenv -p python3.8 --never-download "$ENV_DIR"

source "$ENV_DIR/bin/activate"

# Clean environment variables that could interfere
unset PYTHONPATH
unset PYTHONUSERBASE

# --------------------------------------------------------------------------
# Install base pip tooling
# --------------------------------------------------------------------------
python -m ensurepip
python -m pip install pip==21.1

PYTHON="$(realpath "$ENV_DIR/bin/python")"
spackagespath="$($PYTHON -c "from sysconfig import get_paths; info = get_paths(); print(info['purelib'])")"
echo "spackagespath=$spackagespath"

$PYTHON -m pip install --upgrade --upgrade-strategy only-if-needed \
    pip==21.1 setuptools==49.6.0 wheel==0.35.1 pkginfo==1.5.0.1 \
    -c req_constraints_deps.txt

# --------------------------------------------------------------------------
# Install main requirements (excluding scoring whl, xgboost, lightgbm)
# --------------------------------------------------------------------------
grep -v 'scoring_h2oai_experiment' requirements.txt \
    | grep -v 'xgboost-' | grep -v 'xgboost==' \
    | grep -v 'lightgbm-' | grep -v 'lightgbm=' \
    > /tmp/requirements_filtered.txt

$PYTHON -m pip install --use-deprecated=legacy-resolver \
    --upgrade --upgrade-strategy only-if-needed \
    -r /tmp/requirements_filtered.txt \
    -c req_constraints_deps.txt \
    -f https://download.pytorch.org/whl/torch_stable.html

# --------------------------------------------------------------------------
# Handle xgboost / lightgbm: move h2o4gpu copies, then install proper versions
# --------------------------------------------------------------------------
mv "$spackagespath/xgboost" "$spackagespath/xgboost_h2o4gpu" 2>/dev/null || true
mv "$spackagespath/lightgbm_gpu" "$spackagespath/lightgbm_gpu_h2o4gpu" 2>/dev/null || true
mv "$spackagespath/lightgbm_cpu" "$spackagespath/lightgbm_cpu_h2o4gpu" 2>/dev/null || true

grep 'xgboost-\|lightgbm-' requirements.txt > /tmp/requirements_xgb_lgb.txt || true
if [ -s /tmp/requirements_xgb_lgb.txt ]; then
    $PYTHON -m pip install --use-deprecated=legacy-resolver \
        --upgrade --upgrade-strategy only-if-needed \
        -r /tmp/requirements_xgb_lgb.txt \
        -c req_constraints_deps.txt \
        -f https://download.pytorch.org/whl/torch_stable.html
fi

# --------------------------------------------------------------------------
# Install CPU tensorflow (non-GPU deployment)
# --------------------------------------------------------------------------
$PYTHON -m pip uninstall -y tensorflow tensorflow-gpu nvidia-tensorflow 2>/dev/null || true

$PYTHON -m pip install --use-deprecated=legacy-resolver \
    tensorflow==2.4.4 --upgrade --upgrade-strategy only-if-needed \
    -c req_constraints_deps.txt
$PYTHON -m pip install --use-deprecated=legacy-resolver \
    tensorflow-estimator==2.4.0 --upgrade --upgrade-strategy only-if-needed \
    -c req_constraints_deps.txt
$PYTHON -m pip install --use-deprecated=legacy-resolver \
    tensorboard==2.4.1 --upgrade --upgrade-strategy only-if-needed \
    -c req_constraints_deps.txt

# Rename tensorflow directories for DAI's dynamic loading system
tf_path="$spackagespath/tensorflow"
if [ -d "$tf_path" ]; then
    rm -rf "${tf_path}_cpu"
    mv "$tf_path" "${tf_path}_cpu"
    mv "$spackagespath/tensorflow-2.4.4.dist-info" \
       "$spackagespath/tensorflow_cpu-2.4.4.dist-info" 2>/dev/null || true
    cp -a "$spackagespath/tensorflow_cpu-2.4.4.dist-info" \
       "$spackagespath/tensorflow-2.4.4.dist-info" 2>/dev/null || true
    ln -srf "$spackagespath/tensorflow_cpu" "$spackagespath/tensorflow"

    mv "$spackagespath/tensorflow_estimator" \
       "$spackagespath/tensorflow_estimator_dai" 2>/dev/null || true
    mv "$spackagespath/tensorflow_estimator-2.4.0.dist-info" \
       "$spackagespath/tensorflow_estimator_dai-2.4.0.dist-info" 2>/dev/null || true
    mv "$spackagespath/tensorboard" \
       "$spackagespath/tensorboard_dai" 2>/dev/null || true
    mv "$spackagespath/tensorboard-2.4.1.dist-info" \
       "$spackagespath/tensorboard_dai-2.4.1.dist-info" 2>/dev/null || true

    # Patch tensorflow for numpy 1.22.0+ compatibility
    for dir_to_fix in tensorflow tensorflow_cpu; do
        target="$spackagespath/$dir_to_fix/python/ops/array_ops.py"
        if [ -f "$target" ]; then
            sed -i '/from tensorflow.python.ops import math_ops/d' "$target"
            sed -i 's|from tensorflow.python.ops import gen_math_ops|from tensorflow.python.ops import gen_math_ops\nfrom tensorflow.python.ops import math_ops|g' "$target"
            sed -i 's|if np.prod(shape) < 1000:|if math_ops.reduce_prod(shape) < 1000:|g' "$target"
        fi
    done
fi

# --------------------------------------------------------------------------
# Install pyarrow (with ORC support for pip-based installs)
# --------------------------------------------------------------------------
$PYTHON -m pip install --use-deprecated=legacy-resolver \
    --no-deps --no-cache-dir --upgrade --upgrade-strategy only-if-needed \
    pyarrow==3.0.0

# --------------------------------------------------------------------------
# Install HTTP and TCP server dependencies
# --------------------------------------------------------------------------
$PYTHON -m pip install --use-deprecated=legacy-resolver \
    --upgrade --upgrade-strategy only-if-needed \
    -r http_server_requirements.txt \
    -c req_constraints_deps.txt \
    -f https://download.pytorch.org/whl/torch_stable.html

$PYTHON -m pip install --use-deprecated=legacy-resolver \
    --upgrade --upgrade-strategy only-if-needed \
    -r tcp_server_requirements.txt \
    -c req_constraints_deps.txt \
    -f https://download.pytorch.org/whl/torch_stable.html

# --------------------------------------------------------------------------
# Cleanup
# --------------------------------------------------------------------------
rm -f /tmp/requirements_filtered.txt /tmp/requirements_xgb_lgb.txt
deactivate

echo "=== All shared dependencies installed successfully ==="
