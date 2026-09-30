import sys
from PIL import Image
for f in sys.argv[1:]:
    Image.open(f).crop((130,265,520,335)).resize((780,140)).save(f.replace('.png','_crop.png'))
