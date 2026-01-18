// Clock.swift — ATSAM3X8E clock init to 84 MHz (Arduino Due)
// Returns Bool and uses timeouts to avoid "silent hang".

private let PMC_BASE: U32 = 0x400E_0600

private let CKGR_MOR:  U32 = PMC_BASE + 0x0020
private let CKGR_PLLAR: U32 = PMC_BASE + 0x0028
private let PMC_MCKR:   U32 = PMC_BASE + 0x0030
private let PMC_SR:     U32 = PMC_BASE + 0x0068

// EEFC (Flash controller) — set wait states BEFORE speeding up clock
private let EEFC0_BASE: U32 = 0x400E_0A00
private let EEFC1_BASE: U32 = 0x400E_0C00
private let EEFC_FMR:   U32 = 0x0000

private let SR_MOSCXTS: U32 = U32(1) << 0
private let SR_LOCKA:   U32 = U32(1) << 1
private let SR_MCKRDY:  U32 = U32(1) << 3

private let MOR_MOSCXTEN: U32 = U32(1) << 0
private let MOR_MOSCXTST_SHIFT: U32 = 8
private let MOR_MOSCXTST_MASK: U32 = 0xFF << MOR_MOSCXTST_SHIFT
private let MOR_MOSCSEL: U32 = U32(1) << 24
private let MOR_KEY: U32 = 0x37 << 16

private let MCKR_CSS_MASK: U32 = 0x3
private let MCKR_CSS_PLLA: U32 = 2

private let MCKR_PRES_MASK: U32 = 0x7 << 4
private let MCKR_PRES_1: U32 = 0 << 4

@inline(__always)
private func waitSR(_ mask: U32, timeout: U32 = 5_000_000) -> Bool {
    var t = timeout
    while t != 0 {
        if (read32(PMC_SR) & mask) != 0 { return true }
        bm_nop()
        t &-= 1
    }
    return false
}

@inline(__always)
private func setFlashWaitStates(_ fws: U32) {
    // EEFC_FMR: FWS field typically at bits [8..11]
    // We'll do a conservative mask 0xF<<8.
    let mask: U32 = 0xF << 8
    let v: U32 = (fws & 0xF) << 8

    let fmr0 = (read32(EEFC0_BASE + EEFC_FMR) & ~mask) | v
    let fmr1 = (read32(EEFC1_BASE + EEFC_FMR) & ~mask) | v

    write32(EEFC0_BASE + EEFC_FMR, fmr0)
    write32(EEFC1_BASE + EEFC_FMR, fmr1)

    // ensure it takes effect
    bm_dsb()
    bm_isb()
}

public enum DueClock {
    // ✅ agora retorna Bool (não trava mais silencioso)
    public static func init84MHz() -> Bool {
        // 0) Flash wait states BEFORE switching to fast clock.
        // Arduino Due overclock snippets often use FWS(4) for high clocks.  [oai_citation:1‡Arduino Forum](https://forum.arduino.cc/t/how-to-clock-the-due-cpu-clock-at-80-or-96-mhz/478488/8)
        setFlashWaitStates(4)

        // 1) Enable main crystal oscillator
        var mor = read32(CKGR_MOR)
        mor &= ~MOR_MOSCXTST_MASK
        mor |= MOR_KEY | MOR_MOSCXTEN | (0xFF << MOR_MOSCXTST_SHIFT)
        write32(CKGR_MOR, mor)
        if !waitSR(SR_MOSCXTS) { return false }

        // 2) Select crystal as MAINCK
        mor = read32(CKGR_MOR)
        mor |= MOR_KEY | MOR_MOSCSEL
        write32(CKGR_MOR, mor)
        if !waitSR(SR_MOSCXTS) { return false }

        // 3) PLLA: 12MHz * (MULA+1)/DIVA = 84MHz => MULA=6, DIVA=1
        let diva: U32 = 1
        let mula: U32 = 6
        let pllaCount: U32 = 0x3F
        let pll = (U32(1) << 29) | (mula << 16) | (pllaCount << 8) | diva
        write32(CKGR_PLLAR, pll)
        if !waitSR(SR_LOCKA) { return false }

        // 4) Prescaler first
        var mckr = read32(PMC_MCKR)
        mckr &= ~MCKR_PRES_MASK
        mckr |= MCKR_PRES_1
        write32(PMC_MCKR, mckr)
        if !waitSR(SR_MCKRDY) { return false }

        // 5) Switch MCK to PLLA
        mckr = read32(PMC_MCKR)
        mckr &= ~MCKR_CSS_MASK
        mckr |= MCKR_CSS_PLLA
        write32(PMC_MCKR, mckr)
        if !waitSR(SR_MCKRDY) { return false }

        bm_dsb()
        bm_isb()
        return true
    }
}