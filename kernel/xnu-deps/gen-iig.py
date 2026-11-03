#!/usr/bin/env python3
"""
Minimal stand-in for Apple's closed-source `iig` (DriverKit interface generator).

It reads the interface definition (.iig, which is upstream source in the kernel tree) and
emits the two artefacts the kernel build needs:

  <Class>.h      the macros a DriverKit class header expects:
                   Class_Methods / Class_KernelMethods   (expanded inside the class body by
                                                          OSDeclareDefaultStructorsWithDispatch)
                   Class_<Method>_Args                   (the parameter list of one RPC method)
                   plus every top-level #define / enum member of the .iig that the header we are
                   merged into does not already carry (iOS 26 added constants that a macOS 13.3
                   SDK header never had, e.g. kIOMemoryMapCacheModeRealTime).
  <Class>.iig.cpp  an (empty) kernel-side implementation TU.

The contract is taken from the sources, not guessed:

  iokit/DriverKit/OSObject.iig:318   #define IMPL(classname, name) classname :: DEFN(classname, name)
  iokit/DriverKit/OSObject.iig:309   #define DEFN(classname, name) name ## _Impl(classname ## _ ## name ## _Args)
  libkern/libkern/c++/OSMetaClass.h:1835
                                     #define _OS_ADD_METHODS_dispatch(className) className ## _Methods \\
                                                                                 className ## _KernelMethods

so `_Args` is a macro expanding to a parameter list (not a struct), and `IMPL(X, M)` becomes
`X::M_Impl(<params>)`.  The `_Impl` members are declared **non-virtual**: the kernel image only
needs their definitions, and declaring them virtual would add vtable slots that nothing generates.

usage: gen-iig.py --def X.iig --header out.h --impl out.cpp [--append-only]
       --append-only   keep the existing header, only append the constants it lacks
                       (used when a pre-generated SDK header was copied in).
"""
import os
import re
import sys

CLASS_RE = re.compile(r'\bclass\s+(?:KERNEL\s+)?(\w+)\s*:\s*public\s+(\w+)')
METHOD_RE = re.compile(
    r'^(?P<ret>(?:static\s+|virtual\s+|const\s+)*[\w:<>,\s\*&\[\]]+?)\s*'
    r'(?P<name>\w+)\s*\((?P<args>[^;{}]*)\)\s*(?P<tail>[^;{}]*)$')
CONSTS_RE = re.compile(r'^\s*(?:#\s*define\s+(?P<dname>\w+)\s+(?P<dval>[^\n/]+)'
                       r'|(?P<ename>\w+)\s*=\s*(?P<eval>[^,}\n]+),?)')


def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return re.sub(r'//[^\n]*', '', text)


def class_body(text, name):
    """Return the declaration block of `class [KERNEL] name : public super`, or None."""
    m = re.search(r'\bclass\s+(?:KERNEL\s+)?' + re.escape(name) + r'\s*:\s*public\s+\w+\s*\{', text)
    if not m:
        return None
    i, depth = m.end(), 1
    while i < len(text) and depth:
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
        i += 1
    return text[m.end():i - 1]


def methods(body):
    out = []
    for raw in body.split(';'):
        decl = ' '.join(raw.split())
        if not decl or '(' not in decl:
            continue
        m = METHOD_RE.match(decl)
        if not m:
            continue
        tail = m.group('tail') or ''
        if '= 0' in tail:
            continue
        name = m.group('name')
        if name in ('if', 'for', 'while', 'switch'):
            continue
        out.append({
            'name': name,
            'ret': m.group('ret').strip(),
            'args': ' '.join(m.group('args').split()),
            'local': 'LOCALONLY' in tail or 'LOCAL' in tail,
            'override': 'override' in tail,
            'static': 'static' in m.group('ret'),
        })
    return out


def constants(text):
    """Top-level #define and enum members (class bodies excluded)."""
    seen = []
    for line in text.splitlines():
        m = CONSTS_RE.match(line)
        if not m:
            continue
        if m.group('dname'):
            seen.append((m.group('dname'), m.group('dval').strip()))
        elif m.group('ename') and m.group('ename').isupper() is False:
            seen.append((m.group('ename'), m.group('eval').strip()))
    return seen


