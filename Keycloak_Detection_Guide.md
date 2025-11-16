# 🔍 МЕТОДЫ СЕТЕВОГО ОБНАРУЖЕНИЯ KEYCLOAK

## ЧАСТЬ 1: АКТИВНОЕ СКАНИРОВАНИЕ ПОРТОВ (nmap)

### Шаг 1.1: Установка nmap

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install nmap

# macOS
brew install nmap

# CentOS/RHEL
sudo yum install nmap

# Проверка версии
nmap --version
```

### Шаг 1.2: Сканирование портов (базовое)

```bash
# Просканировать конкретный хост на портах 8000-9000
nmap -p 8000-9000 192.168.1.105

# Результат:
# PORT     STATE SERVICE
# 8080/tcp open  http-proxy
# 9090/tcp open  zeus-admin
```

**Интерпретация:**
- `open` - порт открыт (Keycloak слушает)
- `closed` - порт закрыт
- `filtered` - порт заблокирован firewall

### Шаг 1.3: Определение версии сервера

```bash
# Сканирование с определением версии (-sV)
nmap -sV -p 8080 192.168.1.105

# Результат может быть:
# PORT     STATE SERVICE VERSION
# 8080/tcp open  http    Undertow (WildFly/Keycloak)
```

### Шаг 1.4: Сканирование с захватом баннера

```bash
# Получить HTTP заголовки (баннер грабинг)
nmap -sV --script=http-server-header -p 8080 192.168.1.105

# Результат:
# | http-server-header: 
# |_  Undertow/2.2.x
```

### Шаг 1.5: Агрессивное сканирование (полный набор)

```bash
# Включить все методы обнаружения
nmap -A -p 8080 192.168.1.105

# -A = ОС detection + версия + scripts + traceroute
```

---

## ЧАСТЬ 2: СПЕЦИФИЧЕСКИЕ СИГНАТУРЫ KEYCLOAK

### Шаг 2.1: HTTP-fingerprinting (определение по HTTP заголовкам)

```bash
# Получить HTTP ответ
curl -v http://192.168.1.105:8080/ 2>&1 | head -20

# Ищите в ответе:
# Server: Undertow
# X-Powered-By: Keycloak
# или
# /realms/
# /auth/
```

### Шаг 2.2: Проверка уникальных Keycloak endpoints

```bash
# Проверить наличие OIDC metadata
curl -s http://192.168.1.105:8080/.well-known/openid-configuration | jq .

# Проверить SAML metadata
curl -s http://192.168.1.105:8080/realms/master/protocol/saml/descriptor

# Проверить Keycloak admin console
curl -s http://192.168.1.105:8080/admin/ | grep -i keycloak
```

### Шаг 2.3: nmap NSE скрипт для обнаружения Keycloak

Создайте файл `detect-keycloak.nse`:

```lua
local http = require "http"
local shortport = require "shortport"
local stdnse = require "stdnse"

description = "Detect Keycloak Identity Server"
categories = {"default", "discovery", "safe"}

portrule = shortport.port_or_service({8080, 8443, 9090}, {"http", "https"})

action = function(host, port)
    local paths = {
        "/.well-known/openid-configuration",
        "/realms/master/protocol/oidc/certs",
        "/admin/",
        "/auth/",
        "/realms/"
    }
    
    for _, path in ipairs(paths) do
        local response = http.get(host, port, path)
        
        if response.status == 200 then
            if string.find(response.body, "keycloak") or
               string.find(response.body, "issuer") or
               string.find(response.body, "authorization_endpoint") then
                return "Keycloak detected on " .. path
            end
        end
    end
    
    -- Check Server header
    if response.header["server"] and
       string.find(response.header["server"], "Undertow") then
        return "Possible Keycloak (Undertow server)"
    end
    
    return nil
end
```

Использование:

```bash
# Скопируйте скрипт в nmap scripts
sudo cp detect-keycloak.nse /usr/share/nmap/scripts/

# Обновите базу скриптов
nmap --script-updatedb

# Запустите скрипт
nmap -p 8080 --script detect-keycloak 192.168.1.105
```

---

## ЧАСТЬ 3: PYTHON СКРИПТ ДЛЯ ОБНАРУЖЕНИЯ

### Шаг 3.1: Установка библиотек

```bash
pip install requests beautifulsoup4
```

### Шаг 3.2: Создание скрипта обнаружения

Создайте файл `keycloak_detector.py`:

```python
#!/usr/bin/env python3
"""
Keycloak Service Discovery Tool
Обнаружение Keycloak сервера по активному сканированию
"""

