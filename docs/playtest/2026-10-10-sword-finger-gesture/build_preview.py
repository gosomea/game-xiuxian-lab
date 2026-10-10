"""Compose only real Godot captures; preserve source frames and failed attempts."""
from pathlib import Path
import argparse,subprocess
from PIL import Image,ImageDraw,ImageFont
parser=argparse.ArgumentParser()
parser.add_argument('--evidence-dir',type=Path,default=Path(__file__).resolve().parent)
ROOT=parser.parse_args().evidence_dir
FORMS=[('sword_qi','剑气'),('flying_sword','飞剑出击'),('sword_array','剑阵'),('heavenly_sword_wheel','天轮剑阵'),('giant_sword_descent','巨剑镇落'),('heavenly_sword_rain','天降剑雨')]
font=ImageFont.truetype('/System/Library/Fonts/STHeiti Medium.ttc',24)
canvas=Image.new('RGB',(1440,660),(7,22,34));draw=ImageDraw.Draw(canvas)
for i,(key,title) in enumerate(FORMS):
 frame=35 if key not in ['sword_qi','flying_sword'] else 8
 im=Image.open(ROOT/f'{key}-{frame:03d}.png').convert('RGB').resize((480,300))
 x=(i%3)*480;y=(i//3)*330
 canvas.paste(im,(x,y));draw.text((x+18,y+301),title,font=font,fill=(217,235,222))
canvas.save(ROOT/'six_forms.png')
story=Image.new('RGB',(1440,330),(7,22,34));draw=ImageDraw.Draw(story)
for i,(frame,title) in enumerate([(35,'竖直结诀'),(50,'同轴下压'),(63,'约 105° 前下指')]):
 im=Image.open(ROOT/f'heavenly_sword_wheel-{frame:03d}.png').convert('RGB').resize((480,300))
 story.paste(im,(i*480,0));draw.text((i*480+18,301),title,font=font,fill=(217,235,222))
story.save(ROOT/'gesture_direction.png')
ffmpeg='/Users/yuqixian/.local/bin/ffmpeg'
base=[ffmpeg,'-y','-framerate','20','-pattern_type','glob','-i',str(ROOT/'sequence-*.png')]
subprocess.run(base+['-vf','scale=768:-2,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=sierra2_4a','-loop','0',str(ROOT/'gesture.gif')],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
subprocess.run(base+['-vf','scale=960:-2','-c:v','libx264','-crf','20','-pix_fmt','yuv420p','-movflags','+faststart',str(ROOT/'gesture.mp4')],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
print('Created six_forms.png / gesture.gif / gesture.mp4 from actual captures')
