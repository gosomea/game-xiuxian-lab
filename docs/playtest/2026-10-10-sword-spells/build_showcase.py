"""Build silent previews and phase sheets from the accepted real-window PNGs."""
from pathlib import Path
import json, shutil, subprocess
from PIL import Image, ImageDraw
base = Path(__file__).resolve().parent
report = json.loads((base / 'acceptance.json').read_text())
run = base / Path(report['run_dir']).name
ffmpeg = shutil.which('ffmpeg')
assert ffmpeg, 'Use an installed ffmpeg to reproduce the preview.'
forms = ['heavenly_sword_wheel', 'giant_sword_descent', 'heavenly_sword_rain']
clips=[]
for form in forms:
    target=base/(form+'.mp4')
    if not target.exists():
        subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-y','-framerate','20','-pattern_type','glob','-i',str(run/(form+'-*.png')),'-c:v','libx264','-crf','20','-pix_fmt','yuv420p',str(target)],check=True)
    clips.append(target)
listing=base/'showcase_concat.txt'
listing.write_text(''.join("file '"+str(p)+"'\n" for p in clips))
if not (base/'showcase.mp4').exists():
    subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-y','-f','concat','-safe','0','-i',str(listing),'-c','copy',str(base/'showcase.mp4')],check=True)
if not (base/'showcase.gif').exists():
    subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-y','-i',str(base/'showcase.mp4'),'-filter_complex','fps=20,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=3','-loop','0',str(base/'showcase.gif')],check=True)
# Samples and captures use the same labelled frame indices. Keep phase sheets for review.
for form in forms:
    samples=[]
    last_frame=-1
    for sample in report['samples']:
        if sample.get('form')==form and not sample.get('summary'):
            if sample['frame']<=last_frame: break
            samples.append(sample)
            last_frame=sample['frame']
    phases=[]
    for sample in samples:
        if sample['phase'] not in phases and sample['phase']!='idle': phases.append(sample['phase'])
    if form=='giant_sword_descent': phases=['gather','hover','descent','impact','fade']
    sheet=Image.new('RGB',(640*len(phases),430),(10,24,30));draw=ImageDraw.Draw(sheet)
    frames=sorted(run.glob(form+'-*.png'))
    for i,phase in enumerate(phases):
        subset=[s for s in samples if s['phase']==phase]
        selected=subset[min(len(subset)-1,int(len(subset)*(.85 if phase=='gather' else .5)))]['frame']
        frame=min(frames,key=lambda p:abs(int(p.stem.rsplit('-',1)[1])-selected))
        img=Image.open(frame).convert('RGB').resize((640,400),Image.Resampling.LANCZOS)
        sheet.paste(img,(i*640,30));draw.text((i*640+15,8),form+' / '+phase,fill=(205,245,230))
    target=base/(form+'-phases-v2.png')
    if not target.exists(): sheet.save(target)
print('Built',base/'showcase.mp4',base/'showcase.gif')
