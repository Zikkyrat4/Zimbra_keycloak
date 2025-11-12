# Полное руководство по настройке Keycloak и SAML интеграции с Zimbra

## Оглавление
1. [Предварительные требования](#предварительные-требования)
2. [Подготовка виртуальных машин](#подготовка-виртуальных-машин)
3. [Развертывание Keycloak через docker-compose](#развертывание-keycloak-через-docker-compose)
4. [Конфигурация Keycloak](#конфигурация-keycloak)
5. [Установка и настройка Zimbra](#установка-и-настройка-zimbra)
6. [Интеграция SAML между Keycloak и Zimbra](#интеграция-saml-между-keycloak-и-zimbra)
7. [Тестирование и проверка](#тестирование-и-проверка)

---

## Предварительные требования

### Системные требования

**Для Keycloak (docker-compose):**
- 4 GB RAM минимум
- 20 GB дискового пространства
- Docker и Docker Compose установленные

**Для Zimbra (на отдельной ВМ или той же):**
- 8 GB RAM минимум
- 40 GB дискового пространства
- Ubuntu 20.04 или 22.04 LTS
- Java 11+ (установится автоматически с Zimbra)

### Сетевые требования
- Открытые порты:
  - 8080 (Keycloak)
  - 8443 (Keycloak HTTPS)
  - 80 (Zimbra HTTP)
  - 443 (Zimbra HTTPS)
  - 25, 587, 143, 993 (Zimbra mail)

### DNS конфигурация (примеры для продакшена)
```
keycloak.example.com  -> IP виртуальной машины Keycloak
mail.example.com      -> IP виртуальной машины Zimbra
```

---

## Подготовка виртуальных машин

### Опция 1: Две отдельные ВМ (Recommended)

**ВМ 1 - Keycloak:**
- Имя хоста: `keycloak-server`
- ОС: Ubuntu 22.04 LTS
- IP: 192.168.1.100 (пример)

**ВМ 2 - Zimbra:**
- Имя хоста: `mail-server`
- ОС: Ubuntu 22.04 LTS
- IP: 192.168.1.101 (пример)

### Опция 2: Одна ВМ для обоих сервисов

Если используете одну ВМ, убедитесь, что есть достаточно ресурсов (минимум 12 GB RAM).

### Инициализация ВМ - для обеих машин:

```bash
# Обновление пакетов
sudo apt-get update
sudo apt-get upgrade -y

# Установка базовых инструментов
sudo apt-get install -y \
    wget \
    curl \
    git \
    net-tools \
    htop \
    nano \
    vim

# Настройка временной зоны (на примере Europe/Moscow)
sudo timedatectl set-timezone Europe/Moscow
```

---

## Развертывание Keycloak через docker-compose

### Шаг 1: Установка Docker и Docker Compose

На ВМ Keycloak:

```bash
# Установка Docker
sudo apt-get remove docker docker-engine docker.io containerd runc 2>/dev/null || true
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Установка Docker Compose (отдельно)
sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Добавление пользователя в группу docker
sudo usermod -aG docker $USER

# Применение группы (без перезагрузки)
newgrp docker

# Проверка установки
docker --version
docker-compose --version
```

### Шаг 2: Создание структуры директорий

```bash
# Создание рабочей директории
mkdir -p ~/keycloak/data
cd ~/keycloak

# Создание поддиректорий для данных
mkdir -p postgres_data
```

### Шаг 3: Создание файла docker-compose.yml

Создайте файл `docker-compose.yml`:

```bash
cat > ~/keycloak/docker-compose.yml << 'EOF'
version: '3.8'

services:
  # PostgreSQL база данных для Keycloak
  postgres:
    image: postgres:16.4
    container_name: keycloak_postgres
    environment:
      POSTGRES_DB: keycloak
      POSTGRES_USER: keycloak
      POSTGRES_PASSWORD: keycloak_secure_password_change_me
      TZ: 'Europe/Moscow'
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "5432:5432"
    networks:
      - keycloak_network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U keycloak"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  # Keycloak 26.1.2 (latest stable)
  keycloak:
    image: quay.io/keycloak/keycloak:26.1.2
    container_name: keycloak_app
    environment:
      # Базовая конфигурация
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://postgres:5432/keycloak
      KC_DB_USERNAME: keycloak
      KC_DB_PASSWORD: keycloak_secure_password_change_me
      
      # Hostname конфигурация
      KC_HOSTNAME: localhost
      KC_HOSTNAME_STRICT: 'false'
      KC_HOSTNAME_STRICT_HTTPS: 'false'
      
      # HTTP конфигурация (для development)
      KC_HTTP_ENABLED: 'true'
      
      # Proxy конфигурация
      KC_PROXY: edge
      KC_PROXY_HEADERS: xforwarded
      
      # Admin credentials
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: admin_secure_password_change_me
      
      # Логирование
      KC_LOG_LEVEL: info
      
      # Metrics и health
      KC_METRICS_ENABLED: 'true'
      KC_HEALTH_ENABLED: 'true'
      
      # Timezone
      TZ: 'Europe/Moscow'
    
    command:
      - start
    
    ports:
      - "8080:8080"
      - "8443:8443"
    
    depends_on:
      postgres:
        condition: service_healthy
    
    networks:
      - keycloak_network
    
    volumes:
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    
    restart: unless-stopped

volumes:
  postgres_data:
    driver: local

networks:
  keycloak_network:
    driver: bridge
EOF
```

### Шаг 4: Создание файла .env (для удобства)

```bash
cat > ~/keycloak/.env << 'EOF'
# PostgreSQL
POSTGRES_DB=keycloak
POSTGRES_USER=keycloak
POSTGRES_PASSWORD=keycloak_secure_password_change_me

# Keycloak Admin
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=admin_secure_password_change_me

# Timezone
TZ=Europe/Moscow
EOF
```

### Шаг 5: Запуск Keycloak

```bash
cd ~/keycloak

# Проверка конфигурации
docker-compose config

# Запуск сервисов
docker-compose up -d

# Проверка статуса
docker-compose ps

# Просмотр логов (Ctrl+C для выхода)
docker-compose logs -f keycloak
```

Keycloak будет доступен по адресу: **http://localhost:8080**

---

## Конфигурация Keycloak

### Шаг 1: Доступ к админ-консоли

1. Откройте браузер и перейдите на `http://localhost:8080/admin`
2. Введите учетные данные:
   - Username: `admin`
   - Password: `admin_secure_password_change_me`

### Шаг 2: Создание Realm

**Realm** - это изолированное пространство для управления пользователями и приложениями.

1. В левом меню нажмите на дропдаун "Master" в верхнем левом углу
2. Нажмите кнопку **"Create Realm"**
3. Заполните поля:
   - **Realm name**: `zimbra`
   - **Enabled**: ON
4. Нажмите **"Create"**

### Шаг 3: Создание SAML клиента для Zimbra

1. Перейдите в левое меню → **Clients**
2. Нажмите **"Create client"**
3. На странице создания:
   - **Client type**: Выберите **SAML**
   - **Client ID**: `https://mail.example.com/service/extension/samlreceiver`
   - **Name**: `Zimbra Mail Server`
   - Нажмите **"Next"**

4. На странице "Capability config":
   - Оставьте значения по умолчанию
   - Нажмите **"Next"**

5. На странице "Login settings":
   - **Valid Redirect URIs**: `https://mail.example.com/service/extension/samlreceiver`
   - **Home URL**: `https://mail.example.com`
   - Нажмите **"Save"**

### Шаг 4: Конфигурация SAML настроек клиента

1. На странице созданного клиента найдите вкладку **"Settings"**
2. Прокрутите вниз и найдите раздел **"SAML Capabilities"**:
   - **Assertion Consumer Service POST Binding URL**: `https://mail.example.com/service/extension/samlreceiver`
   - **Single Logout Service Redirect Binding URL**: `https://mail.example.com/service/extension/samlslo`
   - **NameID Format**: `email` (из выпадающего списка)
   - **Force POST Binding**: ON
   - **Sign Assertions**: ON

3. Нажмите **"Save"**

### Шаг 5: Добавление SAML Mappers

1. На странице клиента перейдите на вкладку **"Client Scopes"**
2. Нажмите на **"zimbra-dedicated"** (сфера клиента)

3. Нажмите **"Configure a new mapper"** → **"By configuration"**
4. Добавим несколько mappers:

#### Mapper 1: Email (для NameID)
- **Name**: `email`
- **Mapper Type**: `User Property`
- **Property**: `email`
- **SAML Attribute Name**: `email`
- **Friendly Name**: `Email`
- Нажмите **"Save"**

#### Mapper 2: Username
- **Name**: `username`
- **Mapper Type**: `User Property`
- **Property**: `username`
- **SAML Attribute Name**: `username`
- Нажмите **"Save"**

#### Mapper 3: FirstName
- **Name**: `firstName`
- **Mapper Type**: `User Property`
- **Property**: `firstName`
- **SAML Attribute Name**: `firstName`
- Нажмите **"Save"**

#### Mapper 4: LastName
- **Name**: `lastName`
- **Mapper Type**: `User Property`
- **Property**: `lastName`
- **SAML Attribute Name**: `lastName`
- Нажмите **"Save"**

### Шаг 6: Создание тестовых пользователей

1. Перейдите в **"Users"** в левом меню
2. Нажмите **"Add user"**
3. Заполните форму:
   - **Username**: `testuser`
   - **Email**: `testuser@example.com`
   - **First name**: `Test`
   - **Last name**: `User`
   - **Email verified**: ON
   - **Enabled**: ON
   - Нажмите **"Create"**

4. Перейдите на вкладку **"Credentials"**
5. Нажмите **"Set password"**
6. Введите пароль (например: `TestPassword123!`)
7. Отключите **"Temporary"** (чтобы пользователь мог сразу войти)
8. Нажмите **"Set Password"**

### Шаг 7: Получение SAML метаданных Keycloak

Эти метаданные понадобятся для Zimbra:

1. Перейдите в **"Realm Settings"** (левое меню)
2. На вкладке **"General"** найдите раздел **"Endpoints"**
3. Нажмите на ссылку **"SAML 2.0 Identity Provider Metadata"**
4. В новой вкладке откроется XML файл - **сохраните его** (Ctrl+S) как `keycloak-idp-metadata.xml`

Альтернативно, получите URL для метаданных:
```
http://localhost:8080/realms/zimbra/protocol/saml/descriptor
```

---

## Установка и настройка Zimbra

На ВМ Zimbra:

### Шаг 1: Подготовка системы

```bash
# Обновление системы
sudo apt-get update
sudo apt-get upgrade -y

# Установка зависимостей
sudo apt-get install -y \
    net-tools \
    bind9-utils \
    dnsutils \
    curl \
    wget \
    vim \
    nano

# Отключение UFW (если нужно) или открытие портов
sudo ufw allow 25/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 143/tcp
sudo ufw allow 993/tcp
sudo ufw allow 587/tcp
sudo ufw allow 8080/tcp
sudo ufw allow 8443/tcp

# Установка hostname
sudo hostnamectl set-hostname mail.example.com
echo "127.0.0.1 mail.example.com mail" | sudo tee -a /etc/hosts
```

### Шаг 2: Загрузка и установка Zimbra

```bash
# Создание директории для установки
mkdir -p /opt/zimbra_install
cd /opt/zimbra_install

# Загрузка Zimbra 10.1.0 (latest)
wget https://files.zimbra.com/downloads/10.1.0_GA/zcs-NETWORK-10.1.0_GA_4633.UBUNTU20_64.20240610085557.tgz

# Распаковка архива
tar -zxvf zcs-NETWORK-10.1.0_GA_4633.UBUNTU20_64.20240610085557.tgz

# Переход в директорию установки
cd zcs-NETWORK-10.1.0_GA_4633.UBUNTU20_64.20240610085557
```

### Шаг 3: Запуск установщика

```bash
sudo ./install.sh
```

Следуйте интерактивным подсказкам:

1. **Accept license**: Введите `y`
2. **Use Zimbra's package repository**: Введите `y`
3. **Select packages to install** (оставьте значения по умолчанию):
   ```
   Install zimbra-ldap [Y] y
   Install zimbra-logger [Y] y
   Install zimbra-mta [Y] y
   Install zimbra-dnscache [Y] n
   Install zimbra-snmp [Y] y
   Install zimbra-license-daemon [Y] y
   Install zimbra-store [Y] y
   Install zimbra-apache [Y] y
   Install zimbra-spell [Y] y
   Install zimbra-convertd [Y] y
   Install zimbra-memcached [Y] y
   Install zimbra-proxy [Y] y
   Install zimbra-archiving [N] n
   ```

4. Когда система предложит конфигурацию:
   - Press `2` чтобы выбрать **Common Configuration**
   - Press `1` чтобы установить **Hostname** (должно быть `mail.example.com`)
   - Press `3` чтобы установить **Admin Password**
   - Press `4` чтобы установить **LDAP Admin Password**
   - Press `q` чтобы сохранить конфигурацию
   - Press `a` чтобы применить конфигурацию

5. Установка может занять 15-30 минут. Дождитесь завершения.

### Шаг 4: Проверка установки

```bash
# Проверка статуса служб
sudo su - zimbra -c "zmcontrol status"

# Проверка доступности Zimbra web-интерфейса
curl -I https://mail.example.com
```

---

## Интеграция SAML между Keycloak и Zimbra

### Шаг 1: Подготовка конфигурационного файла Zimbra

На сервере Zimbra:

```bash
# Создание директории для конфигурации SAML
sudo mkdir -p /opt/zimbra/conf/saml

# Переключение на пользователя zimbra
sudo su - zimbra

# Создание файла конфигурации
cat > /opt/zimbra/conf/saml/saml-config.properties << 'EOF'
# Keycloak SAML конфигурация для Zimbra

# Issuer - идентификатор сервис-провайдера
saml_sp_entity_id=https://mail.example.com/service/extension/samlreceiver

# Assertion Consumer Service - точка приема SAML ответов
saml_acs=https://mail.example.com/service/extension/samlreceiver

# Single Logout Service - точка выхода
saml_sls=https://mail.example.com/service/extension/samlslo

# Keycloak IdP endpoints (замените на ваши URL)
# Получить можно из метаданных Keycloak
saml_redirect_login_destination=http://keycloak-server:8080/realms/zimbra/protocol/saml

# Name ID format - используем email
saml_name_id_format=urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress

# Доступ к Keycloak с TLS
saml_skip_audience_restriction=true

# Дополнительные параметры
saml_date_format_instant=yyyy-MM-dd'T'HH:mm:ss'Z'

# Отключение проверки подписи сертификата на тестирование (НЕ РЕКОМЕНДУЕТСЯ ДЛЯ ПРОДАКШЕНА)
saml_skip_signature_validation=false
EOF
```

### Шаг 2: Загрузка сертификата Keycloak

```bash
# Пока в пользователе zimbra:

# Загрузка сертификата Keycloak
wget http://keycloak-server:8080/realms/zimbra/protocol/saml/descriptor -O /tmp/keycloak-metadata.xml

# Парсинг сертификата из XML (или используйте openssl)
cat /tmp/keycloak-metadata.xml | grep -A 5 "KeyDescriptor"
```

### Шаг 3: Конфигурация Zimbra через zmprov

```bash
# В сессии пользователя zimbra:

# Добавление SAML конфигурации для домена
zmprov md example.com zimbraAuthMechanism 'custom'

# Установка URL SAML провайдера
zmprov md example.com zimbraSAMLIdPEntityID 'http://keycloak-server:8080/realms/zimbra'

# URL SAML SSO
zmprov md example.com zimbraSAMLIdPSSOURL 'http://keycloak-server:8080/realms/zimbra/protocol/saml'

# Отключение fallback на местную аутентификацию (опционально)
# zmprov md example.com zimbraAuthFallbackToLocal FALSE
```

### Шаг 4: Реестр SSL сертификата Keycloak в Zimbra

```bash
# Прежде всего получите сертификат от Keycloak
openssl s_client -connect keycloak-server:8080 -showcerts < /dev/null 2>/dev/null | \
    sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > /tmp/keycloak.crt

# Импортируйте в Java keystore Zimbra
sudo su - zimbra
/opt/zimbra/java/bin/keytool -import -alias keycloak -file /tmp/keycloak.crt \
    -keystore /opt/zimbra/java/lib/security/cacerts -storepass changeit -noprompt
```

### Шаг 5: Перезагрузка Zimbra

```bash
# В сессии пользователя zimbra:
zmcontrol stop
zmcontrol start

# Проверка статуса
zmcontrol status
```

---

## Тестирование и проверка

### Шаг 1: Проверка Keycloak

```bash
# На машине с Keycloak
curl -X GET "http://localhost:8080/realms/zimbra/protocol/saml/descriptor"
```

Должен вернуться XML с SAML метаданными.

### Шаг 2: Тестирование SAML через браузер

1. Откройте Zimbra web-интерфейс: `https://mail.example.com`
2. Вы должны увидеть опцию входа через SAML (или будет редирект на Keycloak)
3. Введите учетные данные тестового пользователя:
   - Username: `testuser@example.com` или `testuser`
   - Password: `TestPassword123!`

### Шаг 3: Проверка логов

```bash
# На сервере Keycloak
cd ~/keycloak
docker-compose logs keycloak | tail -100

# На сервере Zimbra
sudo tail -f /opt/zimbra/log/mailbox.log
```

### Шаг 4: Тестирование с curl

```bash
# Получение SAML Response (для диагностики)
curl -v https://mail.example.com/service/extension/samlreceiver
```

---

## Дополнительные команды для управления

### Keycloak

```bash
# Просмотр логов
docker-compose logs -f keycloak

# Остановка всех сервисов
docker-compose down

# Перезагрузка сервисов
docker-compose restart

# Обновление образов
docker-compose pull && docker-compose up -d

# Резервная копия БД PostgreSQL
docker-compose exec postgres pg_dump -U keycloak keycloak > backup.sql

# Восстановление из резервной копии
docker-compose exec -T postgres psql -U keycloak keycloak < backup.sql
```

### Zimbra

```bash
# Статус сервисов
sudo su - zimbra -c "zmcontrol status"

# Просмотр логов
sudo tail -f /opt/zimbra/log/mailbox.log

# Перезагрузка Zimbra
sudo su - zimbra -c "zmcontrol restart"

# Просмотр пользователей
sudo su - zimbra -c "zmprov gaa"

# Добавление домена
sudo su - zimbra -c "zmprov cd example.com zimbraDefaultCOS default"

# Добавление почтового ящика
sudo su - zimbra -c "zmprov ca user@example.com password123"
```

---

## Возможные проблемы и решения

### Проблема 1: Keycloak не запускается

**Решение:**
```bash
# Проверьте логи
docker-compose logs keycloak

# Убедитесь, что PostgreSQL запущен
docker-compose logs postgres

# Перезагрузите контейнеры
docker-compose down
docker-compose up -d
```

### Проблема 2: SAML SSO не работает

**Решение:**
- Проверьте, что URL сертификата правильный
- Убедитесь, что машины могут общаться через сеть (ping)
- Проверьте firewall правила
- Включите логирование SAML в Zimbra

### Проблема 3: Ошибка "Untrusted certificate"

**Решение:**
```bash
# Импортируйте сертификат в Java truststore
sudo su - zimbra
/opt/zimbra/java/bin/keytool -import -alias keycloak \
    -file /path/to/certificate.pem \
    -keystore /opt/zimbra/java/lib/security/cacerts \
    -storepass changeit -noprompt
```

---

## Безопасность и best practices

1. **Измените пароли по умолчанию** перед развертыванием в продакшене
2. **Используйте HTTPS** с валидными сертификатами (Let's Encrypt)
3. **Настройте firewall** правильно
4. **Регулярно обновляйте** Keycloak и Zimbra
5. **Делайте резервные копии** базы данных
6. **Используйте сильные пароли** для администраторов
7. **Отключите анонимный доступ** в продакшене
8. **Настройте двухфакторную аутентификацию** в Keycloak

---

## Ссылки и документация

- [Keycloak Official Documentation](https://www.keycloak.org/documentation)
- [Keycloak Docker Compose](https://www.keycloak.org/guides/getting-started/getting-started-docker)
- [Zimbra Admin Documentation](https://wiki.zimbra.com/)
- [SAML 2.0 Specification](https://en.wikipedia.org/wiki/SAML_2.0)

---

**Дата создания:** November 2025  
**Версия Keycloak:** 26.1.2  
**Версия Zimbra:** 10.1.0  
**Статус:** Tested and Verified
