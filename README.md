# Keycloak ↔ Zimbra SAML SSO Integration - Полное Руководство

**Дата:** November 12, 2025  
**Версия:** 1.0 (Working & Tested)  
**Статус:** ✅ Successfully Implemented

---

## 📋 Содержание

1. [Обзор и архитектура](#обзор)
2. [Предварительные требования](#требования)
3. [Конфигурация Keycloak](#keycloak)
4. [Конфигурация Zimbra](#zimbra)
5. [Настройка SAML](#saml-setup)
6. [Тестирование](#тестирование)
7. [Решение проблем](#решение-проблем)
8. [Команды для проверки](#проверка)

---

## 🏗️ Обзор {#обзор}

### Архитектура интеграции:

```
┌──────────────┐
│  Пользователь│
└──────┬───────┘
       │ 1. Открывает https://mail.prokopenko.com/service/extension/samllogin
       ▼
┌──────────────────────────────────────────────────────────────┐
│                    KEYCLOAK (IdP)                            │
│                  192.168.1.105:8080                          │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Realm: zimbra                                      │    │
│  │  Client: zimbra                                     │    │
│  │  Users: test@mail.prokopenko.com                    │    │
│  └─────────────────────────────────────────────────────┘    │
└──────────────────────┬────────────────────────────────────────┘
       │ 2. Аутентификация + SAML Response
       │
       ▼
┌──────────────────────────────────────────────────────────────┐
│                   ZIMBRA (Service Provider)                  │
│                  mail.prokopenko.com                         │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  SAML Extension: samlextn.jar                       │    │
│  │  Config: /opt/zimbra/conf/saml/                    │    │
│  │  Domain: mail.prokopenko.com                        │    │
│  └─────────────────────────────────────────────────────┘    │
└──────────────────────┬────────────────────────────────────────┘
       │ 3. Создание сессии + Cookie
       ▼
  ┌──────────────┐
  │   Mailbox    │
  │  Успешный    │
  │   вход       │
  └──────────────┘
```

### Информация об окружении:

| Компонент | Значение |
|-----------|---------|
| **Keycloak** | 192.168.1.105:8080 |
| **Zimbra** | mail.prokopenko.com (HTTPS) |
| **ОС** | Ubuntu/Debian |
| **Zimbra версия** | 10.1.x |
| **Protокол** | SAML 2.0 |
| **Binding** | HTTP-POST |

---

## ✅ Предварительные требования {#требования}

Перед началом убедитесь что:

- ✅ Keycloak развернут, запущен и доступен по HTTP
- ✅ Zimbra установлена и работает
- ✅ DNS для mail.prokopenko.com настроен и резолвится
- ✅ HTTPS сертификат установлен на Zimbra (self-signed OK)
- ✅ Нет проблем с доступом между Keycloak и Zimbra
- ✅ Вы имеете root/sudo доступ на сервер Zimbra

**Проверка доступности:**

```bash
# На Zimbra - проверьте доступ до Keycloak
curl -k -v http://192.168.1.105:8080/realms/zimbra/protocol/saml/descriptor

# На Keycloak - проверьте Zimbra (опционально)
curl -k -v https://mail.prokopenko.com/
```

---

## 🔑 Конфигурация Keycloak {#keycloak}

### Шаг 1.1: Создание Realm "zimbra"

```
1. Откройте http://192.168.1.105:8080/admin/
2. Логинитесь как администратор
3. В левом верхнем углу нажмите dropdown (обычно "Master")
4. Нажмите "Create Realm"
5. Заполните:
   - Name: zimbra
   - Enabled: ON
6. Нажмите "Create"
```

### Шаг 1.2: Создание SAML Client

```
1. В новом Realm "zimbra" перейдите: Clients → Create
2. Заполните:
   - Client type: SAML
   - Client ID: zimbra
3. Нажмите "Save"
```

### Шаг 1.3: Конфигурация SAML Client параметров

В настройках созданного Client установите ВСЕ следующие параметры:

```
Вкладка "Settings":
├─ Master SAML Processing URL: https://mail.prokopenko.com/service/extension/samlreceiver
├─ Valid Redirect URIs: https://mail.prokopenko.com/*
├─ Valid POST Logout Redirect URIs: https://mail.prokopenko.com/*
├─ Admin URL: https://mail.prokopenko.com
└─ Web Origins: https://mail.prokopenko.com

Вкладка "SAML Capabilities":
├─ Encrypt Assertions: OFF
├─ Client Signature Required: OFF
├─ Force POST Binding: ON
├─ Force Name ID Format: ON
│  └─ Name ID Format: email
├─ Sign Documents: ON
├─ Sign Assertions: ON
├─ Encrypt Service Documents: OFF
└─ Optimize REDIRECT-binding for RelayState: ON

Вкладка "Keys":
├─ Client Signature Required: OFF
└─ (Остальное по умолчанию)
```

### Шаг 1.4: Создание тестового пользователя

```
1. Перейдите Users → Add user
2. Заполните:
   - Username: test@mail.prokopenko.com
   - Email: test@mail.prokopenko.com
   - Email Verified: ON
   - First Name: Test
   - Last Name: User
   - Enabled: ON
3. Нажмите "Create"
4. Во вкладке "Credentials" → "Set password":
   - Password: Test123!
   - Confirm password: Test123!
   - Temporary: OFF
5. Нажмите "Set Password"
```

### Шаг 1.5: Получение SAML Metadata

Метаданные доступны по URL:

```
http://192.168.1.105:8080/realms/zimbra/protocol/saml/descriptor
```

Сохраните их - они понадобятся для Zimbra.

---

## ⚙️ Конфигурация Zimbra {#zimbra}

### Шаг 2.1: Проверка SAML расширения

На сервере Zimbra выполните:

```bash
# Проверьте наличие расширения SAML
ls -la /opt/zimbra/lib/ext/saml/

# Должны быть файлы:
# - samlextn.jar
# - (дополнительно: документация)
```

Если расширение **не установлено**, установите его:

```bash
# Создайте директорию если её нет
sudo mkdir -p /opt/zimbra/lib/ext/saml

# Если у вас есть samlextn.jar файл, скопируйте его:
sudo cp /путь/к/samlextn.jar /opt/zimbra/lib/ext/saml/

# Установите правильные права
sudo chown -R zimbra:zimbra /opt/zimbra/lib/ext/saml
sudo chmod -R 755 /opt/zimbra/lib/ext/saml
```

### Шаг 2.2: Создание конфигурационного файла SAML

Создайте директорию конфигурации:

```bash
sudo mkdir -p /opt/zimbra/conf/saml
sudo chown zimbra:zimbra /opt/zimbra/conf/saml
sudo chmod 755 /opt/zimbra/conf/saml
```

Создайте конфиг файл:

```bash
sudo cat > /opt/zimbra/conf/saml/saml-config.properties << 'EOF'
# ============================================================================
# ZIMBRA SAML SERVICE PROVIDER CONFIGURATION
# ============================================================================

# Идентификатор Zimbra как SAML Service Provider
saml_sp_entity_id=zimbra

# URL где Zimbra получает SAML Response от Identity Provider (Keycloak)
# ВАЖНО: Должен совпадать с "Master SAML Processing URL" в Keycloak Client
saml_acs=https://mail.prokopenko.com/service/extension/samlreceiver

# URL для Single Logout (выход)
saml_sls=https://mail.prokopenko.com/service/extension/samlslo

# URL Identity Provider (Keycloak) куда перенаправляется пользователь для логина
saml_redirect_login_destination=http://192.168.1.105:8080/realms/zimbra/protocol/saml/clients/zimbra

# Формат Name Identifier в SAML Assertion
# ВАЖНО: Должен быть "email" для сопоставления с пользователями Zimbra
saml_name_id_format=urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress

# Формат временных меток в SAML (ISO 8601)
saml_date_format_instant=yyyy-MM-dd'T'HH:mm:ss'Z'

# ============================================================================
# РЕЖИМ: ТЕСТИРОВАНИЕ (отключены проверки)
# Для ПРОДАКШЕНА измените на false и добавьте сертификат
# ============================================================================

# Пропустить проверку Audience (целевого Realm)
saml_skip_audience_restriction=true

# Пропустить проверку подписи SAML Response
saml_skip_signature_validation=true

# ============================================================================
EOF
```

Проверьте что файл создан:

```bash
sudo cat /opt/zimbra/conf/saml/saml-config.properties
```

---

## 📡 Настройка SAML интеграции {#saml-setup}

### Шаг 3.1: Получение сертификата Keycloak

На сервере Zimbra получите сертификат от Keycloak:

```bash
# Загрузите SAML метаданные
curl -k -s "http://192.168.1.105:8080/realms/zimbra/protocol/saml/descriptor" > /tmp/keycloak_metadata.xml

# Проверьте что файл загрузился
cat /tmp/keycloak_metadata.xml | head -5
```

Извлеките сертификат из метаданных:

```bash
# Получите Base64 кодированный сертификат
cat /tmp/keycloak_metadata.xml | grep -oP '(?<=<ds:X509Certificate>)[^<]+' | head -1 > /tmp/keycloak_cert_b64.txt

# Преобразуйте в PEM формат
echo "-----BEGIN CERTIFICATE-----" > /tmp/keycloak.pem
cat /tmp/keycloak_cert_b64.txt >> /tmp/keycloak.pem
echo "-----END CERTIFICATE-----" >> /tmp/keycloak.pem

# Проверьте что сертификат правильный
openssl x509 -in /tmp/keycloak.pem -text -noout | head -20
```

### Шаг 3.2: Добавление сертификата в конфигурацию Zimbra домена

Добавьте сертификат Keycloak в конфигурацию домена Zimbra:

```bash
# Получите содержимое сертификата
CERT_DATA=$(cat /tmp/keycloak.pem)

# Добавьте сертификат через zmprov
sudo su - zimbra -c "zmprov md mail.prokopenko.com zimbraMyoneloginSamlSigningCert '$CERT_DATA'"

# Проверьте что был добавлен (должен быть длинный текст)
sudo su - zimbra -c "zmprov gd mail.prokopenko.com | grep -i saml"
```

Ожидаемый результат:

```
zimbraMyoneloginSamlSigningCert: -----BEGIN CERTIFICATE-----
                                MIIDXTCCAkWgAwIBAgIRAL...
                                ...длинный сертификат...
                                ... -----END CERTIFICATE-----
```

### Шаг 3.3: Настройка URL логина через SAML для домена

Установите URL для SAML логина:

```bash
# Установите zimbraWebClientLoginURL на SAML endpoint
sudo su - zimbra -c "zmprov md mail.prokopenko.com zimbraWebClientLoginURL https://mail.prokopenko.com/service/extension/samllogin"

# Проверьте
sudo su - zimbra -c "zmprov gd mail.prokopenko.com | grep -i zimbraWebClientLoginURL"
```

### Шаг 3.4: Перезагрузка Zimbra mailboxd

Перезагрузите сервис:

```bash
# Остановите mailboxd
sudo su - zimbra -c "zmmailboxdctl stop"

# Дождитесь остановки (30-60 секунд)
sleep 30

# Запустите mailboxd
sudo su - zimbra -c "zmmailboxdctl start"

# Дождитесь запуска (40-60 секунд)
sleep 60

# Проверьте статус
sudo su - zimbra -c "zmmailboxdctl status"
```

Ожидаемый результат:

```
amavis: running
antivirus: running
antispam: running
apache: running
memcached: running
ldap: running
mysql: running
mailboxd: running (PID: XXXXX)
```

---

## 🧪 Тестирование {#тестирование}

### Тест 1: Проверка доступности SAML endpoint

```bash
# Проверьте что SAML endpoints доступны
curl -k -I https://mail.prokopenko.com/service/extension/samllogin
curl -k -I https://mail.prokopenko.com/service/extension/samlreceiver
curl -k -I https://mail.prokopenko.com/service/extension/samlslo

# Должны быть HTTP ответы (302 Redirect или 200 OK)
```

### Тест 2: Вход через SAML в браузере

1. Откройте новое окно в инкогнито режиме браузера
2. Перейдите по URL: `https://mail.prokopenko.com/service/extension/samllogin`
3. Вы должны перенаправиться на страницу логина Keycloak
4. Введите учетные данные: `test@mail.prokopenko.com` / `Test123!`
5. Нажмите "Sign In"
6. Вы должны вернуться в Zimbra и войти автоматически

**Ожидаемый результат:**

- ✅ Перенаправление на Keycloak
- ✅ Успешная аутентификация в Keycloak
- ✅ Возврат в Zimbra
- ✅ Автоматический вход в почту или сообщение о лицензии
- ✅ Сессия создана (видны cookies)

### Тест 3: Проверка логов

```bash
# Проверьте логи для SAML событий
tail -50 /opt/zimbra/log/zmmailboxd.out | grep -i "saml\|error"

# Проверьте успешные логины в audit.log
grep "saml\|SAML" /opt/zimbra/log/audit.log | tail -20

# Проверьте что нет ошибок
tail -20 /opt/zimbra/log/zmmailboxd.out
```

**Признак успеха:**
- Нет ошибок типа "SAML signing certificate has not been configured"
- Нет ошибок типа "SAML response signature verification failed"
- Видны логи про успешную аутентификацию

---

## 🐛 Решение проблем {#решение-проблем}

### Проблема 1: "SAML signing certificate has not been configured"

**Симптомы:** HTTP 500 ошибка при попытке входа через SAML

**Причина:** Сертификат не был добавлен в конфигурацию домена

**Решение:**

```bash
# Проверьте наличие сертификата
sudo su - zimbra -c "zmprov gd mail.prokopenko.com | grep zimbraMyoneloginSamlSigningCert"

# Если нет - добавьте его еще раз
curl -k -s "http://192.168.1.105:8080/realms/zimbra/protocol/saml/descriptor" > /tmp/metadata.xml
cat /tmp/metadata.xml | grep -oP '(?<=<ds:X509Certificate>)[^<]+' | head -1 > /tmp/cert_b64.txt
echo "-----BEGIN CERTIFICATE-----" > /tmp/cert.pem
cat /tmp/cert_b64.txt >> /tmp/cert.pem
echo "-----END CERTIFICATE-----" >> /tmp/cert.pem
CERT_DATA=$(cat /tmp/cert.pem)
sudo su - zimbra -c "zmprov md mail.prokopenko.com zimbraMyoneloginSamlSigningCert '$CERT_DATA'"

# Перезагрузитесь
sudo su - zimbra -c "zmmailboxdctl restart"
sleep 60
```

### Проблема 2: "SAML response signature verification failed"

**Симптомы:** HTTP 500 при входе с ошибкой про подпись

**Причина:** Keycloak подписывает Response своим сертификатом, но Zimbra проверяет подпись неправильно

**Решение:** Используйте сертификат Keycloak (уже сделано выше)

```bash
# Проверьте что используется сертификат Keycloak
sudo su - zimbra -c "zmprov gd mail.prokopenko.com | grep zimbraMyoneloginSamlSigningCert | head -c 200"

# Если нужно - повторите Шаг 3.1 и 3.2
```

### Проблема 3: Перенаправление на Keycloak не происходит

**Симптомы:** При входе на samllogin остаетесь на той же странице

**Причина:** Неправильно настроена ссылка на Keycloak в конфиге

**Решение:**

```bash
# Проверьте конфиг
sudo cat /opt/zimbra/conf/saml/saml-config.properties | grep "redirect_login"

# Должна быть строка:
# saml_redirect_login_destination=http://192.168.1.105:8080/realms/zimbra/protocol/saml/clients/zimbra

# Если неправильно - отредактируйте файл и перезагрузитесь
```

### Проблема 4: "You do not have a valid license"

**Симптомы:** Сообщение об ошибке лицензии после успешного входа через SAML

**Причина:** Лицензия Zimbra истекла или отсутствует

**Решение:** Это НЕ проблема SAML - вы успешно вошли! Выберите один вариант:

**Вариант А - Игнорировать (проще):**
```bash
# Просто нажмите OK и пользуйтесь почтой
```

**Вариант Б - Удалить проверку лицензии:**
```bash
# Удалите модули проверки лицензии
sudo rm -rf /opt/zimbra/lib/ext/zimbra-license
sudo rm -rf /opt/zimbra/zimlets-deployed/com_zimbra_license

# Перезагрузитесь
sudo su - zimbra -c "zmmailboxdctl restart"
sleep 60
```

---

## ✔️ Команды для проверки {#проверка}

### Проверка конфигурации SAML

```bash
# 1. Проверьте конфиг файл
sudo cat /opt/zimbra/conf/saml/saml-config.properties

# 2. Проверьте конфигурацию домена
sudo su - zimbra -c "zmprov gd mail.prokopenko.com | grep -i saml"

# 3. Проверьте что сертификат установлен
sudo su - zimbra -c "zmprov gd mail.prokopenko.com | grep zimbraMyoneloginSamlSigningCert | wc -c"
# Должно быть > 1000 символов

# 4. Проверьте URL логина
sudo su - zimbra -c "zmprov gd mail.prokopenko.com | grep zimbraWebClientLoginURL"
```

### Проверка статуса сервисов

```bash
# Проверьте статус mailboxd
sudo su - zimbra -c "zmmailboxdctl status"

# Проверьте что сервис запущен
ps aux | grep mailboxd | grep -v grep

# Проверьте слушаемые порты
sudo netstat -tlnp | grep java
```

### Проверка логов

```bash
# Последние SAML события
grep -i "saml" /opt/zimbra/log/zmmailboxd.out | tail -30

# Ошибки в логах
grep "ERROR" /opt/zimbra/log/zmmailboxd.out | tail -20

# Audit логи (успешные логины)
grep "auth" /opt/zimbra/log/audit.log | tail -30
```

### Проверка доступности

```bash
# SAML endpoints
curl -k -v https://mail.prokopenko.com/service/extension/samllogin 2>&1 | grep -i "location\|status"

# Keycloak metadata
curl -k -s http://192.168.1.105:8080/realms/zimbra/protocol/saml/descriptor | head -5
```

---

**✅ ГОТОВО! SAML интеграция между Keycloak и Zimbra успешно работает!** 🎉🚀
