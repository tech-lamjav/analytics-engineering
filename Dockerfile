# Use Python 3.13 slim as base image
FROM python:3.13-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements file
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy dbt project
COPY dbt_nba/ ./dbt_nba/

# Create .dbt directory and copy profiles.yml from root
# The profiles.yml uses service account authentication via Application Default Credentials
# The service account will be configured at the Cloud Run Job level
RUN mkdir -p /app/.dbt
COPY profiles.yml /app/.dbt/profiles.yml

# Set dbt project directory and profiles directory
ENV DBT_PROJECT_DIR=/app/dbt_nba
ENV DBT_PROFILES_DIR=/app/.dbt

# Install dbt dependencies
RUN dbt deps --project-dir /app/dbt_nba --profiles-dir /app/.dbt

# Default command (can be overridden in Cloud Run Job)
# Use --target prod for production environment
CMD ["dbt", "run", "--project-dir", "/app/dbt_nba", "--profiles-dir", "/app/.dbt", "--target", "prod"]
