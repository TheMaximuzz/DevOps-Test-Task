# DevOps Test Task

PostgreSQL (TLS), OpenLDAP (TLS), Apache Airflow (LDAP-авторизация), Prometheus (basic auth), Grafana — всё в Minikube.

## Before start

- Docker, `kubectl`, `minikube`, `helm` (см. установку ниже)
- **Важно:** одновременный запуск всех 5 сервисов требует ~10-12GB RAM. На машинах с меньшим объёмом (тестировалось на 7.5GB) рекомендуется поднимать сервисы по очереди и временно останавливать неиспользуемые (`kubectl scale deployment/statefulset --replicas=0`).

```bash
sudo apt update
sudo apt install -y docker.io postgresql-client-18 apache2-utils
sudo systemctl enable --now docker
sudo usermod -aG docker $USER && newgrp docker

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

## Развёртывание с нуля

```bash
git clone https://github.com/TheMaximuzz/DevOps-Test-Task.git
cd DevOps-Test-Task

minikube start --driver=docker --cpus=4 --memory=8g   # увеличьте, если позволяет железо

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add apache-airflow https://airflow.apache.org
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

cp .env.template .env
# заполните .env реальными паролями вручную (или сгенерируйте: openssl rand -base64 16)
set -a
source .env
set +a
```

### 1. PostgreSQL

```bash
./files/tls/generate-certs.sh
kubectl create secret generic postgresql-tls \
  --from-file=tls.crt=files/tls/postgresql/server.crt \
  --from-file=tls.key=files/tls/postgresql/server.key

helm install postgresql bitnami/postgresql \
  -f values/postgresql-values.yaml \
  --set auth.password="$POSTGRES_PASSWORD"
```

Проверка TLS:
```bash
kubectl port-forward svc/postgresql 5432:5432 &
psql "host=localhost port=5432 dbname=appdb user=appuser sslmode=disable"   # отклонено
psql "host=localhost port=5432 dbname=appdb user=appuser sslmode=require"   # успех
```

### 2. OpenLDAP

```bash
kubectl create secret generic openldap-tls \
  --from-file=tls.crt=files/tls/openldap/ldap.crt \
  --from-file=tls.key=files/tls/openldap/ldap.key \
  --from-file=ca.crt=files/tls/openldap/ldap.crt

kubectl create secret generic openldap-credentials \
  --from-literal=adminPassword="$LDAP_ADMIN_PASSWORD" \
  --from-literal=LDAP_ADMIN_PASSWORD="$LDAP_ADMIN_PASSWORD"

kubectl create configmap openldap-bootstrap-ldif \
  --from-file=files/ldif/bootstrap.ldif

kubectl apply -f k8s/openldap.yaml
```

Порты: **389 (LDAP, TLS обязателен)** / **636 (LDAPS)** — не 1389/1636 (это было особенностью другого, отброшенного чарта).

Задать реальные пароли пользователям (плейсхолдер в LDIF нерабочий по дизайну):
```bash
kubectl port-forward svc/openldap 389:389 636:636 &
LDAPTLS_REQCERT=never ldappasswd -x -D "cn=admin,dc=example,dc=org" -w "$LDAP_ADMIN_PASSWORD" \
  -H ldaps://localhost:636 -S "uid=admin_user,ou=users,dc=example,dc=org"
LDAPTLS_REQCERT=never ldappasswd -x -D "cn=admin,dc=example,dc=org" -w "$LDAP_ADMIN_PASSWORD" \
  -H ldaps://localhost:636 -S "uid=analyst_user,ou=users,dc=example,dc=org"
```

Проверка TLS:
```bash
ldapsearch -x -H ldap://localhost:389 -b "dc=example,dc=org" -D "cn=admin,dc=example,dc=org" -w "$LDAP_ADMIN_PASSWORD"
# ожидаем: confidentiality required
LDAPTLS_REQCERT=never ldapsearch -x -H ldaps://localhost:636 -b "dc=example,dc=org" -D "cn=admin,dc=example,dc=org" -w "$LDAP_ADMIN_PASSWORD"
# ожидаем: полное дерево объектов
```

> Самоподписанный сертификат → клиентские LDAP-утилиты требуют `LDAPTLS_REQCERT=never`.

### 3. Apache Airflow

```bash
kubectl create secret generic openldap-credentials \
  --from-literal=LDAP_ADMIN_PASSWORD="$LDAP_ADMIN_PASSWORD" \
  --from-literal=adminPassword="$LDAP_ADMIN_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

