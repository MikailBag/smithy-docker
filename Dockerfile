# syntax=docker/dockerfile:1.3.0
FROM docker.io/library/ubuntu:focal as fetch-base
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates
WORKDIR /

FROM fetch-base as fetch-core
ARG CORE_REV="5c293d8c7ed8f4a1817c808cc6e530e7f7fd57d3"
RUN git clone https://github.com/awslabs/smithy src
WORKDIR /src
RUN git checkout ${CORE_REV}
RUN rm -rf .git

FROM fetch-base as fetch-rs
ARG RUST_REV="66db8dac60aa301fca95e0f6c63684da4a50a342"
RUN git clone https://github.com/awslabs/smithy-rs src
WORKDIR /src
RUN git checkout ${RUST_REV}
RUN rm -rf .git

FROM fetch-base as fetch-ts
ARG TYPESCRIPT_REV="c6f19cd7536531781a42480e3abb8b8eb8e097c9"
RUN git clone https://github.com/awslabs/smithy-typescript src
WORKDIR /src
RUN git checkout ${TYPESCRIPT_REV}
RUN rm -rf .git

FROM docker.io/library/gradle:7-jdk11 as build-core
WORKDIR /work
COPY --from=fetch-core /src /work
RUN gradle --no-daemon --console plain assemble
RUN mkdir /out
ARG CORE_VERSION='1.11.0'
RUN cp /work/smithy-cli/build/libs/smithy-cli-${CORE_VERSION}.jar /out/cli.jar
RUN cp /work/smithy-codegen-core/build/libs/smithy-codegen-core-${CORE_VERSION}.jar /out/codegen-core.jar
RUN cp /work/smithy-model/build/libs/smithy-model-${CORE_VERSION}.jar /out/model.jar
RUN cp /work/smithy-build/build/libs/smithy-build-${CORE_VERSION}.jar /out/build.jar
RUN cp /work/smithy-utils/build/libs/smithy-utils-${CORE_VERSION}.jar /out/utils.jar
RUN cp /work/smithy-aws-traits/build/libs/smithy-aws-traits-${CORE_VERSION}.jar /out/aws-traits.jar
RUN cp /work/smithy-protocol-test-traits/build/libs/smithy-protocol-test-traits-${CORE_VERSION}.jar /out/protocol-test-traits.jar
RUN cp /work/smithy-aws-protocol-tests/build/libs/smithy-aws-protocol-tests-${CORE_VERSION}.jar /out/protocol-tests.jar
RUN cp /work/smithy-validation-model/build/libs/smithy-validation-model-${CORE_VERSION}.jar /out/validation.jar
RUN cp /work/smithy-openapi/build/libs/smithy-openapi-${CORE_VERSION}.jar /out/openapi.jar
RUN cp /work/smithy-jsonschema/build/libs/smithy-jsonschema-${CORE_VERSION}.jar /out/jsonschema.jar

FROM docker.io/library/gradle:7-jdk11 as build-ts
WORKDIR /work
COPY --from=fetch-ts /src /work
RUN gradle --no-daemon --console plain assemble
RUN mkdir /out
ARG TS_VERSION='0.6.0'
RUN cp /work/smithy-typescript-codegen/build/libs/smithy-typescript-codegen-${TS_VERSION}.jar /out/ts.jar

FROM docker.io/library/gradle:6-jdk11 as build-rs
WORKDIR /work
COPY --from=fetch-rs /src /work
RUN gradle --no-daemon --console plain codegen:assemble rust-runtime:assemble
RUN mkdir /out
ARG RS_CODEGEN_VERSION='0.1.0'
ARG RS_RUNTIME_VERSION='0.0.3'
RUN cp /work/codegen/build/libs/codegen-${RS_CODEGEN_VERSION}.jar /out/rust.jar
RUN cp /work/rust-runtime/build/libs/rust-runtime-${RS_RUNTIME_VERSION}.jar /out/rust-rt.jar

FROM docker.io/library/gradle:7-jdk11 as build-dummy
COPY /dummy-proj /work
WORKDIR /work
RUN gradle --no-daemon --console plain shadowJar
RUN mkdir /out
RUN cp /work/lib/build/libs/lib-all.jar /out/dummy.jar

FROM scratch as jars
COPY --from=build-core /out /jars
COPY --from=build-ts /out /jars-ignored
COPY --from=build-rs /out /jars
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

