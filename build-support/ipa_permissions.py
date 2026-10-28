"""Normalize public IPA metadata without changing entry contents."""
import copy, stat, zipfile
from pathlib import PurePosixPath

MAGIC={b'\xcf\xfa\xed\xfe',b'\xce\xfa\xed\xfe',b'\xfe\xed\xfa\xcf',b'\xfe\xed\xfa\xce',b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca',b'\xca\xfe\xba\xbf',b'\xbf\xba\xfe\xca'}

def normalized(entry, data):
    path=PurePosixPath(entry.filename)
    if path.is_absolute() or '..' in path.parts or '\\' in entry.filename or not entry.filename.startswith('Payload/'):
        raise ValueError('Unsafe IPA entry')
    kind=stat.S_IFMT(entry.external_attr >> 16)
    if kind not in {0,stat.S_IFREG,stat.S_IFDIR}:
        raise ValueError('Unsupported IPA entry type')
    directory=entry.is_dir()
    mode=0o755 if directory or data[:4] in MAGIC else 0o644
    item=copy.copy(entry);item.create_system=3
    item.external_attr=((stat.S_IFDIR if directory else stat.S_IFREG)|mode)<<16
    if directory:item.external_attr |= 0x10
    return item

def normalize_ipa(source, destination):
    with zipfile.ZipFile(source) as src,zipfile.ZipFile(destination,'w',zipfile.ZIP_DEFLATED) as dst:
        if len(src.namelist()) != len(set(src.namelist())):raise ValueError('Duplicate IPA entries')
        for entry in src.infolist():
            data=src.read(entry);dst.writestr(normalized(entry,data),data)
    with zipfile.ZipFile(source) as src,zipfile.ZipFile(destination) as dst:
        assert src.namelist()==dst.namelist() and dst.testzip() is None
        for entry in dst.infolist():
            data=dst.read(entry);assert data==src.read(entry.filename)
            assert entry.create_system==3 and entry.external_attr==normalized(entry,data).external_attr