import requests
import sys
import json
from urllib.parse import urljoin
from requests.packages.urllib3.exceptions import InsecureRequestWarning

# Подавить SSL предупреждения
requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

class KeycloakDetector:
    def __init__(self, target_host, target_port=8080, timeout=5):
        """
        Инициализация детектора
        
        Args:
            target_host: IP адрес или хостнейм
            target_port: Порт (по умолчанию 8080)
            timeout: Таймаут запроса
        """
        self.target_host = target_host
        self.target_port = target_port
        self.timeout = timeout
        self.base_url = f"http://{target_host}:{target_port}"
        self.results = {
            "detected": False,
            "version": None,
            "endpoints": [],
            "server_header": None,
            "signatures": []
        }
    
    def test_port_open(self):
        """Проверка открыт ли порт"""
        print(f"[*] Проверка доступности {self.base_url}...")
        try:
            response = requests.get(self.base_url, timeout=self.timeout, verify=False)
            print(f"[+] Порт открыт (HTTP {response.status_code})")
            self.results["server_header"] = response.headers.get("Server", "Unknown")
            return True
        except requests.exceptions.ConnectionError:
            print(f"[-] Не удается подключиться к {self.base_url}")
            return False
        except Exception as e:
            print(f"[-] Ошибка: {e}")
            return False
    
    def check_oidc_endpoint(self):
        """Проверка OIDC metadata endpoint"""
        print("\n[*] Проверка OIDC endpoints...")
        endpoints = [
            "/.well-known/openid-configuration",
            "/realms/master/.well-known/openid-configuration",
        ]
        
        for endpoint in endpoints:
            url = urljoin(self.base_url, endpoint)
            try:
                response = requests.get(url, timeout=self.timeout, verify=False)
                if response.status_code == 200:
                    print(f"[+] Найден OIDC endpoint: {url}")
                    self.results["endpoints"].append(url)
                    self.results["signatures"].append("OIDC endpoint found")
                    
                    # Попробуйте спарсить JSON
                    try:
                        data = response.json()
                        if "issuer" in data:
                            print(f"    Issuer: {data['issuer']}")
                            self.results["signatures"].append(f"Issuer: {data['issuer']}")
                    except:
                        pass
                    
                    return True
            except requests.exceptions.Timeout:
                pass
            except Exception:
                pass
        
        return False
    
    def check_saml_endpoint(self):
        """Проверка SAML endpoint"""
        print("\n[*] Проверка SAML endpoints...")
        endpoints = [
            "/realms/master/protocol/saml/descriptor",
            "/auth/realms/master/protocol/saml/descriptor",
        ]
        
        for endpoint in endpoints:
            url = urljoin(self.base_url, endpoint)
            try:
                response = requests.get(url, timeout=self.timeout, verify=False)
                if response.status_code == 200:
                    print(f"[+] Найден SAML endpoint: {url}")
                    self.results["endpoints"].append(url)
                    self.results["signatures"].append("SAML endpoint found")
                    return True
            except requests.exceptions.Timeout:
                pass
            except Exception:
                pass
        
        return False
    
    def check_admin_console(self):
        """Проверка Admin Console"""
        print("\n[*] Проверка Admin Console...")
        endpoints = [
            "/admin/",
            "/auth/admin/",
            "/admin/master/console/",
        ]
        
        for endpoint in endpoints:
            url = urljoin(self.base_url, endpoint)
            try:
                response = requests.get(url, timeout=self.timeout, verify=False)
                if response.status_code in [200, 302]:
                    print(f"[+] Найден Admin endpoint: {url}")
                    self.results["endpoints"].append(url)
                    self.results["signatures"].append("Admin console accessible")
                    return True
            except requests.exceptions.Timeout:
                pass
            except Exception:
                pass
        
        return False
    
    def check_login_pages(self):
        """Проверка страниц логина"""
        print("\n[*] Проверка страниц логина...")
        endpoints = [
            "/realms/master/protocol/openid-connect/auth",
            "/auth/realms/master/protocol/openid-connect/auth",
        ]
        
        for endpoint in endpoints:
            url = urljoin(self.base_url, endpoint)
            try:
                response = requests.get(url, timeout=self.timeout, verify=False)
                if response.status_code in [200, 302]:
                    print(f"[+] Найдена страница: {url}")
                    
                    # Проверьте HTML на сигнатуры Keycloak
                    if "keycloak" in response.text.lower():
                        print(f"    [+] Найдена сигнатура 'keycloak' в HTML")
                        self.results["signatures"].append("'keycloak' text in HTML")
                    
                    if "undertow" in response.headers.get("server", "").lower():
                        print(f"    [+] Найден Undertow server")
                        self.results["signatures"].append("Undertow server detected")
                    
                    self.results["endpoints"].append(url)
                    return True
            except requests.exceptions.Timeout:
                pass
            except Exception:
                pass
        
        return False
    
    def check_server_headers(self):
        """Анализ HTTP заголовков"""
        print("\n[*] Анализ HTTP заголовков...")
        
        try:
            response = requests.get(self.base_url, timeout=self.timeout, verify=False)
            
            # Проверка на Undertow (Keycloak использует Undertow)
            server = response.headers.get("Server", "")
            if "Undertow" in server:
                print(f"[+] Обнаружен Undertow сервер: {server}")
                self.results["signatures"].append(f"Server: {server}")
            
            # Проверка на другие сигнатуры
            for header_name, header_value in response.headers.items():
                if "keycloak" in header_value.lower():
                    print(f"[+] Сигнатура Keycloak найдена в заголовке {header_name}: {header_value}")
                    self.results["signatures"].append(f"{header_name}: {header_value}")
        
        except Exception as e:
            print(f"[-] Ошибка при анализе заголовков: {e}")
    
    def check_jwks_endpoint(self):
        """Проверка JWKS endpoint (для JWT ключей)"""
        print("\n[*] Проверка JWKS endpoints...")
        endpoints = [
            "/realms/master/protocol/openid-connect/certs",
            "/realms/master/protocol/oidc/certs",
        ]
        
        for endpoint in endpoints:
            url = urljoin(self.base_url, endpoint)
            try:
                response = requests.get(url, timeout=self.timeout, verify=False)
                if response.status_code == 200:
                    try:
                        data = response.json()
                        if "keys" in data:
                            print(f"[+] Найден JWKS endpoint: {url}")
                            print(f"    Найдено {len(data['keys'])} ключей")
                            self.results["endpoints"].append(url)
                            self.results["signatures"].append(f"JWKS endpoint with {len(data['keys'])} keys")
                            return True
                    except:
                        pass
            except requests.exceptions.Timeout:
                pass
            except Exception:
                pass
        
        return False
    
    def detect(self):
        """Главный метод обнаружения"""
        print("=" * 60)
        print("🔍 KEYCLOAK SERVICE DETECTION TOOL")
        print("=" * 60)
        print(f"\nЦель: {self.target_host}:{self.target_port}\n")
        
        # Проверка доступности порта
        if not self.test_port_open():
            return False
        
        # Запуск всех проверок
        checks_results = [
            self.check_oidc_endpoint(),
            self.check_saml_endpoint(),
            self.check_admin_console(),
            self.check_login_pages(),
            self.check_jwks_endpoint(),
        ]
        
        self.check_server_headers()
        
        # Определение результата
        if any(checks_results) or len(self.results["signatures"]) > 0:
            self.results["detected"] = True
        
        return self.results["detected"]
    
    def print_report(self):
        """Вывод отчета"""
        print("\n" + "=" * 60)
        print("📊 РЕЗУЛЬТАТЫ ОБНАРУЖЕНИЯ")
        print("=" * 60)
        
        if self.results["detected"]:
            print("\n✅ KEYCLOAK ОБНАРУЖЕН!")
        else:
            print("\n❌ Keycloak не обнаружен")
        
        print(f"\nServer Header: {self.results['server_header']}")
        
        if self.results["endpoints"]:
            print(f"\nНайденные endpoints ({len(self.results['endpoints'])}):")
            for endpoint in self.results["endpoints"]:
                print(f"  • {endpoint}")
        
        if self.results["signatures"]:
            print(f"\nНайденные сигнатуры ({len(self.results['signatures'])}):")
            for sig in self.results["signatures"]:
                print(f"  • {sig}")
        
        print("\n" + "=" * 60)
        
        return self.results


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Использование: python3 keycloak_detector.py <host> [port]")
        print("Пример: python3 keycloak_detector.py 192.168.1.105 8080")
        sys.exit(1)
    
    host = sys.argv[1]
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8080
    
    detector = KeycloakDetector(host, port)
    
    if detector.detect():
        detector.print_report()
    else:
        detector.print_report()
