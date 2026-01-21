// MMIO.swift — Shared low-level MMIO helpers for Embedded Swift (Arduino Due)
//
// Regras do projeto:
// - Toda ponte @_silgen_name(...) fica aqui.
// - Helpers são genéricos (read/write/set/clear), sem lógica de periférico.

public typealias U32 = UInt32
public typealias U16 = UInt16
public typealias U8  = UInt8

// MARK: - asm/C shims (support.c)

@_silgen_name("bm_nop")
public func bm_nop() -> Void

@_silgen_name("bm_enable_irq")
public func bm_enable_irq() -> Void

@_silgen_name("bm_disable_irq")
public func bm_disable_irq() -> Void

@_silgen_name("bm_dsb")
public func bm_dsb() -> Void

@_silgen_name("bm_isb")
public func bm_isb() -> Void

// ✅ Volatile MMIO shims (support.c)
// Esses garantem que o acesso não será otimizado/“cacheado” pelo compilador.
@_silgen_name("bm_read32")
public func bm_read32(_ addr: U32) -> U32

@_silgen_name("bm_write32")
public func bm_write32(_ addr: U32, _ value: U32) -> Void

// MARK: - MMIO primitives (volatile-safe)

// Mantém o helper de ponteiro só pra casos muito específicos,
// mas NÃO use para read/write normal (não é volatile).
@inline(__always)
public func reg32(_ addr: U32) -> UnsafeMutablePointer<U32> {
    UnsafeMutablePointer<U32>(bitPattern: UInt(addr))!
}

@inline(__always)
public func read32(_ addr: U32) -> U32 {
    bm_read32(addr)
}

@inline(__always)
public func write32(_ addr: U32, _ value: U32) {
    bm_write32(addr, value)
}

// Útil quando você precisa garantir ordem de escrita de registradores
// antes de prosseguir (alguns periféricos precisam disso).
public enum MMIOBarrier {
    case none
    case dsb        // Data Synchronization Barrier
    case dsb_isb    // DSB + ISB (mais forte)
}

@inline(__always)
public func write32(_ addr: U32, _ value: U32, barrier: MMIOBarrier) {
    bm_write32(addr, value)
    switch barrier {
    case .none: break
    case .dsb: bm_dsb()
    case .dsb_isb:
        bm_dsb()
        bm_isb()
    }
}

@inline(__always)
public func setBits32(_ addr: U32, _ mask: U32) {
    bm_write32(addr, bm_read32(addr) | mask)
}

@inline(__always)
public func clearBits32(_ addr: U32, _ mask: U32) {
    bm_write32(addr, bm_read32(addr) & ~mask)
}

@inline(__always)
public func writeMasked32(_ addr: U32, _ mask: U32, _ value: U32) {
    // Replace only bits in mask with (value & mask)
    let cur = bm_read32(addr)
    bm_write32(addr, (cur & ~mask) | (value & mask))
}

// MARK: - Read-modify-write com seção crítica (quando precisar)

// Em muitos MCUs, alguns registradores têm SET/CLEAR dedicados (melhor),
// mas quando você é obrigado a fazer RMW no mesmo endereço,
// isso evita race com IRQ (não resolve concorrência com DMA/segundo core).
@inline(__always)
public func withIRQLocked<T>(_ body: () -> T) -> T {
    bm_disable_irq()
    let result = body()
    bm_enable_irq()
    return result
}

@inline(__always)
public func setBits32_locked(_ addr: U32, _ mask: U32) {
    withIRQLocked {
        bm_write32(addr, bm_read32(addr) | mask)
    }
}

@inline(__always)
public func clearBits32_locked(_ addr: U32, _ mask: U32) {
    withIRQLocked {
        bm_write32(addr, bm_read32(addr) & ~mask)
    }
}

@inline(__always)
public func writeMasked32_locked(_ addr: U32, _ mask: U32, _ value: U32) {
    withIRQLocked {
        let cur = bm_read32(addr)
        bm_write32(addr, (cur & ~mask) | (value & mask))
    }
}

// MARK: - Simple spin helpers

@inline(__always)
public func spin(_ cycles: U32) {
    if cycles == 0 { return }
    var n = cycles
    while n > 0 {
        bm_nop()
        n &-= 1
    }
}

// Espera uma condição até timeout. Bom pra flags de periférico.
// Dica: se for flag de registrador, use read32 dentro do cond.
@inline(__always)
public func waitUntil(_ timeout: U32, _ cond: () -> Bool) -> Bool {
    var t = timeout
    while t > 0 {
        if cond() { return true }
        bm_nop()      // reduz agressividade do loop e ajuda timing
        t &-= 1
    }
    return false
}

// Espera um bit ficar 1 (ou 0) em um registrador.
@inline(__always)
public func waitBitSet32(_ addr: U32, _ mask: U32, timeout: U32) -> Bool {
    waitUntil(timeout) { (read32(addr) & mask) != 0 }
}

@inline(__always)
public func waitBitClear32(_ addr: U32, _ mask: U32, timeout: U32) -> Bool {
    waitUntil(timeout) { (read32(addr) & mask) == 0 }
}