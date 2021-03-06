--//Nematode
--nematode by Nobuhito Aono, licensed under Creative Commons Attribution-Share Alike 3.0 and GNU GPL license.
-- Work: http://openprocessing.org/visuals/?visualID=6979
-- License:
-- http://creativecommons.org/licenses/by-sa/3.0/
-- http://creativecommons.org/licenses/GPL/2.0/
-- Modified by Georg Essl 5/30/11

height = ScreenHeight()
width = ScreenWidth()

function HSVtoRGB( h, s, v )
local i
local f, p, q, t

if  s == 0 then
    return v,v,v
end

s = s/100.0
v = v/100.0
--h = h/100.0

h = h/60.0;			--// sector 0 to 5
i = math.floor( h );
f = h - i;			--// factorial part of h
p = v * ( 1 - s );
q = v * ( 1 - s * f );
t = v * ( 1 - s * ( 1 - f ) );

v = v*255
t = t*255
p = p*255
q = q*255

if i == 0 then
    return v,t,p
elseif i == 1 then
    return q,v,p
elseif i == 2 then
    return p,v,t
elseif i == 3 then
    return p,q,v
elseif i == 4 then
return t,p,v
else
    return v,p,q
end
end

radius = 10
thickness = 0.5
x = 2
y = ScreenHeight()/2
z = ScreenHeight()/2
t = ScreenHeight()/2
amp = 5
angle = 0
i = 0

r = Region()
r:SetWidth(ScreenWidth())
r:SetHeight(ScreenHeight())
r.t=r:Texture(255,255,255,255)
r.t:SetTexCoord(0,ScreenWidth()/1024.0,1.0,0.0)
--r.t:SetBlendMode("BLEND")
r:Show()


function draw(self,elapsed)

if x<ScreenWidth() then
r2,g,b=HSVtoRGB(x/ScreenWidth()*500,100,100)
r.t:SetBrushColor(r2,g,b,30)
--    r.t:SetFill(true)
r.t:Ellipse(x, height/2+y+t, radius, radius*1.25)

r2,g,b=HSVtoRGB((ScreenWidth() - x)/ScreenWidth()*500,100,100)
r.t:SetBrushColor(r2, g, b,30)
r.t:Ellipse(x, height/2+z-t, radius, radius*0.75)

y = math.sin(angle/360*2*math.pi) * amp
z = math.cos(angle/360*2*math.pi) * amp
t = math.sin(angle/360*2*math.pi) * 10
x=x+1
angle=angle+5;
radius = radius +thickness;
if x == width/2 then thickness = thickness*-1 end
end

end

r:Handle("OnUpdate", draw)

pagebutton=Region('region', 'pagebutton', UIParent);
pagebutton:SetWidth(pagersize);
pagebutton:SetHeight(pagersize);
pagebutton:SetLayer("TOOLTIP");
pagebutton:SetAnchor('BOTTOMLEFT',ScreenWidth()-pagersize-4,ScreenHeight()-pagersize-4); 
pagebutton:EnableClamping(true)
--pagebutton:Handle("OnDoubleTap", FlipPage)
pagebutton:Handle("OnTouchDown", FlipPage)
pagebutton.texture = pagebutton:Texture("circlebutton-16.png");
pagebutton.texture:SetGradientColor("TOP",255,255,255,255,255,255,255,255);
pagebutton.texture:SetGradientColor("BOTTOM",255,255,255,255,255,255,255,255);
pagebutton.texture:SetBlendMode("BLEND")
pagebutton.texture:SetTexCoord(0,1.0,0,1.0);
pagebutton:EnableInput(true);
pagebutton:Show();
