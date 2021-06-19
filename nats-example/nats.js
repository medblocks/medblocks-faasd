const { connect } = require("nats");

const textdecoder = new TextDecoder();

const main = async () => {
    const conn = await connect();
    const sub = conn.subscribe(">");

    const messageThread = async () => {
        for await (const m of sub) {
            console.log(`[${m.subject}]: ${textdecoder.decode(m.data)}`)
        }
    }
    messageThread()
}

console.log("running main")
main()