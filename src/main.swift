// main.swift — Blink D13 + D2 + UART using Board

var timer: Timer?

@_cdecl("main")
public func main() -> Never {
    let ctx = Board.initBoard()

    let serial = ctx.serial
    timer  = ctx.timer

    let led13 = PIN(13)
    let led2  = PIN(32)

    led13.output()
    led2.output()

    while true {

        sequenceBlink(pin: led13, blinks: 5)
        sequenceBlink(pin: led2, blinks: 5)
    }
}

public func sequenceBlink(pin: PIN, blinks: Int) {
    guard let timer else {
        return
    }
    for _ in 0...blinks {
        pin.on()
        timer.sleepFor(ms: 40)
        pin.off()
        timer.sleepFor(ms: 40)
    }
}