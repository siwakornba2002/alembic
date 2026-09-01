#!/usr/bin/env bash
set -Eeuo pipefail

ALEMBIC_VERSION="1.8.12"
IMATH_VERSION="3.1.12"
BOOST_VERSION="1.85.0"
PYTHON_TAG="cp39-cp39"

# GitHub checks out the fork here. Build this exact Alembic commit rather than
# cloning upstream again, so branches and source changes in the fork are tested.
ALEMBIC_SOURCE_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
WORK_DIR="${ALEMBIC_SOURCE_DIR}/.pyalembic-build"
SOURCE_DIR="${WORK_DIR}/sources"
BUILD_DIR="${WORK_DIR}/build"
PREFIX_DIR="${WORK_DIR}/prefix"
RAW_WHEEL_DIR="${WORK_DIR}/raw-wheel"
WHEELHOUSE="${ALEMBIC_SOURCE_DIR}/wheelhouse"
PYTHON_ROOT="/opt/python/${PYTHON_TAG}"
PYTHON_BIN="${PYTHON_ROOT}/bin/python"

rm -rf "${WORK_DIR}" "${WHEELHOUSE}"
mkdir -p "${SOURCE_DIR}" "${BUILD_DIR}" "${PREFIX_DIR}" "${RAW_WHEEL_DIR}" "${WHEELHOUSE}"

"${PYTHON_BIN}" -m pip install --disable-pip-version-check \
  "cmake>=3.29,<4" ninja "numpy<2" wheel auditwheel

export PATH="${PYTHON_ROOT}/bin:${PATH}"
export LD_LIBRARY_PATH="${PREFIX_DIR}/lib:${LD_LIBRARY_PATH:-}"

git clone --branch "v${IMATH_VERSION}" --depth 1 \
  https://github.com/AcademySoftwareFoundation/Imath.git "${SOURCE_DIR}/imath"

# PyImath uses Boost.Python. The official Boost release archive contains all
# Boost subprojects, unlike GitHub's automatically generated source archive.
BOOST_ARCHIVE_VERSION="${BOOST_VERSION//./_}"
curl --fail --location --retry 3 \
  "https://archives.boost.io/release/${BOOST_VERSION}/source/boost_${BOOST_ARCHIVE_VERSION}.tar.bz2" \
  --output "${SOURCE_DIR}/boost.tar.bz2"
tar -xf "${SOURCE_DIR}/boost.tar.bz2" -C "${SOURCE_DIR}"

pushd "${SOURCE_DIR}/boost_${BOOST_ARCHIVE_VERSION}"
./bootstrap.sh \
  --prefix="${PREFIX_DIR}" \
  --with-libraries=python \
  --with-python="${PYTHON_BIN}" \
  --with-python-root="${PYTHON_ROOT}"
./b2 -j2 \
  variant=release \
  link=shared \
  runtime-link=shared \
  threading=multi \
  cxxstd=17 \
  --with-python \
  install
popd

# Alembic asks CMake for Boost's generic "python" component, while modern
# Boost names the CPython 3.9 library boost_python39.
BOOST_PYTHON_LIBRARY="$(find "${PREFIX_DIR}/lib" -maxdepth 1 -name 'libboost_python39.so' -print -quit)"
test -n "${BOOST_PYTHON_LIBRARY}"
ln -s "$(basename "${BOOST_PYTHON_LIBRARY}")" "${PREFIX_DIR}/lib/libboost_python.so"

cmake -S "${SOURCE_DIR}/imath" -B "${BUILD_DIR}/imath" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX_DIR}" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_PREFIX_PATH="${PREFIX_DIR}" \
  -DBoost_ROOT="${PREFIX_DIR}" \
  -DBoost_NO_BOOST_CMAKE=ON \
  -DPYTHON=ON \
  -DPython_EXECUTABLE="${PYTHON_BIN}" \
  -DPython3_EXECUTABLE="${PYTHON_BIN}" \
  -DPYIMATH_OVERRIDE_PYTHON_INSTALL_DIR=lib/python3.9/site-packages \
  -DBUILD_TESTING=OFF
