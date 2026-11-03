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
 *
 * 注意：这个头文件也会被 mig 解析（生成 kextd_mach.h 等），而 mig 只认宏、
 * 不接受函数定义——所以这里必须用纯宏，不能写 static inline。
 * bits.h 的调用点都是普通变量，重复求值没有副作用。
 */
#if !__has_builtin(__builtin_clzg)
#define __builtin_clzg(x, fallback) \
	((x) ? (int)__builtin_clzll((unsigned long long)(x)) : (int)(fallback))
#endif
#if !__has_builtin(__builtin_ctzg)
#define __builtin_ctzg(x, fallback) \
	((x) ? (int)__builtin_ctzll((unsigned long long)(x)) : (int)(fallback))
#endif
