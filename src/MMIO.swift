// MMIO.swift — Shared low-level MMIO helpers for Embedded Swift (Arduino Due)

public typealias U32 = UInt32

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