helm install airflow apache-airflow/airflow \
  -f values/airflow-values.yaml \
  --set data.metadataConnection.pass="$POSTGRES_PASSWORD"
```

LDAP-конфиг задаётся через `apiServer.apiServerConfig` (не `webserver.webserverConfig` — в Airflow 3.x компонент переименован в `api-server`, старый ключ монтируется, но не используется реальным контейнером). Известный баг `python-ldap` (`module 'ldap' has no attribute 'filter'`) обходится явным `import ldap.filter` в конфиге.

Проверка:
```bash
kubectl port-forward svc/airflow-api-server 8080:8080 &
```
`http://localhost:8080` → `admin_user` (роль **Admin**, доступно меню Admin) / `analyst_user` (роль **Viewer**, только просмотр).

### 4. Prometheus + Grafana

```bash
kubectl create secret generic prometheus-web-config \
  --from-file=web-config.yml=files/prometheus/web-config.yml
kubectl create secret generic prometheus-nginx-htpasswd \
  --from-file=htpasswd.txt=files/prometheus/htpasswd.txt

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -f values/kube-prometheus-values.yaml \
  --set grafana.adminPassword="$GRAFANA_ADMIN_PASSWORD"

kubectl apply -f k8s/prometheus-auth-proxy.yaml

kubectl create configmap grafana-dashboards \
  --from-file=files/grafana/dashboards/
kubectl label configmap grafana-dashboards grafana_dashboard=1
```

Проверка авторизации (через nginx-прокси, порт 9091, НЕ напрямую 9090):
```bash
kubectl port-forward svc/prometheus-authenticated 9091:8080 &
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:9091/graph                              # 401
curl -s -o /dev/null -w "%{http_code}\n" -u "prom_admin:$PROMETHEUS_PASSWORD" -L http://localhost:9091/graph  # 200
```

Grafana:
```bash
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 &
```
`http://localhost:3000` → `admin` / `$GRAFANA_ADMIN_PASSWORD`. Три дашборда (Node Exporter System, K8s Pods Resources, Services Status) появляются автоматически, без ручного импорта.

## Логи

| Сервис | Команда |
|---|---|
| PostgreSQL | `kubectl logs -f postgresql-0` |
| OpenLDAP | `kubectl logs -f $(kubectl get pods -l app=openldap -o jsonpath="{.items[0].metadata.name}")` |
| Airflow | `kubectl logs -f -l component=api-server -c api-server` |
| Prometheus | `kubectl logs -f prometheus-kube-prometheus-stack-prometheus-0 -c prometheus` |
| Grafana | `kubectl logs -f -l app.kubernetes.io/name=grafana -c grafana` |

## Резервное копирование

```bash
kubectl port-forward svc/postgresql 5432:5432 &
kubectl port-forward svc/openldap 389:389 636:636 &
POSTGRES_HOST=localhost LDAP_HOST=localhost BACKUP_DIR=./backups ./scripts/backup/backup.sh
```

Скрипт сам подгружает `.env`. Для запуска внутри кластера (`CronJob`, реальные внутрикластерные хосты) переменные `POSTGRES_HOST`/`LDAP_HOST` переопределять не нужно — берутся из `.env` как есть. Плановый запуск — см. `scripts/backup/crontab.example`.

## Управление секретами

- `.env` — реальные пароли, **не коммитится** (`.gitignore`)
- `.env.template` — шаблон без значений, коммитится
- Сертификаты (`*.crt`/`*.key`), `htpasswd.txt`, `web-config.yml` — генерируются локально, не коммитятся
- Все пароли в Kubernetes передаются через `--set`/`kubectl create secret`, никогда не хардкодятся в values-файлах

## Известные ограничения окружения

- Одновременный запуск всех сервисов требует больше 7.5GB ; рекомендуется поднимать по очереди при таком лимите
- Внешний доступ — через `kubectl port-forward`; для постоянного HTTPS-доступа потребуется Ingress + cert-manager (не входит в объём теста)
- `values/openldap-values.yaml` в истории коммитов — артефакт неудачной попытки с `helm-openldap/openldap-stack-ha`, сохранён для прозрачности процесса; актуальная конфигурация — `k8s/openldap.yaml`
