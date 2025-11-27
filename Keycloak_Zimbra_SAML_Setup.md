# Keycloak ↔ Zimbra SAML SSO Integration Guide

## 📋 Обзор

Полное руководство по настройке интеграции между **Keycloak** (Identity Provider) и **Zimbra** (Service Provider) через SAML протокол.

**Среда:**
- Keycloak: `192.168.1.105:8080`
- Zimbra: `mail.prokopenko.com` (https)
- ОС: Ubuntu/Debian
- Zimbra версия: 10.1.x

---

## 🔧 Предварительные требования

- ✅ Keycloak развернут и запущен
- ✅ Zimbra установлена и запущена
- ✅ DNS настроены (mail.prokopenko.com доступен)
- ✅ HTTPS сертификат установлен на Zimbra
- ✅ Доступ root на сервер Zimbra

---

## 📝 ШАГ 1: Настройка Keycloak (Identity Provider)

### 1.1 Создание Realm

```bash
# В веб-интерфейсе Keycloak (http://192.168.1.105:8080):
# 1. Нажмите на dropdown текущего Realm (обычно "master")
# 2. Нажмите "Create Realm"
# 3. Name: "zimbra"
# 4. Нажмите "Create"
```

### 1.2 Создание SAML Client

```
1. В левом меню: Clients → Create
2. Client type: SAML
3. Client ID: zimbra
4. Нажмите "Save"
```

### 1.3 Конфигурация SAML Client

В созданном Client установите:

| Параметр | Значение |
|----------|---------|
| **Master SAML Processing URL** | https://mail.prokopenko.com/service/extension/samlreceiver |
| **Valid Redirect URIs** | https://mail.prokopenko.com/* |
| **Name ID Format** | email |
| **Force POST Binding** | ON |
| **Sign Assertions** | ON |
| **Encrypt Assertions** | OFF |

### 1.4 Создание тестовых пользователей

```
1. Left menu: Users → Add user
2. Username: test@mail.prokopenko.com
3. Email: test@mail.prokopenko.com
4. First Name: Test
5. Last Name: User
6. Credentials → Set password
7. User Roles → add domain roles if needed
```

### 1.5 Получение SAML Metadata

```
Метаданные доступны по URL:
http://192.168.1.105:8080/realms/zimbra/protocol/saml/descriptor
```

---

## ⚙️ ШАГ 2: Настройка Zimbra (Service Provider)

### 2.1 Проверка установки SAML расширения

```bash
# На сервере Zimbra
ls -la /opt/zimbra/lib/ext/saml/

# Должен быть файл: samlextn.jar
```

Если расширение не установлено:

```bash
# Установка SAML расширения
sudo mkdir -p /opt/zimbra/lib/ext/saml
sudo cp samlextn.jar /opt/zimbra/lib/ext/saml/
sudo chown -R zimbra:zimbra /opt/zimbra/lib/ext/saml
```

### 2.2 Создание конфигурационного файла SAML

```bash
# Создайте директорию конфигурации
sudo mkdir -p /opt/zimbra/conf/saml

# Создайте конфиг файл
sudo cat > /opt/zimbra/conf/saml/saml-config.properties << 'EOF'
# SAML Service Provider Configuration for Zimbra

# Zimbra как Service Provider
saml_sp_entity_id=zimbra

# URL для получения SAML Response от IdP
saml_acs=https://mail.prokopenko.com/service/extension/samlreceiver

# URL для Single Logout
saml_sls=https://mail.prokopenko.com/service/extension/samlslo

# URL для перенаправления на Keycloak (IdP)
saml_redirect_login_destination=http://192.168.1.105:8080/realms/zimbra/protocol/saml/clients/zimbra

# Формат Name ID в SAML Assertion (должен быть email)
saml_name_id_format=urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress

# Формат временных меток в SAML
saml_date_format_instant=yyyy-MM-dd'T'HH:mm:ss'Z'

# Для тестирования - отключите проверку аудитории
saml_skip_audience_restriction=true
saml_skip_signature_validation=true
EOF
```

### 2.3 Установка сертификата Keycloak в Zimbra

