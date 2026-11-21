#!/usr/bin/env python3
"""English iPad 5 screenshots for the primary-language change."""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONT="/Library/Fonts/SF-Pro-Display-Black.otf"
W,H=2048,2732
RAW=os.path.join(ROOT,"screenshots","store-ipad-en")
OUT=os.path.join(ROOT,"应用商店信息","商店5图-en-iPad")
SHOTS=[("01-home","CONNECT","TO YOUR OWN SERVER IN ONE TAP"),
       ("02-nodes","MANAGE","EVERY SERVER, SORTED BY SPEED"),
       ("03-routing","ROUTE","ONLY THE TRAFFIC YOU CHOOSE"),
       ("04-import","IMPORT","QR CODE, LINK, OR SUBSCRIPTION"),
       ("05-subscriptions","SYNC","SUBSCRIPTIONS THAT STAY FRESH")]
FILES=["01-home.png","02-nodes.png","03-add-node.png","04-routing.png","05-subscriptions.png"]


def font(size): return ImageFont.truetype(FONT,size)

def bg():
    im=Image.new("RGBA",(W,H)); d=ImageDraw.Draw(im)
    top,bottom=(231,240,255),(247,236,255)
    for y in range(H):
        t=y/(H-1); c=tuple(int(top[i]+(bottom[i]-top[i])*t) for i in range(3))+(255,)
        d.line([(0,y),(W,y)],fill=c)
    blobs=Image.new("RGBA",(W,H),(0,0,0,0)); bd=ImageDraw.Draw(blobs)
    bd.ellipse([-300,100,620,900],fill=(255,214,231,120))
    bd.ellipse([W-760,500,W+260,1500],fill=(196,218,255,150))
    bd.ellipse([-420,1600,520,2600],fill=(225,211,255,110))
    bd.ellipse([W-720,1900,W+300,2830],fill=(255,227,239,135))
    im.alpha_composite(blobs.filter(ImageFilter.GaussianBlur(180)))
    return im

def wrap(draw,text,f,maxw):
    words=text.split(); lines=[]; cur=""
    for word in words:
        cand=f"{cur} {word}".strip()
        if draw.textlength(cand,font=f)<=maxw: cur=cand
        else:
            if cur: lines.append(cur)
            cur=word
    if cur: lines.append(cur)
    return lines

def compose(slug,verb,desc,raw):
    canvas=bg(); draw=ImageDraw.Draw(canvas)
    # headline
    vf=font(230); bbox=draw.textbbox((0,0),verb,font=vf)
    draw.text(((W-(bbox[2]-bbox[0]))/2,140-bbox[1]),verb,font=vf,fill=(14,21,37,255))
    y=140+(bbox[3]-bbox[1])+34
    df=font(92)
    for line in wrap(draw,desc,df,int(W*0.82)):
        lb=draw.textbbox((0,0),line,font=df)
        draw.text(((W-(lb[2]-lb[0]))/2,y-lb[1]),line,font=df,fill=(44,54,76,255))
        y+=(lb[3]-lb[1])+10
    # screenshot card
    shot=Image.open(os.path.join(RAW,raw)).convert("RGBA")
    card_w=1640; bezel=18
    card=shot.resize((card_w-2*bezel,int(shot.height*(card_w-2*bezel)/shot.width)),Image.LANCZOS)
    frame_w=card_w; frame_h=card.height+2*bezel
    x=(W-frame_w)//2; card_y=860
    # shadow
    sh=Image.new("RGBA",(W,H),(0,0,0,0)); ImageDraw.Draw(sh).rounded_rectangle([x+24,card_y+34,x+frame_w+24,card_y+frame_h+34],radius=100,fill=(60,40,80,90)); canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(45)))
    # black bezel
    layer=Image.new("RGBA",(W,H),(0,0,0,0)); ld=ImageDraw.Draw(layer)
    ld.rounded_rectangle([x,card_y,x+frame_w,card_y+frame_h],radius=100,fill=(15,17,22,255))
    mask=Image.new("L",(W,H),0); ImageDraw.Draw(mask).rounded_rectangle([x+bezel,card_y+bezel,x+bezel+card.width,card_y+bezel+card.height],radius=82,fill=255)
    layer.paste(card,(x+bezel,card_y+bezel)); layer.putalpha(mask)
    canvas.alpha_composite(layer)
    os.makedirs(OUT,exist_ok=True)
    p=os.path.join(OUT,slug+'.jpg'); canvas.convert("RGB").save(p,"JPEG",quality=92,subsampling=1); return p

def main():
    paths=[compose(*s, raw=raw) for s, raw in zip(SHOTS, FILES)]
    print("\n".join(paths))

if __name__=="__main__": main()
