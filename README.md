# Harbor Scan Tools

Набор скриптов для работы с Harbor Registry: получение проектов, репозиториев, образов и запуск сканирования уязвимостей.

## 🚀 Возможности

- 📋 Получение списка всех проектов, репозиториев и образов
- 🔍 Запуск сканирования уязвимостей для образов
- 📊 Мониторинг статуса сканирования
- 🎯 Сканирование конкретных проектов
- 🔄 Принудительное пересканирование

## 📁 Структура проекта

```
harbor_scan_run/
├── harbor_projects.py          # Python скрипт для получения информации о проектах
├── harbor_scan.py              # Python скрипт для сканирования (с проблемой CSRF)
├── harbor_scan_project.py      # Python скрипт для сканирования конкретного проекта
├── scan_all_images.sh          # Bash скрипт для сканирования всех образов
├── scan_project.sh             # Bash скрипт для сканирования конкретного проекта
├── check_scan_status.sh        # Bash скрипт для проверки статуса сканирования
├── requirements.txt            # Python зависимости
└── README.md                   # Документация
```

## 🛠️ Установка

1. Клонируйте репозиторий:
```bash
git clone <repository-url>
cd harbor_scan_run
```

2. Создайте виртуальное окружение (для Python скриптов):
```bash
python3 -m venv venv
source venv/bin/activate  # Linux/Mac
# или
venv\Scripts\activate     # Windows
```

3. Установите зависимости:
```bash
pip install -r requirements.txt
```

## 📖 Использование

### Получение информации о проектах

#### Python скрипт:
```bash
# Активируйте виртуальное окружение
source venv/bin/activate

# Краткая сводка по проектам
python harbor_projects.py

# Детальная информация
python harbor_projects.py --detailed

# Только репозитории
python harbor_projects.py --repos-only

# Все образы
python harbor_projects.py --artifacts

# JSON вывод
python harbor_projects.py --output json

# Сохранить в файл
python harbor_projects.py --save results.txt
```

### Сканирование образов

#### Bash скрипты (рекомендуется):

**Сканирование всех образов:**
```bash
./scan_all_images.sh
```

**Сканирование конкретного проекта:**
```bash
# Обычное сканирование (пропускает уже отсканированные)
./scan_project.sh library
./scan_project.sh test_project

# Принудительное сканирование (всегда запускает)
./scan_project.sh library --force
./scan_project.sh test_project --force
```

**Проверка статуса сканирования:**
```bash
./check_scan_status.sh
```

#### Python скрипты:

**Сканирование конкретного проекта:**
```bash
source venv/bin/activate

# Обычное сканирование
python harbor_scan_project.py library

# Принудительное сканирование
python harbor_scan_project.py library --force
```

## ⚙️ Настройка

По умолчанию скрипты настроены для работы с Harbor на `http://localhost:8080` с учетными данными `admin:Harbor12345`.

Для изменения настроек используйте параметры командной строки:

```bash
# Изменить URL Harbor
python harbor_projects.py --url http://harbor.example.com:8080

# Изменить учетные данные
python harbor_projects.py --username myuser --password mypass

# Для bash скриптов отредактируйте переменные в начале файла
```

## 📊 Примеры вывода

### Список проектов:
```
📊 Сводка по проектам:
Всего проектов: 2

№   Название                       Публичный  Создан               Обновлен            
------------------------------------------------------------------------------------------
1   library                        Нет        2025-10-06T14:02:25  2025-10-06T14:02:25 
2   test_project                   Нет        2025-10-13T08:56:08  2025-10-13T08:56:08 
```

### Статус сканирования:
```
🔍 Проверка статуса сканирования образов в Harbor...

🏗️  Проект: library
✅ library/golang@sha256:64749ebac738... - Завершено (Уязвимостей: 239, H:1 M:1 L:214)
🔄 library/postgres@sha256:ef202e91a193... - Выполняется
```

## 🔧 Требования

- **Harbor Registry** v2.0+
- **Python** 3.6+
- **jq** (для bash скриптов)
- **curl**

## 🐛 Известные проблемы

- Python скрипт `harbor_scan.py` имеет проблемы с CSRF токенами в Harbor
- Рекомендуется использовать bash скрипты для сканирования

## 📝 Лицензия

MIT License

## 🤝 Вклад в проект

1. Fork репозиторий
2. Создайте ветку для новой функции (`git checkout -b feature/amazing-feature`)
3. Зафиксируйте изменения (`git commit -m 'Add amazing feature'`)
4. Отправьте в ветку (`git push origin feature/amazing-feature`)
5. Откройте Pull Request

## 📞 Поддержка

Если у вас есть вопросы или проблемы, создайте issue в репозитории.