```bash
# Получите сертификат от Keycloak
curl -k -s "http://192.168.1.105:8080/realms/zimbra/protocol/saml/descriptor" > /tmp/keycloak_metadata.xml

# Распарсите сертификат из метаданных
cat /tmp/keycloak_metadata.xml | grep -oP '(?<=<ds:X509Certificate>)[^<]+' | head -1 > /tmp/keycloak_cert_b64.txt

# Преобразуйте в PEM формат
echo "-----BEGIN CERTIFICATE-----" > /tmp/keycloak.pem
cat /tmp/keycloak_cert_b64.txt >> /tmp/keycloak.pem
echo "-----END CERTIFICATE-----" >> /tmp/keycloak.pem

# Проверьте сертификат
openssl x509 -in /tmp/keycloak.pem -text -noout | head -20

# Добавьте сертификат в конфигурацию Zimbra домена
CERT_DATA=$(cat /tmp/keycloak.pem)
sudo su - zimbra -c "zmprov md mail.prokopenko.com zimbraMyoneloginSamlSigningCert '$CERT_DATA'"

# Проверьте что был добавлен
sudo su - zimbra -c "zmprov gd mail.prokopenko.com | grep -i saml"
```

### 2.4 Настройка логина через SAML в домене

```bash
# Установите URL логина через SAML для домена
sudo su - zimbra -c "zmprov md mail.prokopenko.com zimbraWebClientLoginURL https://mail.prokopenko.com/service/extension/samllogin"

# Проверьте конфигурацию
sudo su - zimbra -c "zmprov gd mail.prokopenko.com | grep -i web"
```

### 2.5 Перезагрузка Zimbra

```bash
# Перезагрузите mailboxd сервис
sudo su - zimbra -c "zmmailboxdctl restart"

# Ждите 30-40 секунд пока сервис запустится
sleep 40

# Проверьте статус
sudo su - zimbra -c "zmmailboxdctl status"
```

---

## 🧪 ШАГ 3: Тестирование SAML логина

### 3.1 Первый вход

```bash
# Откройте браузер и перейдите по URL:
https://mail.prokopenko.com/service/extension/samllogin

# Вы должны:
# 1. Перенаправиться на страницу логина Keycloak
# 2. Ввести учетные данные пользователя (test@mail.prokopenko.com)
# 3. Вернуться в Zimbra с активной сессией
# 4. Увидеть почтовый интерфейс (или сообщение о лицензии)
```

### 3.2 Проверка логов

```bash
# Смотрите логи mailboxd для SAML событий
tail -50 /opt/zimbra/log/zmmailboxd.out | grep -i "saml\|error"

# Проверьте успешные логины
grep "saml" /opt/zimbra/log/audit.log | tail -20
```

---

## 🔐 ШАГ 4: Продвинутая конфигурация

### 4.1 Отключение проверки лицензии (если нужно)

```bash
# Удалите лицензионный модуль (только для тестирования!)
sudo rm -rf /opt/zimbra/lib/ext/zimbra-license
sudo rm -rf /opt/zimbra/zimlets-deployed/com_zimbra_license

# Перезагрузитесь
sudo su - zimbra -c "zmmailboxdctl restart"
```

### 4.2 Включение проверки подписей для продакшена

Обновите конфиг для строгой проверки:

```bash
sudo cat > /opt/zimbra/conf/saml/saml-config.properties << 'EOF'
saml_sp_entity_id=zimbra
saml_acs=https://mail.prokopenko.com/service/extension/samlreceiver
saml_sls=https://mail.prokopenko.com/service/extension/samlslo
saml_redirect_login_destination=http://192.168.1.105:8080/realms/zimbra/protocol/saml/clients/zimbra
saml_name_id_format=urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress
saml_date_format_instant=yyyy-MM-dd'T'HH:mm:ss'Z'

# ПРОДАКШЕН - включите проверки
saml_skip_audience_restriction=false
saml_skip_signature_validation=false
EOF

sudo su - zimbra -c "zmmailboxdctl restart"
```

---

## 📊 Проверка конфигурации

