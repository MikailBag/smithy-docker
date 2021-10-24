# syntax=docker/dockerfile:1.3.0
FROM docker.io/library/ubuntu:focal as fetch-base
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates
WORKDIR /

FROM fetch-base as fetch-core
ARG CORE_REV="306fa1a66ce7cb12f057cd6c856c55e1911df1de"
RUN git clone https://github.com/awslabs/smithy src
WORKDIR /src
RUN git checkout ${CORE_REV}
RUN rm -rf .git

FROM fetch-base as fetch-rs
ARG RUST_REV="edcc7c19589bac39edcd26c287b2c95b41996a50"
RUN git clone https://github.com/awslabs/smithy-rs src
WORKDIR /src
RUN git checkout ${RUST_REV}
RUN rm -rf .git

FROM fetch-base as fetch-ts
ARG TYPESCRIPT_REV="2d95be8407f6f39c925949da1f99326cef3b602d"
RUN git clone https://github.com/awslabs/smithy-typescript src
WORKDIR /src
RUN git checkout ${TYPESCRIPT_REV}
RUN rm -rf .git

FROM docker.io/library/gradle:7-jdk11 as build-core
WORKDIR /work
COPY --from=fetch-core /src /work
RUN gradle --no-daemon --console plain assemble


FROM scratch as output-core
ARG CORE_VERSION='1.12.0'
COPY --from=build-core /work/smithy-cli/build/libs/smithy-cli-${CORE_VERSION}.jar /out/cli.jar
COPY --from=build-core /work/smithy-codegen-core/build/libs/smithy-codegen-core-${CORE_VERSION}.jar /out/codegen-core.jar
COPY --from=build-core /work/smithy-model/build/libs/smithy-model-${CORE_VERSION}.jar /out/model.jar
COPY --from=build-core /work/smithy-build/build/libs/smithy-build-${CORE_VERSION}.jar /out/build.jar
COPY --from=build-core /work/smithy-utils/build/libs/smithy-utils-${CORE_VERSION}.jar /out/utils.jar
COPY --from=build-core /work/smithy-aws-traits/build/libs/smithy-aws-traits-${CORE_VERSION}.jar /out/aws-traits.jar
COPY --from=build-core /work/smithy-protocol-test-traits/build/libs/smithy-protocol-test-traits-${CORE_VERSION}.jar /out/protocol-test-traits.jar
COPY --from=build-core /work/smithy-aws-protocol-tests/build/libs/smithy-aws-protocol-tests-${CORE_VERSION}.jar /out/protocol-tests.jar
COPY --from=build-core /work/smithy-validation-model/build/libs/smithy-validation-model-${CORE_VERSION}.jar /out/validation.jar
COPY --from=build-core /work/smithy-openapi/build/libs/smithy-openapi-${CORE_VERSION}.jar /out/openapi.jar
COPY --from=build-core /work/smithy-jsonschema/build/libs/smithy-jsonschema-${CORE_VERSION}.jar /out/jsonschema.jar

FROM docker.io/library/gradle:7-jdk11 as build-ts
WORKDIR /work
COPY --from=fetch-ts /src /work
RUN gradle --no-daemon --console plain assemble

FROM scratch as output-ts
ARG TS_VERSION='0.6.0'
COPY --from=build-ts /work/smithy-typescript-codegen/build/libs/smithy-typescript-codegen-${TS_VERSION}.jar /out/ts.jar

FROM docker.io/library/gradle:6-jdk11 as build-rs
COPY --from=fetch-rs /src /work
WORKDIR /work/codegen
RUN gradle --no-daemon --console plain assemble 
WORKDIR /work/rust-runtime
RUN gradle --no-daemon --console plain assemble

FROM scratch as output-rs
ARG RS_CODEGEN_VERSION='0.1.0'
ARG RS_RUNTIME_VERSION='0.0.3'
COPY --from=build-rs /work/codegen/build/libs/codegen-${RS_CODEGEN_VERSION}.jar /out/rust.jar
COPY --from=build-rs /work/rust-runtime/build/libs/rust-runtime-${RS_RUNTIME_VERSION}.jar /out/rust-rt.jar

FROM docker.io/library/gradle:7-jdk11 as build-dummy
COPY /dummy-proj /work
WORKDIR /work
RUN gradle --no-daemon --console plain shadowJar
RUN mkdir /out
RUN cp /work/lib/build/libs/lib-all.jar /out/dummy.jar

FROM scratch as jars
COPY --from=output-core /out /jars
COPY --from=output-ts /out /jars-ignored
COPY --from=output-rs /out /jars
COPY --from=build-dummy /out /jars

FROM gcr.io/distroless/java:11
COPY --from=fetch-rs /src/rust-runtime /opt/rust/runtime
COPY --from=jars /jars /jars
VOLUME [ "/input" ]
VOLUME [ "/output" ]
ENTRYPOINT [ "java", "-cp", "/jars/*", \
    "software.amazon.smithy.cli.SmithyCli", \
    "build", "--discover", "--config", "/input/smithy-build.json", \
    "--output", "/output", "/input/model"]