cmake --build "${BUILD_DIR}/imath" --target install --parallel 2

cmake -S "${ALEMBIC_SOURCE_DIR}" -B "${BUILD_DIR}/alembic" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX_DIR}" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_PREFIX_PATH="${PREFIX_DIR}" \
  -DBoost_ROOT="${PREFIX_DIR}" \
  -DBoost_NO_BOOST_CMAKE=ON \
  -DImath_DIR="${PREFIX_DIR}/lib/cmake/Imath" \
  -DPython_EXECUTABLE="${PYTHON_BIN}" \
  -DALEMBIC_PYTHON_INSTALL_DIR=lib/python3.9/site-packages \
  -DUSE_PYALEMBIC=ON \
  -DUSE_BINARIES=OFF \
  -DUSE_TESTS=OFF
cmake --build "${BUILD_DIR}/alembic" --target install --parallel 2

# Package Alembic and its required Imath Python module. auditwheel bundles
# their non-manylinux shared libraries into the repaired wheel.
SITE_PACKAGES="${PREFIX_DIR}/lib/python3.9/site-packages"
find "${SITE_PACKAGES}" -maxdepth 1 -type f \
  \( -name 'alembic*.so' -o -name 'imath*.so' \) \
  -exec cp -v '{}' "${RAW_WHEEL_DIR}/" ';'

test -n "$(find "${RAW_WHEEL_DIR}" -maxdepth 1 -name 'alembic*.so' -print -quit)"
test -n "$(find "${RAW_WHEEL_DIR}" -maxdepth 1 -name 'imath*.so' -print -quit)"

DIST_INFO="${RAW_WHEEL_DIR}/pyalembic_aswf-${ALEMBIC_VERSION}.dist-info"
mkdir -p "${DIST_INFO}"
cat > "${DIST_INFO}/METADATA" <<EOF
Metadata-Version: 2.1
Name: pyalembic-aswf
Version: ${ALEMBIC_VERSION}
Summary: ASWF Alembic geometry-cache Python bindings
Requires-Python: ==3.9.*
Requires-Dist: numpy<2
EOF
cat > "${DIST_INFO}/WHEEL" <<'EOF'
Wheel-Version: 1.0
Generator: build_pyalembic_manylinux.sh
Root-Is-Purelib: false
Tag: cp39-cp39-linux_x86_64
EOF

"${PYTHON_BIN}" -m wheel pack "${RAW_WHEEL_DIR}" --dest-dir "${BUILD_DIR}"
RAW_WHEEL="$(find "${BUILD_DIR}" -maxdepth 1 -name '*.whl' -print -quit)"
auditwheel repair "${RAW_WHEEL}" \
  --plat manylinux_2_28_x86_64 \
  --wheel-dir "${WHEELHOUSE}"

# Validate the artifact in a clean environment and read a real upstream test
# archive from the checked-out fork.
"${PYTHON_BIN}" -m venv "${WORK_DIR}/test-venv"
TEST_PYTHON="${WORK_DIR}/test-venv/bin/python"
"${TEST_PYTHON}" -m pip install --disable-pip-version-check \
  "numpy<2" "${WHEELHOUSE}"/*.whl
"${TEST_PYTHON}" "${ALEMBIC_SOURCE_DIR}/examples/read_alembic.py" \
  "${ALEMBIC_SOURCE_DIR}/lib/Alembic/AbcCoreOgawa/Tests/issue257.abc"

"${TEST_PYTHON}" - <<'PY'
import alembic
import imath
from alembic.Abc import GetLibraryVersion

print("PyAlembic:", GetLibraryVersion())
print("Alembic module:", alembic.__file__)
print("Imath module:", imath.__file__)
PY
