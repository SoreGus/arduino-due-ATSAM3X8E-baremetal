// Timer.swift — SysTick timer (Cortex-M3) for ATSAM3X8E (Arduino Due)
// Depends on MMIO.swift providing: U32, bm_nop(), bm_disable_irq(), bm_enable_irq(),
// write32(), read32(), bm_dsb(), bm_isb().

// MUST be global and single symbol.
public var g_msTicks: U32 = 0

@_cdecl("SysTick_Handler")
public func SysTick_Handler() {
    g_msTicks &+= 1
}

public final class Timer {
    private let cpuHz: U32

    public init(cpuHz: U32) {
        self.cpuHz = cpuHz
    }

    public func startTick1ms() {
        // stop
        write32(ATSAM3X8E.SYST_CSR, 0)

        // reload = cpuHz/1000 - 1
        let reload = (cpuHz / 1_000) &- 1
        write32(ATSAM3X8E.SYST_RVR, reload)
        write32(ATSAM3X8E.SYST_CVR, 0)

        // enable + tickint + cpu clock
        write32(
            ATSAM3X8E.SYST_CSR,
            ATSAM3X8E.SysTick.CSR_CLKSRC |
            ATSAM3X8E.SysTick.CSR_TICKINT |
            ATSAM3X8E.SysTick.CSR_ENABLE
        )

        bm_dsb()
        bm_isb()
    }

    @inline(__always)
    public func millis() -> U32 {
        // Stable snapshot: SysTick IRQ might update while reading.
        // Keep it minimal and deterministic.
        bm_disable_irq()
        let v = g_msTicks
        bm_enable_irq()
        return v
    }

    public func sleep(ms: U32) {
        let start = millis()
        while (millis() &- start) < ms {
            bm_nop()
        }
    }
}

extension Timer {
    @inline(__always)
    public func sleepUntil(_ deadline: U32) {
        // while now < deadline (safe with wrap-around)
        while ((millis() &- deadline) & 0x8000_0000) != 0 {
            bm_nop()
        }
    }

    @inline(__always)
    public func sleepFor(ms: U32) {
        let d = millis() &+ ms
        sleepUntil(d)
    }
}