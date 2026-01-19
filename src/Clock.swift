// Clock.swift — ATSAM3X8E clock init to 84 MHz (Arduino Due)
// Returns Bool and uses timeouts to avoid "silent hang".

@inline(__always)
private func waitSR(_ mask: U32, timeout: U32 = 5_000_000) -> Bool {
    var t = timeout
    while t != 0 {
        if (read32(ATSAM3X8E.PMC.SR) & mask) != 0 { return true }
        bm_nop()
        t &-= 1
    }
    return false
}

@inline(__always)
private func setFlashWaitStates(_ fws: U32) {
    // EEFC_FMR: FWS field typically at bits [8..11]
    let mask = ATSAM3X8E.EEFC.FMR_FWS_MASK
    let v: U32 = (fws & 0xF) << ATSAM3X8E.EEFC.FMR_FWS_SHIFT

    let fmr0 = (read32(ATSAM3X8E.EEFC0_BASE + ATSAM3X8E.EEFC.FMR_OFFSET) & ~mask) | v
    let fmr1 = (read32(ATSAM3X8E.EEFC1_BASE + ATSAM3X8E.EEFC.FMR_OFFSET) & ~mask) | v

    write32(ATSAM3X8E.EEFC0_BASE + ATSAM3X8E.EEFC.FMR_OFFSET, fmr0)
    write32(ATSAM3X8E.EEFC1_BASE + ATSAM3X8E.EEFC.FMR_OFFSET, fmr1)

    bm_dsb()
    bm_isb()
}

public enum DueClock {
    // ✅ agora retorna Bool (não trava mais silencioso)
    public static func init84MHz() -> Bool {
        // 0) Flash wait states BEFORE switching to fast clock.
        setFlashWaitStates(4)

        // 1) Enable main crystal oscillator
        var mor = read32(ATSAM3X8E.PMC.CKGR_MOR)
        mor &= ~ATSAM3X8E.PMC.MOR_MOSCXTST_MASK
        mor |= ATSAM3X8E.PMC.MOR_KEY
        mor |= ATSAM3X8E.PMC.MOR_MOSCXTEN
        mor |= (0xFF << ATSAM3X8E.PMC.MOR_MOSCXTST_SHIFT)
        write32(ATSAM3X8E.PMC.CKGR_MOR, mor)
        if !waitSR(ATSAM3X8E.PMC.SR_MOSCXTS) { return false }

        // 2) Select crystal as MAINCK
        mor = read32(ATSAM3X8E.PMC.CKGR_MOR)
        mor |= ATSAM3X8E.PMC.MOR_KEY | ATSAM3X8E.PMC.MOR_MOSCSEL
        write32(ATSAM3X8E.PMC.CKGR_MOR, mor)
        if !waitSR(ATSAM3X8E.PMC.SR_MOSCXTS) { return false }

        // 3) PLLA: 12MHz * (MULA+1)/DIVA = 84MHz => MULA=6, DIVA=1
        let diva: U32 = 1
        let mula: U32 = 6
        let pllaCount: U32 = 0x3F
        let pll = (U32(1) << 29) | (mula << 16) | (pllaCount << 8) | diva
        write32(ATSAM3X8E.PMC.CKGR_PLLAR, pll)
        if !waitSR(ATSAM3X8E.PMC.SR_LOCKA) { return false }

        // 4) Prescaler first
        var mckr = read32(ATSAM3X8E.PMC.MCKR)
        mckr &= ~ATSAM3X8E.PMC.MCKR_PRES_MASK
        mckr |= ATSAM3X8E.PMC.MCKR_PRES_1
        write32(ATSAM3X8E.PMC.MCKR, mckr)
        if !waitSR(ATSAM3X8E.PMC.SR_MCKRDY) { return false }

        // 5) Switch MCK to PLLA
        mckr = read32(ATSAM3X8E.PMC.MCKR)
        mckr &= ~ATSAM3X8E.PMC.MCKR_CSS_MASK
        mckr |= ATSAM3X8E.PMC.MCKR_CSS_PLLA
        write32(ATSAM3X8E.PMC.MCKR, mckr)
        if !waitSR(ATSAM3X8E.PMC.SR_MCKRDY) { return false }

        bm_dsb()
        bm_isb()
        return true
    }
}