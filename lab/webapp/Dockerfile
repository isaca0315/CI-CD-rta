FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends iproute2 iputils-ping curl \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir flask==3.1.*

WORKDIR /app
COPY app.py imds_mock.py entrypoint.sh ./
RUN chmod +x entrypoint.sh && echo 'FLAG{dockerfile_backdoor}' > /flag.txt

EXPOSE 8000
ENTRYPOINT ["./entrypoint.sh"]
