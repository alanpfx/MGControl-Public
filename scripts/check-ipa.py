#!/usr/bin/env python3
"""校验 IPA 的最低系统版本，确认产物真的能在目标 iOS 上运行。

检查两类信息：
1. 每个 Info.plist 的 MinimumOSVersion；
2. 每个 Mach-O 二进制的 LC_BUILD_VERSION / LC_VERSION_MIN_IPHONEOS（minos）。

两者都不得高于目标版本，否则在旧系统上会直接拒绝安装。

用法：
    python3 scripts/check-ipa.py dist/MGControl-Release-unsigned.ipa --target 16.0
"""

import argparse
import plistlib
import struct
import sys
import zipfile

MACHO_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF

LC_VERSION_MIN_IPHONEOS = 0x25
LC_BUILD_VERSION = 0x32

PLATFORM_IOS = 2


def version_string(value: int) -> str:
    return f"{value >> 16}.{(value >> 8) & 0xFF}.{value & 0xFF}"


def version_tuple(text: str):
    parts = []
    for piece in text.split("."):
        try:
            parts.append(int(piece))
        except ValueError:
            parts.append(0)
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts[:3])


def parse_thin(data: bytes):
    """返回 (cmd_name, minos_int) 列表。"""
    if len(data) < 32:
        return []
    magic, _cputype, _cpusub, _ftype, ncmds, _sizeofcmds, _flags = struct.unpack_from(
        "<IiiIIII", data, 0
    )
    if magic != MACHO_MAGIC_64:
        return []

    found = []
    offset = 32
    for _ in range(ncmds):
        if offset + 8 > len(data):
            break
        cmd, cmdsize = struct.unpack_from("<II", data, offset)
        if cmdsize < 8:
            break
        if cmd == LC_BUILD_VERSION and offset + 24 <= len(data):
            platform, minos, _sdk = struct.unpack_from("<III", data, offset + 8)
            if platform == PLATFORM_IOS:
                found.append(("LC_BUILD_VERSION", minos))
        elif cmd == LC_VERSION_MIN_IPHONEOS and offset + 16 <= len(data):
            version, _sdk = struct.unpack_from("<II", data, offset + 8)
            found.append(("LC_VERSION_MIN_IPHONEOS", version))
        offset += cmdsize
    return found


def parse_macho(data: bytes):
    """处理 fat 与 thin 两种布局，返回 (cmd_name, minos_int) 列表。"""
    if len(data) < 8:
        return []

    magic_be = struct.unpack_from(">I", data, 0)[0]
    if magic_be in (FAT_MAGIC, FAT_MAGIC_64):
        nfat = struct.unpack_from(">I", data, 4)[0]
        offset = 8
        results = []
        for _ in range(min(nfat, 8)):
            if offset + 20 > len(data):
                break
            _cputype, _cpusub, arch_offset, arch_size, _align = struct.unpack_from(
                ">iiIII", data, offset
            )
            offset += 20
            slice_data = data[arch_offset : arch_offset + arch_size]
            results.extend(parse_thin(slice_data))
        return results

    return parse_thin(data)


def is_executable_candidate(name: str) -> bool:
    base = name.rsplit("/", 1)[-1]
    if base.endswith(".app") or base.endswith(".appex"):
        return False
    return "." not in base


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa")
    parser.add_argument("--target", default="16.0")
    args = parser.parse_args()

    target = version_tuple(args.target)
    rows = []
    failures = []

    with zipfile.ZipFile(args.ipa) as zf:
        names = zf.namelist()

        # 1) Info.plist
        for name in names:
            if not name.endswith("Info.plist"):
                continue
            try:
                info = plistlib.loads(zf.read(name))
            except Exception:
                rows.append((name, "Info.plist", "无法解析", False))
                continue
            bundle_id = info.get("CFBundleIdentifier", "?")
            minimum = info.get("MinimumOSVersion")
            if minimum is None:
                rows.append((f"{name}\n({bundle_id})", "Info.plist", "缺失", True))
                continue
            ok = version_tuple(str(minimum)) <= target
            rows.append((f"{name}\n({bundle_id})", "Info.plist", str(minimum), ok))
            if not ok:
                failures.append(f"{name}: MinimumOSVersion={minimum}")

        # 2) Mach-O
        for name in names:
            if not is_executable_candidate(name):
                continue
            try:
                head = zf.read(name)
            except Exception:
                continue
            entries = parse_macho(head)
            if not entries:
                continue
            for cmd, minos in entries:
                text = version_string(minos)
                ok = version_tuple(text) <= target
                rows.append((name, cmd, text, ok))
                if not ok:
                    failures.append(f"{name}: {cmd}={text}")

    print(f"目标最低版本：iOS {args.target}\n")
    print("| 文件 | 来源 | 最低版本 | 结果 |")
    print("|---|---|---|---|")
    for name, source, value, ok in rows:
        print(f"| `{name}` | {source} | {value} | {'✅' if ok else '❌ 高于目标'} |")

    if failures:
        print("\n**以下条目高于目标版本，旧系统会拒绝安装：**")
        for item in failures:
            print(f"- {item}")
        return 1

    print(f"\n全部条目均 ≤ iOS {args.target}，可以安装到该版本系统。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
