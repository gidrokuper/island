#!/bin/bash
# Создаёт локальный сертификат подписи «Island Local Signing» в связке «вход».
# Зачем: macOS запоминает разрешения (Полный доступ к диску, Универсальный доступ)
# по подписи приложения. С постоянным сертификатом они переживают пересборки.
# Сертификат самоподписанный, живёт только на этом Mac, никуда не отправляется.
set -e
NAME="Island Local Signing"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
  echo "Сертификат «$NAME» уже есть"; exit 0
fi
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat > "$T/c.cnf" <<EOF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
EOF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout "$T/k.pem" -out "$T/c.pem" -days 3650 -config "$T/c.cnf" 2>/dev/null
PW=$(/usr/bin/openssl rand -hex 16)
/usr/bin/openssl pkcs12 -export -inkey "$T/k.pem" -in "$T/c.pem" -out "$T/c.p12" -passout pass:"$PW" -name "$NAME"
security import "$T/c.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PW" -T /usr/bin/codesign
echo "OK сертификат «$NAME» создан. Пометка «не доверенный» для подписи своего приложения не мешает."
