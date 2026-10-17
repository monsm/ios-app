import io,json,subprocess,sys,time,urllib.request,zipfile
REPO="monsm/ios-app"
def token():
    p=subprocess.run(["git","credential","fill"],input="protocol=https\nhost=github.com\n\n",capture_output=True,text=True,check=True)
    d=dict(l.split("=",1) for l in p.stdout.strip().splitlines() if "=" in l)
    return d.get("password") or d.get("username")
TOK=token()
def api(u):
    r=urllib.request.Request(u,headers={"Authorization":"Bearer "+TOK,"Accept":"application/vnd.github+json","User-Agent":"ci"})
    return urllib.request.urlopen(r,timeout=60).read()
sha=sys.argv[1]; deadline=time.time()+int(sys.argv[2])*60; rid=None
while time.time()<deadline:
    d=json.loads(api(f"https://api.github.com/repos/{REPO}/actions/runs?branch=main&per_page=6"))
    for r in d["workflow_runs"]:
        if r["head_sha"].startswith(sha):
            rid=r["id"]; st=(r["status"],r["conclusion"]); break
    if rid:
        print(time.strftime("%H:%M:%S"),rid,st,flush=True)
        if st[0]=="completed": break
    time.sleep(20)
raw=api(f"https://api.github.com/repos/{REPO}/actions/runs/{rid}/logs")
z=zipfile.ZipFile(io.BytesIO(raw))
txt="\n".join(z.read(n).decode("utf-8","replace") for n in z.namelist() if n.endswith(".txt"))
open("_ci_new.log","w",encoding="utf-8").write(txt); print("bytes",len(txt))
