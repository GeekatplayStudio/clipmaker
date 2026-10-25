import wave, struct, math, random, sys
sr=44100; bpm=118; dur=60; out=sys.argv[1]
n=sr*dur; beat=60/bpm
buf=[0.0]*n
def add(t0, f):
    s=int(t0*sr)
    for i in range(int(0.25*sr)):
        if s+i>=n: break
        buf[s+i]+=f(i/sr)
t=0.0; k=0
while t<dur:
    add(t, lambda x: 0.9*math.sin(2*math.pi*(55+120*math.exp(-x*40))*x)*math.exp(-x*12))   # kick
    if k%2==1: add(t, lambda x: 0.4*(random.random()*2-1)*math.exp(-x*25))                  # snare
    add(t+beat/2, lambda x: 0.15*(random.random()*2-1)*math.exp(-x*80))                     # hat
    chord=[220,277,330] if (k//8)%2==0 else [196,247,294]
    add(t, lambda x: 0.12*sum(math.sin(2*math.pi*c*x) for c in chord)*math.exp(-x*3))
    t+=beat; k+=1
w=wave.open(out,'w'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
w.writeframes(b''.join(struct.pack('<h', int(max(-1,min(1,v*0.8))*32767)) for v in buf)); w.close()
print("wrote", out, bpm, "bpm")
