FROM nvidia/cuda:12.8.1-cudnn-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive

# 공식 Ubuntu 저장소 사용: APT 목록 갱신과 설치를 같은 레이어에서 실행
RUN apt-get update && \
    apt-get install -y software-properties-common ca-certificates gnupg && \
    add-apt-repository -y ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y build-essential git ffmpeg libsm6 libxext6 libgl1 curl \
        python3.12 python3.12-dev python3.12-venv && \
    rm -rf /var/lib/apt/lists/*

RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python3.12

RUN ln -sf /usr/bin/python3.12 /usr/bin/python
RUN ln -sf /usr/bin/python3.12 /usr/bin/python3

RUN python -m pip install --upgrade pip

# PyTorch CPU 버전 설치
RUN pip install --no-cache-dir torch==2.9.1 torchvision==0.24.1 --index-url https://download.pytorch.org/whl/cu128

# 추가로 필요할 수 있는 라이브러리
RUN pip install --no-cache-dir opencv-python==5.0.0.93
RUN pip install --no-cache-dir numpy==2.4.4
RUN pip install --no-cache-dir pillow==12.2.0
RUN pip install --no-cache-dir pandas==2.3.1
RUN pip install --no-cache-dir matplotlib==3.11.1
RUN pip install --no-cache-dir tqdm==4.69.0
RUN pip install --no-cache-dir scikit-learn==1.9.0
RUN pip install --no-cache-dir timm==1.0.28
RUN pip install --no-cache-dir diffusers==0.39.0
RUN pip install --no-cache-dir accelerate==1.14.0
RUN pip install --no-cache-dir clearml==2.1.12
RUN pip install --no-cache-dir albumentations==2.0.8

RUN mkdir /app
WORKDIR /app
