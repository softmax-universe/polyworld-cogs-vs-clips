FROM ubuntu:24.04 AS compiler
RUN apt-get update && apt-get install -y --no-install-recommends gcc g++ git curl ca-certificates xz-utils python3 libopenblas-dev && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://github.com/nim-lang/nightlies/releases/download/2026-04-24-version-2-2-bfeb3146d1638b39f69007a4ae5a23e23ae4e5ef/nim-2.2.10-linux_x64.tar.xz | tar xJ -C /opt
ENV PATH=/opt/nim-2.2.10/bin:$PATH
WORKDIR /src/cvc
COPY dependencies.lock dependencies.lock
COPY tools/setup_dependencies.py tools/setup_dependencies.py
ARG POLYWORLD_REVISION
RUN test -n "$POLYWORLD_REVISION" && POLYWORLD_REVISION="$POLYWORLD_REVISION" python3 tools/setup_dependencies.py
ENV POLYWORLD_DEPS=/src/cvc/.deps
COPY config.nims config.nims
COPY src src
COPY data/maps data/maps
COPY data/policies data/policies
COPY training/fourscore/safa_candidate.json training/fourscore/safa_candidate.json
COPY players players
ARG COOPERATIVE=0
RUN case "$COOPERATIVE" in 0) mode= ;; 1) mode=-d:cooperative ;; *) exit 1 ;; esac && nim c $mode -d:release -d:headless -d:coworld -d:tensorBlas --nimcache:/tmp/nimcache -o:/out/game src/cvc.nim
FROM emscripten/emsdk:4.0.15 AS viewer
COPY --from=compiler /opt/nim-2.2.10 /opt/nim-2.2.10
ENV PATH=/opt/nim-2.2.10/bin:$PATH
ENV POLYWORLD_DEPS=/src/cvc/.deps
WORKDIR /src/cvc
COPY --from=compiler /src/cvc /src/cvc
COPY data data
COPY tools/build_browser.sh tools/browser.html tools/
ARG COOPERATIVE=0
RUN if [ "$COOPERATIVE" = 1 ]; then mode=cooperative; else mode=fourscore; fi && \
    ./tools/build_browser.sh "$mode" && \
    if [ "$mode" = cooperative ]; then mv out/browser-cooperative /viewer; else mv out/browser /viewer; fi
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends libcurl4t64 libopenblas0-pthread ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=compiler /out/game /usr/local/bin/cvc
COPY --from=viewer /viewer /app/viewer
ENV OPENBLAS_NUM_THREADS=1
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/cvc"]
