# Инструкции для создания релиза

## 📦 Создание релиза на GitHub

### 1. Перейдите на страницу релизов
Откройте: https://github.com/ant1freeze/harbor-scan-tools/releases

### 2. Создайте новый релиз
- Нажмите "Create a new release"
- Выберите тег: `v1.0.0`
- Заголовок: `Harbor Scan Tools v1.0.0`

### 3. Описание релиза
```markdown
# Harbor Scan Tools v1.0.0

## 🚀 Новые возможности

- **Универсальные скрипты** - `scan.sh` и `check.sh` заменяют все предыдущие скрипты
- **Поддержка робот-аккаунтов** - готово для автоматизации
- **Автоматическая пагинация** - работа с любым количеством данных
- **Детальная статистика** - полная информация об уязвимостях
- **Централизованная конфигурация** - все настройки в `harbor.conf`

## 📁 Содержимое релиза

- `scan.sh` - Универсальный скрипт для сканирования
- `check.sh` - Универсальный скрипт для проверки статуса
- `harbor.conf.example` - Шаблон конфигурации
- `README.md` - Полная документация

## 🔧 Быстрый старт

1. Распакуйте архив
2. Скопируйте `harbor.conf.example` в `harbor.conf`
3. Настройте подключение к Harbor
4. Запустите: `./scan.sh --help` или `./check.sh --help`

## 📊 Статистика

- 2 основных скрипта
- Поддержка пагинации API
- Совместимость с Harbor v2.0+
- Готово для production использования
```

### 4. Загрузите архив
- Перетащите файл `release/harbor-scan-tools-v1.0.0.tar.gz` в область "Attach binaries"
- Или нажмите "Choose your files" и выберите архив

### 5. Опубликуйте релиз
- Нажмите "Publish release"

## 📥 Скачивание релиза

После создания релиза архив будет доступен по адресу:
https://github.com/ant1freeze/harbor-scan-tools/releases/download/v1.0.0/harbor-scan-tools-v1.0.0.tar.gz

## 🚀 Развертывание на целевом хосте

```bash
# Скачайте релиз
wget https://github.com/ant1freeze/harbor-scan-tools/releases/download/v1.0.0/harbor-scan-tools-v1.0.0.tar.gz

# Распакуйте архив
tar -xzf harbor-scan-tools-v1.0.0.tar.gz

# Настройте конфигурацию
cp harbor.conf.example harbor.conf
# Отредактируйте harbor.conf под ваше окружение

# Сделайте скрипты исполняемыми
chmod +x scan.sh check.sh

# Протестируйте
./scan.sh --help
./check.sh --help
```
