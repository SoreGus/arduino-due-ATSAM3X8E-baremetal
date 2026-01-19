// main.swift — Blink D13 + D2 + UART using Board

@_cdecl("main")
public func main() -> Never {
    let ctx = Board.initBoard()

    let serial = ctx.serial
    let timer  = ctx.timer

    let led13 = PIN(13) // built-in LED "L"
    let led2  = PIN(32)  // your external transistor LED

    led13.output()
    led2.output()

    while true {
        led13.on()
        led2.on()
        serial.writeString("ON\r\n")
        timer.sleepFor(ms: 1000)

        led13.off()
        led2.off()
        serial.writeString("OFF\r\n")
        timer.sleepFor(ms: 1000)
    }
}