def rt(ret):
    """Return type as spelled in the .iig, made safe for a declaration."""
    ret = re.sub(r'\b(static|virtual|KERNEL|LOCALONLY|LOCAL)\b', ' ', ret)
    ret = re.sub(r'\b(public|private|protected)\s*:', ' ', ret)
    return ' '.join(ret.split())


def main(argv):
    def opt(flag):
        return argv[argv.index(flag) + 1] if flag in argv else None

    deffile, hdr, impl = opt('--def'), opt('--header'), opt('--impl')
    append_only = '--append-only' in argv
    if not (deffile and hdr):
        sys.stderr.write(__doc__)
        return 2
    text = strip_comments(open(deffile, encoding='utf-8', errors='replace').read())
    name = os.path.basename(deffile)
    name = name[:-4] if name.endswith('.iig') else name

    body = class_body(text, name)
    consts = constants(text)

    # ---- constants the header must carry ------------------------------------------------
    existing = ''
    if append_only and os.path.exists(hdr):
        existing = open(hdr, encoding='utf-8', errors='replace').read()
    missing = [(n, v) for n, v in consts
               if not re.search(r'\b' + re.escape(n) + r'\b', existing)]

    lines = []
    if not append_only:
        lines += ['/* generated by xnu-deps/gen-iig.py (stand-in for Apple\'s iig) -- do not edit */',
                  '#ifndef __GENIIG_%s_H' % name, '#define __GENIIG_%s_H' % name, '']
    elif missing:
        lines += ['', '/* constants from %s.iig that the copied SDK header lacks */' % name]

    for n, v in missing:
        if re.fullmatch(r'-?\d+[uUlL]*|0[xX][0-9a-fA-F]+[uUlL]*', v.replace('(', '').replace(')', '')):
            lines.append('#define %s %s' % (n, v))
        else:
            lines.append('#define %s %s' % (n, v))

    if not append_only and body is None:
        sys.stderr.write('gen-iig: no `class %s : public ...` found in %s\n' % (name, deffile))
        lines += ['/* no class parsed; macro spellings only */']
    if not append_only and body is not None:
        ms = methods(body)
        # LOCALONLY 只表示“不在 RPC 表里”，但内核侧仍实现 *_Impl（TestDextRematch 的
        # Start/Stop 就是 LOCAL+override 却仍有 IMPL）。多出的非虚声明无害，缺了才报错。
        rpc = [m for m in ms if m['name'] not in ('init', 'free')] + \
              [m for m in ms if m['name'] in ('init', 'free')]
        lines += ['', '/* argument-list macros: IMPL(X, M) expands to X::M_Impl(X_M_Args) */']
        for m in ms:
            lines.append('#define %s_%s_Args %s' % (name, m['name'], m['args'] if m['args'] else 'void'))
        lines += ['', '/* the two macros OSDeclareDefaultStructorsWithDispatch() splices in */',
                  '#ifndef %s_Methods' % name,
                  '#define %s_Methods' % name,
                  '#endif']
        decls = ['#define %s_KernelMethods' % name]
        for m in rpc:
            decls.append('    %s %s_Impl(%s_%s_Args);' % (rt(m['ret']), m['name'], name, m['name']))
        lines += decls
    if not append_only:
        lines += ['', '#endif /* __GENIIG_%s_H */' % name]

    if append_only:
        with open(hdr, 'a', encoding='utf-8') as f:
            f.write('\n'.join(lines) + '\n')
    else:
        with open(hdr, 'w', encoding='utf-8') as f:
            f.write('\n'.join(lines) + '\n')

    if impl:
        if not os.path.exists(impl) or append_only is False:
            with open(impl, 'w', encoding='utf-8') as f:
                f.write('/* %s: kernel-side implementation is hand written; nothing generated here */\n' % name)

    sys.stderr.write('gen-iig: %s -> %s（常量 %d 个缺失、%d 个方法）\n' % (
        name, os.path.basename(hdr), len(missing), len(methods(body)) if body else 0))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
