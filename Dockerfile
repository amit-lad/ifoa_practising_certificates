FROM rocker/r-ver:4.4.3

ENV TZ=Europe/London

RUN apt-get update && apt-get install -y --no-install-recommends \
    pandoc \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libpng-dev \
    libjpeg-dev \
    libtiff5-dev \
    zlib1g-dev \
    libcairo2-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY renv.lock ./
COPY renv/ ./renv/
COPY .Rprofile ./

RUN R -e 'install.packages("renv", repos="https://cloud.r-project.org"); renv::restore()'

COPY . .

RUN mkdir -p data_raw database _site

CMD ["Rscript", "build_dashboard_github_actions.R"]
