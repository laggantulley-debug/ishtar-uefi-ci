/*
 * Force-included into every XNU translation unit when building with stock
 * (non-Apple) clang. Apple's clang has builtins that describe the pointer/data
 * layout of a type for kalloc_type; upstream clang lacks them, so every type
 * is conservatively described as "mixed pointers and data".
 */
#ifndef XNU_CLANG_COMPAT_H
#define XNU_CLANG_COMPAT_H
#if !defined(ASSEMBLER) && !defined(__ASSEMBLER__)
#if !__has_builtin(__builtin_xnu_type_signature)
#define XNU_NO_TYPE_BUILTINS                     1
#define __builtin_xnu_type_signature(type)       "12"
#define __builtin_xnu_type_summary(type)         ((1U << 1) | (1U << 2))
#ifdef __cplusplus
#define __builtin_xnu_types_compatible(a, b)     __is_same(a, b)
#else
#define __builtin_xnu_types_compatible(a, b)     __builtin_types_compatible_p(a, b)
#endif
#else
/* Apple's clang (macOS hosts) has the builtins; OSData.h still tests the macro */
#define XNU_NO_TYPE_BUILTINS                     0
#endif
#endif
#endif

/*
 * __builtin_clzg / __builtin_ctzg（带 fallback 的 count-leading/trailing-zeros）
 * 是 clang-19 才有的；Ubuntu 24.04 的 clang-18 不认识，osfmk/kern/bits.h 却在
 * 每个 uint64_t 上用它，于是报 "use of unknown builtin"。
 * 这里用 clzll/ctzll 给出等价实现（入参是 uint64_t，语义一致）。
 */
#if !__has_builtin(__builtin_clzg)
static inline int __xnu_clzg_u64(uint64_t x, int fallback) { return x ? __builtin_clzll(x) : fallback; }
#define __builtin_clzg(x, fallback)     __xnu_clzg_u64((uint64_t)(x), (int)(fallback))
#endif
#if !__has_builtin(__builtin_ctzg)
static inline int __xnu_ctzg_u64(uint64_t x, int fallback) { return x ? __builtin_ctzll(x) : fallback; }
#define __builtin_ctzg(x, fallback)     __xnu_ctzg_u64((uint64_t)(x), (int)(fallback))
#endif
