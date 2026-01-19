// main.swift

@_cdecl("main")
public func main() -> Never {
    let (_, serial, timer) = ATSAM3X8E.initBoard()
    let led = PIN(27)
    led.output()
    while true {
        timer.sleepFor(ms: 1000)
        serial.writeString("Hello\n")
        led.on()
        timer.sleepFor(ms: 1000)
        led.off()
    }
}