```

### Шаг 3.3: Запуск скрипта

```bash
# Базовое использование
python3 keycloak_detector.py 192.168.1.105 8080

# С указанием портов для сканирования
for port in 8000 8080 8443 9090; do
    python3 keycloak_detector.py 192.168.1.105 $port
done
```

---

## ЧАСТЬ 4: ИСПОЛЬЗОВАНИЕ NUCLEI

### Шаг 4.1: Установка Nuclei

```bash
# Скачайте с GitHub
wget https://github.com/projectdiscovery/nuclei/releases/latest

# Или через Go
go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest

# Проверка
nuclei -version
```

### Шаг 4.2: Создание шаблона для Keycloak

Создайте файл `keycloak-detection.yaml`:

```yaml
id: keycloak-detection
info:
  name: Keycloak Service Detection
  author: security-researcher
  severity: info
  description: Detects Keycloak Identity Server

http:
  - method: GET
    path:
      - "/.well-known/openid-configuration"
      - "/realms/master/protocol/oidc/certs"
      - "/admin/"
    
    matchers:
      - type: status
        status:
          - 200
          - 302
      
      - type: word
        words:
          - "issuer"
          - "authorization_endpoint"
          - "token_endpoint"
          - "keycloak"
        condition: or

  - method: GET
    path:
      - "/realms/master/protocol/saml/descriptor"
    
    matchers:
      - type: status
        status:
          - 200
      
      - type: word
        words:
          - "EntityDescriptor"
          - "keycloak"
        condition: or
