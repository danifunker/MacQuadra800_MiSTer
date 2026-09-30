# compare.py <image> : read the HFS partition with machfs and compare the SimCity2000 folder
# against every "SimCity2000 copy*" folder, file by file, both forks and Finder type/creator.
import sys, struct, hashlib, mmap, machfs
f = open(sys.argv[1], 'rb'); mm = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
start = cnt = None
for i in range(1, 64):
    e = mm[i*512:(i+1)*512]
    if e[:2] != b'PM': break
    pstart, pcnt = struct.unpack('>II', e[8:16]); ptype = e[48:80].split(b'\0')[0]
    if ptype == b'Apple_HFS': start, cnt = pstart, pcnt
print('HFS partition at block', start, 'blocks', cnt)
v = machfs.Volume(); v.read(mm[start*512:(start+cnt)*512])
def walk(folder, prefix=''):
    out = {}
    if not isinstance(folder, machfs.Folder):
        item = folder
        return {'(file)': (hashlib.md5(item.data).hexdigest(), hashlib.md5(item.rsrc).hexdigest(), item.type, item.creator, len(item.data), len(item.rsrc))}
    for name, item in folder.items():
        if isinstance(item, machfs.Folder): out.update(walk(item, prefix + name + ':'))
        else: out[prefix + name] = (hashlib.md5(item.data).hexdigest(), hashlib.md5(item.rsrc).hexdigest(), item.type, item.creator, len(item.data), len(item.rsrc))
    return out
desk = v['Desktop Folder'] if 'Desktop Folder' in v else v
names = [n for n in desk.keys() if n.startswith('SimCity2000')]
print('folders:', names)
ref = walk(desk['SimCity2000'])
print('SimCity2000:', len(ref), 'files,', sum(x[4]+x[5] for x in ref.values()), 'bytes')
bad = 0
for n in names:
    if n == 'SimCity2000': continue
    c = walk(desk[n])
    diff = [k for k in set(ref) | set(c) if ref.get(k) != c.get(k)]
    print(f'{n}: {len(c)} files, {"IDENTICAL" if not diff else str(len(diff)) + " DIFFER: " + ", ".join(sorted(diff)[:5])}')
    bad += len(diff)
sys.exit(1 if bad else 0)
