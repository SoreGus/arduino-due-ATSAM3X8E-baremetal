// Timer.swift — SysTick timer (Cortex-M3) for ATSAM3X8E (Arduino Due)
// Depends on MMIO.swift providing: U32, bm_nop(), write32(), read32().

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
    }

    @inline(__always)
    public func millis() -> U32 {
        bm_nop()
        return g_msTicks
    }

    public func sleep(ms: U32) {
        let start = millis()
        while (millis() &- start) < ms {
            bm_nop()
        }
    }
}