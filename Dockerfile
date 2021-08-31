# syntax=docker/dockerfile:1.3.0
FROM ubuntu:focal as fetch-base
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates
WORKDIR /

FROM fetch-base as fetch-core
ARG CORE_REV="a9a46d2f9e5df611c5dbae52143cc165a2f3f4fc"
RUN git clone https://github.com/awslabs/smithy src
WORKDIR /src
RUN git checkout ${CORE_REV}
RUN rm -rf .git

FROM fetch-base as fetch-rs
ARG RUST_REV="130703dadf2f5366dccc402e4d2cd11db7b004ad"
RUN git clone https://github.com/awslabs/smithy-rs src
WORKDIR /src
RUN git checkout ${RUST_REV}
RUN rm -rf .git

FROM fetch-base as fetch-ts
ARG TYPESCRIPT_REV="adf914b2707163be2b48c161dd960d47d465f789"
RUN git clone https://github.com/awslabs/smithy-typescript src
WORKDIR /src
RUN git checkout ${TYPESCRIPT_REV}
RUN rm -rf .git

FROM gradle:6-jdk11 as build-core
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

FROM gradle:6-jdk11 as build-ts
WORKDIR /work
COPY --from=fetch-ts /src /work
RUN gradle --no-daemon --console plain assemble
RUN mkdir /out
ARG TS_VERSION='0.5.0'
RUN cp /work/smithy-typescript-codegen/build/libs/smithy-typescript-codegen-${TS_VERSION}.jar /out/ts.jar

FROM gradle:6-jdk11 as build-rs
WORKDIR /work
COPY --from=fetch-rs /src /work
RUN gradle --no-daemon --console plain assemble
RUN mkdir /out
ARG RS_CODEGEN_VERSION='0.1.0'
ARG RS_RUNTIME_VERSION='0.0.3'
RUN cp /work/codegen/build/libs/codegen-${RS_CODEGEN_VERSION}.jar /out/rust.jar
RUN cp /work/rust-runtime/build/libs/rust-runtime-${RS_RUNTIME_VERSION}.jar /out/rust-rt.jar

FROM gradle:7-jdk11 as build-dummy
COPY /dummy-proj /work
WORKDIR /work
RUN gradle --no-daemon --console plain shadowJar
RUN mkdir /out
RUN cp /work/lib/build/libs/lib-all.jar /out/dummy.jar

FROM scratch as jars
COPY --from=build-core /out /jars
# TODO
# COPY --from=build-ts /out /jars
COPY --from=build-rs /out /jars
COPY --from=build-dummy /out /jars

FROM ubuntu:focal
RUN apt-get update && apt-get install -y --no-install-recommends \
     default-jre
COPY --from=fetch-rs /src/rust-runtime /opt/rust/runtime
COPY --from=jars /jars /jars
VOLUME [ "/input" ]
VOLUME [ "/output" ]
ENTRYPOINT [ "java", "-cp", "/jars/*", \
    "software.amazon.smithy.cli.SmithyCli", \
    "build", "--discover", "--config", "/input/smithy-build.json", \
    "--output", "/output", "/input/model"]

