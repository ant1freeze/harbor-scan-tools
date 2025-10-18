#!/bin/bash

# Скрипт для запуска сканирования всех образов в Harbor
# Использует curl для обхода проблем с CSRF токенами

# Загружаем конфигурацию
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/harbor.conf"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "❌ Файл конфигурации не найден: $CONFIG_FILE"
    echo "Создайте файл harbor.conf с настройками подключения к Harbor"
    exit 1
fi

# Проверяем аргументы
if [ $# -eq 0 ]; then
    echo "⚠️  ВНИМАНИЕ: Этот скрипт запустит сканирование ВСЕХ образов во ВСЕХ проектах!"
    echo "   Это может занять очень много времени и ресурсов."
    echo ""
    echo "Использование: $0 --force"
    echo ""
    echo "Для запуска используйте: $0 --force"
    echo "Для сканирования конкретного проекта используйте: ./scan_project.sh <project_name>"
    exit 1
fi

if [ "$1" != "--force" ]; then
    echo "❌ Ошибка: Для запуска сканирования всех образов используйте флаг --force"
    echo "   $0 --force"
    exit 1
fi

echo "🔍 Запуск сканирования всех образов в Harbor..."
echo "⚠️  ВНИМАНИЕ: Это может занять очень много времени!"
echo ""
echo "Вы уверены, что хотите продолжить? (yes/no)"
read -r confirmation

if [ "$confirmation" != "yes" ]; then
    echo "❌ Операция отменена пользователем"
    exit 0
fi

echo "🚀 Начинаем сканирование..."

# Функция для запуска сканирования образа
scan_artifact() {
    local project=$1
    local repo=$2
    local digest=$3
    
    echo "📦 Сканирование: $project/$repo@${digest:0:19}..."
    
    response=$(curl -s -X POST -u "$USERNAME:$PASSWORD" \
        -H "Content-Type: application/json" \
        -H "X-Requested-With: XMLHttpRequest" \
        -d '{}' \
        "$HARBOR_URL/api/v2.0/projects/$project/repositories/$repo/artifacts/$digest/scan")
    
    if [ $? -eq 0 ]; then
        echo "✅ Сканирование запущено для $project/$repo@${digest:0:19}..."
    else
        echo "❌ Ошибка сканирования для $project/$repo@${digest:0:19}..."
    fi
}

# Получаем все проекты
echo "📋 Получение списка проектов..."
projects=$(curl -s -u "$USERNAME:$PASSWORD" "$HARBOR_URL/api/v2.0/projects" | jq -r '.[].name')

total_scanned=0

for project in $projects; do
    echo ""
    echo "🏗️  Проект: $project"
    
    # Получаем репозитории проекта
    repos=$(curl -s -u "$USERNAME:$PASSWORD" "$HARBOR_URL/api/v2.0/projects/$project/repositories" | jq -r '.[].name')
    
    for repo in $repos; do
        repo_name=$(echo $repo | sed "s/$project\///")
        echo "  📦 Репозиторий: $repo_name"
        
        # Получаем артефакты репозитория
        artifacts=$(curl -s -u "$USERNAME:$PASSWORD" "$HARBOR_URL/api/v2.0/projects/$project/repositories/$repo_name/artifacts" | jq -r '.[].digest')
        
        for digest in $artifacts; do
            scan_artifact "$project" "$repo_name" "$digest"
            total_scanned=$((total_scanned + 1))
            sleep 1  # Небольшая пауза между запросами
        done
    done
done

echo ""
echo "📊 Итого отправлено запросов на сканирование: $total_scanned"
echo "✅ Готово!"
