# Build environment for the data pipeline.
#
# The pipeline needs numpy/pandas/pyarrow/trimesh/fast-simplification/cloud-volume, and those
# only have wheels for released Python versions — on a host with a very new or externally
# managed interpreter the install cannot succeed. Pinning it here makes the download
# reproducible on any machine that has Docker.
#
#   docker build -t godot-fly-data .
#   docker run --rm -v "$PWD/data:/app/data" godot-fly-data
#
# ./download_data.sh does both for you.
FROM python:3.11-slim

# curl for the flybody download; the rest are build deps for the few packages
# that ship an sdist instead of a wheel.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY tools/requirements.txt tools/requirements.txt
RUN pip install --no-cache-dir -r tools/requirements.txt

COPY tools/ tools/

# Writable HOME for cloud-volume's cache/config, so the container can run as any uid.
ENV HOME=/tmp PYTHONUNBUFFERED=1

# data/ is a bind mount: raw downloads are cached in data/raw and outputs land in data/.
VOLUME /app/data

ENTRYPOINT ["bash", "tools/pipeline.sh"]
