$version: "1.0"

namespace org.example.hi

@aws.protocols#restJson1
service Hi {
    version: "1.0.0",
    resources: [Greeting]
}

resource Greeting {
    operations: [HelloWorld]
}

structure HelloInput {}

structure HelloOutput {}

@http(method: "POST", uri: "/hello")
operation HelloWorld {
    input: HelloInput,
    output: HelloOutput,
}