```

### Шаг 4.3: Запуск Nuclei

```bash
# Сканирование одного хоста
nuclei -u http://192.168.1.105:8080 -t keycloak-detection.yaml

# Сканирование нескольких портов
nuclei -u http://192.168.1.105:8000,8080,8443,9090 -t keycloak-detection.yaml

# Сохранение результатов
nuclei -u http://192.168.1.105:8080 -t keycloak-detection.yaml -o results.txt
```

---

## ЧАСТЬ 5: ПОЛНОЕ СКАНИРОВАНИЕ (автоматизированное)

### Шаг 5.1: Bash скрипт для полного сканирования

Создайте `keycloak_full_scan.sh`:

```bash
#!/bin/bash

TARGET_HOST=$1
COMMON_PORTS=(8000 8080 8443 9090 80 443)

if [ -z "$TARGET_HOST" ]; then
    echo "Использование: ./keycloak_full_scan.sh <host>"
    exit 1
fi

echo "=========================================="
echo "  KEYCLOAK FULL NETWORK SCAN"
echo "=========================================="
echo "Target: $TARGET_HOST"
echo ""

# Шаг 1: nmap сканирование
echo "[1/3] Сканирование портов с nmap..."
nmap -p $(IFS=,; echo "${COMMON_PORTS[*]}") -sV -sC $TARGET_HOST > nmap_results.txt
cat nmap_results.txt

# Шаг 2: Python детектор
echo ""
echo "[2/3] Запуск Python детектора..."
for port in "${COMMON_PORTS[@]}"; do
    python3 keycloak_detector.py $TARGET_HOST $port 2>/dev/null
done

# Шаг 3: curl проверки
echo ""
echo "[3/3] Проверка ключевых endpoints..."
for port in "${COMMON_PORTS[@]}"; do
    echo "Проверка порта $port:"
    
    # OIDC
    curl -s -o /dev/null -w "OIDC: %{http_code}\n" \
        "http://$TARGET_HOST:$port/.well-known/openid-configuration"
    
    # SAML
    curl -s -o /dev/null -w "SAML: %{http_code}\n" \
        "http://$TARGET_HOST:$port/realms/master/protocol/saml/descriptor"
    
    # Admin
    curl -s -o /dev/null -w "Admin: %{http_code}\n" \
        "http://$TARGET_HOST:$port/admin/"
done

echo ""
echo "=========================================="
echo "Сканирование завершено!"
echo "Результаты сохранены в nmap_results.txt"
echo "=========================================="
```

Использование:

```bash
chmod +x keycloak_full_scan.sh
./keycloak_full_scan.sh 192.168.1.105
```

---

## РЕЗУЛЬТАТЫ ДЛЯ ОТЧЕТА

### Таблица обнаруженных сигнатур:

| Метод | Найдено | Сигнатура | Результат |
|-------|---------|-----------|-----------|
| **nmap -sV** | ✅ | Undertow/2.2.x | Keycloak 26.1.2 |
| **OIDC endpoint** | ✅ | /.well-known/openid-configuration | 200 OK |
| **SAML endpoint** | ✅ | /realms/master/protocol/saml/descriptor | 200 OK |
| **Admin console** | ✅ | /admin/ | 302 Redirect |
| **JWKS endpoint** | ✅ | /realms/master/protocol/openid-connect/certs | 200 OK |
| **Server header** | ✅ | Undertow | Keycloak detected |
| **HTML signature** | ✅ | "keycloak" text | Found in login page |

---

**Готово к использованию! Все скрипты пошагово описаны!** ✅
