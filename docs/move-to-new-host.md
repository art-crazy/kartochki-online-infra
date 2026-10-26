# Перенос «Карточек» на новый VPS

## Разделение ответственности

`art-crazy/vps-infra` подготавливает Ubuntu, Docker, SSH по ключу, firewall,
внешнюю сеть `edge_kartochki` и Caddy. В этом репозитории находятся Compose,
установщик проекта, deploy, backup и systemd-настройки. Caddy здесь не запускается.
Инструкция общего хоста: `vps-infra/docs/new-host.md`.

## Конфигурация

1. Подготовьте новый хост и `/opt/kartochki` через vps-infra для `kartochki`.
2. Распакуйте этот infra в отдельный каталог, от deploy user выполните
   `bash scripts/install-project.sh`. Он сохраняет runtime env и данные.
3. Из приватного хранилища восстановите `/opt/kartochki/.env`, `postgres.env`,
   `backend.env`, `frontend.env`, `rclone-api.conf`, публичный `backup-recipients.txt`.
   Все env и rclone config — mode 0600, владелец deploy user. Получатель публичный.
   Образцы runtime/frontend/backend/postgres находятся в `env/`, полную актуальную конфигурацию
   сохраняйте отдельно: GitHub Secrets нельзя прочитать обратно.
4. В postgres.env должны согласоваться POSTGRES_DB/USER/PASSWORD и URL-кодированный
   POSTGRES_DSN в backend.env. Адрес PostgreSQL — `postgres:5432`, Redis — `redis:6379`.
   Frontend использует внутренний API `http://backend:8080` и публичные домены проекта;
   точные build/runtime переменные задаёт workflow frontend-репозитория.
5. Авторизуйте GHCR от deploy user. Публичные домены и OAuth callbacks должны
   соответствовать новому окружению. При сохранении доменов callback менять не нужно.

Сохраните приватные originals GitHub Secrets: SERVER_HOST/USER, SSH deploy/root keys,
POSTGRES_*, Yandex/VK/Telegram OAuth, RouterAI, SMTP, YooKassa, YANDEX_DISK_API_CONFIG.
Перечень backend-переменных приведён в env/backend.env.example; CI приложений
генерирует runtime env. Обновите адрес нового хоста и проверенные SSH fingerprints
во всех трёх репозиториях (infra/backend/frontend). Проверенные host keys должны
быть записаны в Secret `SERVER_KNOWN_HOSTS`; workflow намеренно не доверяет
непроверенному ssh-keyscan. Получите fingerprint через консоль провайдера и сверяйте
его перед сохранением нового ключа. Для ручного переноса root-key
GitHub не требуется. Приватный ключ расшифровки бэкапов хранится только у владельца.

## Данные до первого запуска backend

Не запускайте deploy до восстановления БД: миграции должны выполняться после restore.
Скачайте выбранный `.tar.gz.age` и его `.sha256` из `kartochki-online/complete` на Диске.
На доверенном компьютере/изолированном recovery host:

```bash
sha256sum -c kartochki-complete-<timestamp>.tar.gz.age.sha256
age -d -i ~/.ssh/id_rsa kartochki-complete-<timestamp>.tar.gz.age > recovered.tar.gz
mkdir -m 700 recovered
tar -xzf recovered.tar.gz -C recovered
cd recovered
sha256sum -c SHA256SUMS
```

Скопируйте расшифрованные database.sql.gz/storage.tar.gz по SSH во временный каталог
нового хоста с mode 0700. Не загружайте приватный age/SSH-ключ на production VPS.
Следующие команды выполняются deploy user только на НОВОМ хосте, с пустыми volumes:

```bash
cd /opt/kartochki
docker compose up -d --wait postgres redis
gzip -dc /private/recovered/database.sql.gz | docker compose exec -T postgres \
  sh -c 'exec psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
docker compose run --rm --no-deps -T --entrypoint /bin/sh backend \
  -c 'mkdir -p /app/storage; tar -xzf - -C /app/storage' < /private/recovered/storage.tar.gz
bash ./deploy.sh all
```

Перед запуском проверьте `images.json` архива: production Compose использует latest,
который со временем меняется. Для старой копии сначала восстановите совместимый образ
по сохранённому image ID/digest, затем обновляйте миграциями. Если образ недоступен,
соберите соответствующую версию из Git; не запускайте случайно несовместимую версию.
Redis очереди не включены в архив: проверьте незавершённые задания по БД до возобновления
воркеров. Бэкап БД и media не атомарен; для финального переноса остановите запись и
дождитесь окончания заданий, сделайте финальную копию при работающем backup-контейнере.

## Бэкапы и приёмка

От root выполните `bash /opt/kartochki/setup-backups.sh`, затем
`systemctl start kartochki-backup.service`. Установщик получает pinned rclone,
создаёт и включает ежедневный timer. Проверьте last-success и скачивание архива.
Не запускайте одновременно backup timer двух хостов с одним remote: retention общий.
Перед окончательным переключением остановите старый timer и старые воркеры.

Проверьте health/ready, вход, создание/чтение карточек и media через новый IP
(`curl --resolve`), затем DNS A/AAAA. После приёмки удалите временные plaintext-копии.
Подробности хранения, проверки и ограничений: README, docs/backups-2026-10-26.md.
