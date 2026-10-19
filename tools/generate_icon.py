"""Render the app's original geometric sun mark; no reference images used."""
from pathlib import Path
from PIL import Image, ImageDraw
root = Path(__file__).resolve().parent.parent / 'app'
def mark(size):
    image = Image.new('RGBA', (size, size))
    draw = ImageDraw.Draw(image)
    box = lambda a,b,c,d: tuple(round(n*size) for n in (a,b,c,d))
    draw.rounded_rectangle(box(.02,.02,.98,.98), radius=round(size*.22), fill='#436395')
    draw.rounded_rectangle(box(.20,.20,.80,.80), radius=round(size*.27), fill='#FFE3A7')
    for x in (.43,.57):
        draw.ellipse(box(x-.016,.424,x+.016,.456),fill='#675731')
    draw.arc(box(.40,.45,.60,.60),0,180,fill='#675731',width=max(1,round(size*.018)))
    return image
brand=root/'assets'/'brand'; brand.mkdir(parents=True,exist_ok=True)
mark(1024).save(brand/'day.png')
mark(256).save(root/'windows'/'runner'/'resources'/'app_icon.ico',sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])
for qualifier,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    mark(size).save(root/'android'/'app'/'src'/'main'/'res'/f'mipmap-{qualifier}'/'ic_launcher.png')
