@_cdecl("main")
public func main() -> Never {
    let ctx = Board.initBoard()
    let serial = ctx.serial
    let timer  = ctx.timer

    let led13 = PIN(13)
    let led7 = PIN(7)
    led13.output()
    led7.output()

    let btnA = PIN(3)
    let btnB = PIN(4)
    let btnC = PIN(5)
    let btnD = PIN(6)

    btnA.inputPullup()
    btnB.inputPullup()
    btnC.inputPullup()
    btnD.inputPullup()

    var lastA = false
    var lastB = false
    var lastC = false
    var lastD = false

    serial.writeString("Ready\r\n")

    led7.on()

    while true {
        let a = btnA.isLow()
        let b = btnB.isLow()
        let c = btnC.isLow()
        let d = btnD.isLow()

        // borda de subida do "pressed"
        if !lastA && a { serial.writeString("A\r\n"); led13.toggle(); led7.toggle() }
        if !lastB && b { serial.writeString("B\r\n"); led13.toggle(); led7.toggle() }
        if !lastC && c { serial.writeString("C\r\n"); led13.toggle(); led7.toggle() }
        if !lastD && d { serial.writeString("D\r\n"); led13.toggle(); led7.toggle() }

        lastA = a; lastB = b; lastC = c; lastD = d

        timer.sleepFor(ms: 10)
    }
}