```bash
# Проверьте конфиг SAML
sudo cat /opt/zimbra/conf/saml/saml-config.properties

# Проверьте домен конфигурацию
sudo su - zimbra -c "zmprov gd mail.prokopenko.com | grep -i saml"

# Проверьте что сертификат установлен
sudo su - zimbra -c "zmprov gd mail.prokopenko.com | grep zimbraMyoneloginSamlSigningCert"
```

---

## 🐛 Решение проблем

### Проблема: "SAML signing certificate has not been configured"

**Решение:**
```bash
# Убедитесь что сертификат был добавлен
sudo su - zimbra -c "zmprov gd mail.prokopenko.com | grep zimbraMyoneloginSamlSigningCert"

# Если нет - добавьте его еще раз
curl -k -s "http://192.168.1.105:8080/realms/zimbra/protocol/saml/descriptor" > /tmp/metadata.xml
cat /tmp/metadata.xml | grep -oP '(?<=<ds:X509Certificate>)[^<]+' | head -1 > /tmp/cert_b64.txt
echo "-----BEGIN CERTIFICATE-----" > /tmp/cert.pem
cat /tmp/cert_b64.txt >> /tmp/cert.pem
echo "-----END CERTIFICATE-----" >> /tmp/cert.pem
CERT_DATA=$(cat /tmp/cert.pem)
sudo su - zimbra -c "zmprov md mail.prokopenko.com zimbraMyoneloginSamlSigningCert '$CERT_DATA'"
```

### Проблема: "SAML response signature verification failed"

**Решение:** Используйте сертификат Keycloak вместо самоподписанного.

### Проблема: HTTP 500 на samlreceiver

**Решение:** Проверьте логи mailboxd:
```bash
tail -50 /opt/zimbra/log/zmmailboxd.out | grep -i "error\|exception"
```

---

## 📱 Использование

### Для пользователей:

1. **Логин через SAML:**
   ```
   https://mail.prokopenko.com/service/extension/samllogin
   ```

2. **Стандартный вход в Zimbra:**
   ```
   https://mail.prokopenko.com
   ```

### Для администраторов:

1. **Админ панель:**
   ```
   https://mail.prokopenko.com:7071 (или 7072)
   ```

2. **Проверка SAML логинов:**
   ```bash
   grep -i saml /opt/zimbra/log/audit.log | tail -50
   ```

---

## ✅ Итоговый чеклист

- ✅ Keycloak Realm "zimbra" создан
- ✅ SAML Client "zimbra" создан и настроен
- ✅ Тестовые пользователи созданы в Keycloak
- ✅ SAML расширение установлено в Zimbra
- ✅ Конфиг саml-config.properties создан
- ✅ Сертификат Keycloak добавлен в Zimbra
- ✅ Домен конфигурация обновлена (zimbraWebClientLoginURL)
- ✅ Zimbra перезагружена
- ✅ SAML вход работает
- ✅ Логи проверены

---

## 📚 Дополнительные ресурсы

- **Keycloak документация:** https://www.keycloak.org/documentation
- **Zimbra документация:** https://wiki.zimbra.com/
- **SAML спецификация:** https://www.oasis-open.org/committees/saml/
- **Zimbrа SAML README:** `/opt/zimbra/extensions-network-extra/saml/README.txt`

---

## 🔗 URLs в этой конфигурации

| Компонент | URL |
|-----------|-----|
| Keycloak Admin | http://192.168.1.105:8080/admin/ |
| Keycloak Realm | http://192.168.1.105:8080/realms/zimbra |
| SAML Metadata | http://192.168.1.105:8080/realms/zimbra/protocol/saml/descriptor |
| Zimbra Webmail | https://mail.prokopenko.com |
| Zimbra Admin | https://mail.prokopenko.com:7071 |
| SAML Login | https://mail.prokopenko.com/service/extension/samllogin |
| SAML Receiver | https://mail.prokopenko.com/service/extension/samlreceiver |

---

**Версия документа:** 1.0  
**Дата:** November 12, 2025  
**Статус:** ✅ Работает и протестировано
