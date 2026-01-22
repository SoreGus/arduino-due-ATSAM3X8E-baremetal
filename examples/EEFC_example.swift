// main.swift — EEFC simple KV storage test
//
// Pins:
//  D5  -> save current time to key "time"
//  D6  -> load & print "time"
//  D7  -> append "Hello " to key "hello"
//  D8  -> load & print "hello"
//  D9  -> remove key "hello"
//  D10 -> remove key "time"
//  D11 -> remove ALL keys
//

@inline(__always)
func decU32(_ value: U32) -> String {
    var v = value
    var buf = [UInt8](repeating: 0, count: 10)
    var i = 0

    repeat {
        buf[i] = UInt8(v % 10) + 48
        v /= 10
        i += 1
    } while v > 0

    var s = ""
    while i > 0 {
        i -= 1
        s.append(Character(UnicodeScalar(buf[i])))
    }
    return s
}

@_cdecl("main")
public func main() -> Never {
    let ctx = Board.initBoard()
    let serial = ctx.serial
    let timer  = ctx.timer

    let store = EEFCStorage()

    // ---------------- GPIO ----------------

    let bSaveTime   = PIN(5)
    let bLoadTime   = PIN(6)
    let bSaveHello  = PIN(7)
    let bLoadHello  = PIN(8)
    let bClearHello = PIN(9)
    let bClearTime  = PIN(10)
    let bClearAll   = PIN(11)

    bSaveTime.inputPullup()
    bLoadTime.inputPullup()
    bSaveHello.inputPullup()
    bLoadHello.inputPullup()
    bClearHello.inputPullup()
    bClearTime.inputPullup()
    bClearAll.inputPullup()

    var last5  = false
    var last6  = false
    var last7  = false
    var last8  = false
    var last9  = false
    var last10 = false
    var last11 = false

    serial.writeString("EEFC KV test ready\r\n")

    // ---------------- Loop ----------------

    while true {
        let p5  = bSaveTime.isLow()
        let p6  = bLoadTime.isLow()
        let p7  = bSaveHello.isLow()
        let p8  = bLoadHello.isLow()
        let p9  = bClearHello.isLow()
        let p10 = bClearTime.isLow()
        let p11 = bClearAll.isLow()

        // D5 — save time
        if !last5 && p5 {
            let t = timer.millis()
            if let err = store.save(key: "time", value: t) {
                serial.writeString("SAVE time FAIL: ")
                serial.writeString(err.name)
                serial.writeString("\r\n")
            } else {
                serial.writeString("SAVE time = ")
                serial.writeString(decU32(t))
                serial.writeString("\r\n")
            }
        }

        // D6 — load time
        if !last6 && p6 {
            switch store.loadU32(key: "time") {
            case .success(let t):
                serial.writeString("LOAD time = ")
                serial.writeString(decU32(t))
                serial.writeString("\r\n")
            case .failure(let e):
                serial.writeString("LOAD time FAIL: ")
                serial.writeString(e.name)
                serial.writeString("\r\n")
            }
        }

        // D7 — append "Hello "
        if !last7 && p7 {
            var current = ""
            if case .success(let s) = store.loadString(key: "hello") {
                current = s
            }
            current += "Hello "

            if let err = store.save(key: "hello", value: current) {
                serial.writeString("SAVE hello FAIL: ")
                serial.writeString(err.name)
                serial.writeString("\r\n")
            } else {
                serial.writeString("SAVE hello OK\r\n")
            }
        }

        // D8 — load hello
        if !last8 && p8 {
            switch store.loadString(key: "hello") {
            case .success(let s):
                serial.writeString("LOAD hello = ")
                serial.writeString(s)
                serial.writeString("\r\n")
            case .failure(let e):
                serial.writeString("LOAD hello FAIL: ")
                serial.writeString(e.name)
                serial.writeString("\r\n")
            }
        }

        // D9 — clear hello
        if !last9 && p9 {
            if let err = store.remove(key: "hello") {
                serial.writeString("REMOVE hello FAIL: ")
                serial.writeString(err.name)
                serial.writeString("\r\n")
            } else {
                serial.writeString("REMOVE hello OK\r\n")
            }
        }

        // D10 — clear time
        if !last10 && p10 {
            if let err = store.remove(key: "time") {
                serial.writeString("REMOVE time FAIL: ")
                serial.writeString(err.name)
                serial.writeString("\r\n")
            } else {
                serial.writeString("REMOVE time OK\r\n")
            }
        }

        // D11 — clear all
        if !last11 && p11 {
            if let err = store.removeAll() {
                serial.writeString("REMOVE ALL FAIL: ")
                serial.writeString(err.name)
                serial.writeString("\r\n")
            } else {
                serial.writeString("REMOVE ALL OK\r\n")
            }
        }

        last5  = p5
        last6  = p6
        last7  = p7
        last8  = p8
        last9  = p9
        last10 = p10
        last11 = p11

        timer.sleepFor(ms: 40)
    }
}