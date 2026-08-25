# Food Lens FastAPI + YOLOv3 CPU image
FROM python:3.10-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# OpenCV and PyTorch CPU inference runtime dependencies.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt ./
RUN pip install --upgrade pip \
    && pip install --extra-index-url https://download.pytorch.org/whl/cpu -r requirements.txt

# The model file is excluded by .dockerignore. Cloud Run downloads it from private Cloud Storage.
COPY . ./

RUN mkdir -p /app/uploads/food-images /app/uploads/ai-feedback

EXPOSE 8080

CMD ["sh", "-c", "python scripts/download_model.py && python -m uvicorn api.main:app --host 0.0.0.0 --port ${PORT:-8080}"]