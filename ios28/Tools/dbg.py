import io, re

pat = re.compile(
    r'(?m)^(?P<i>[ ]*)if let (?P<v>errorLine|message|flash) \{\n'
    r'(?P<t>[ ]*)Text\((?P=v)\)\n'
    r'(?P=t)[ ]*\.type\(T\.F\.caption\)\n'
    r'(?P=t)[ ]*\.foregroundStyle\(T\.C\.(?P<c>danger|brass|ink2)\)\n'
    r'(?P=t)[ ]*\.padding\(\.top, \d+\)\n'
    r'(?P=t)[ ]*(?P<extra>(?:\.[a-zA-Z]+\([^)\n]*\)\n)*)'
    r'(?P<e>[ ]*)\}\n'
)

p = 'App/Features/Access/CredentialCreateScreen.swift'
s = io.open(p, 'rb').read().decode('utf-8').replace('\r\n', '\n')
m = pat.search(s)
print('full match:', bool(m))
if m:
    print(repr(m.group(0)))

# 不带 extra 与 e 的版本
pat2 = re.compile(
    r'(?m)^(?P<i>[ ]*)if let (?P<v>errorLine|message|flash) \{\n'
    r'(?P<t>[ ]*)Text\((?P=v)\)\n'
    r'(?P=t)[ ]*\.type\(T\.F\.caption\)\n'
    r'(?P=t)[ ]*\.foregroundStyle\(T\.C\.(?P<c>danger|brass|ink2)\)\n'
    r'(?P=t)[ ]*\.padding\(\.top, \d+\)\n'
    r'(?P=i)[ ]*\}\n'
)
print('no-extra match:', bool(pat2.search(s)))
