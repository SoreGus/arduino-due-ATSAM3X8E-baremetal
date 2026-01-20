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

// MARK: - MMIO primitives

@inline(__always)
public func reg32(_ addr: U32) -> UnsafeMutablePointer<U32> {
    UnsafeMutablePointer<U32>(bitPattern: UInt(addr))!
}

@inline(__always)
public func write32(_ addr: U32, _ value: U32) {
    reg32(addr).pointee = value
}

@inline(__always)
public func read32(_ addr: U32) -> U32 {
    reg32(addr).pointee
}

@inline(__always)
public func setBits32(_ addr: U32, _ mask: U32) {
    write32(addr, read32(addr) | mask)
}

@inline(__always)
public func clearBits32(_ addr: U32, _ mask: U32) {
    write32(addr, read32(addr) & ~mask)
}

@inline(__always)
public func writeMasked32(_ addr: U32, _ mask: U32, _ value: U32) {
    // Replace only bits in mask with (value & mask)
    let cur = read32(addr)
    write32(addr, (cur & ~mask) | (value & mask))
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

@inline(__always)
public func waitUntil(_ timeout: U32, _ cond: () -> Bool) -> Bool {
    // busy-wait up to "timeout" iterations
    var t = timeout
    while t > 0 {
        if cond() { return true }
        t &-= 1
    }
    return false
}