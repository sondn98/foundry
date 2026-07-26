FROM elyra/enterprise-gateway:3.2.3

USER root

# Pin kubernetes client version tương thích
RUN pip install --no-cache-dir --upgrade kubernetes==26.1.0

USER ${NB_UID}
